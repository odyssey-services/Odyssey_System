// Combat HUD — Phase 3A scene-selection controller (OBR-bound, thin).
//
// Runs in the BACKGROUND context alongside combatHudOverlayController. It:
//   1. reads the viewer (OBR player id + role) and room/scene context;
//   2. resolves the current OBR selection → a normalized selection state via the
//      pure adapter (token link + runtime bundle through the existing Supabase
//      RPCs — no token metadata, no new RPCs);
//   3. broadcasts a TRIMMED selection payload (LOCAL) to the module iframes;
//   4. replays the latest payload to freshly-mounted iframes on request;
//   5. notifies the overlay controller of status changes so it can show/hide the
//      ready-only modules — WITHOUT re-opening popovers on every selection.
//
// All heavy lifting (state shape, ownership, stale-request gate) lives in the
// pure selectionState/sceneSelectionAdapter modules. This file only wires OBR.

import OBR from "@owlbear-rodeo/sdk";
import {
  subscribePlayerChanges,
  subscribeSceneItems,
  getPlayerInfo,
  getRoomSceneContext,
  getSelectedTokenIds,
} from "../../bridge/obrBridge.js";
import { loadRoomSupabaseSettings, hasSupabaseSettings } from "../../bridge/settingsBridge.js";
import { getSceneTokenLinks, getCharacterRuntimeBundle } from "../../api/characterPlacementApi.js";
import { loadWeaponProfileMagazine, getCharacterArmory, switchWeaponFireMode, switchActiveWeapon } from "../../api/weaponApi.js";
import { performAttack, executeAction } from "../../api/combatApi.js";
import { getCharacterInventory } from "../../api/inventoryApi.js";
import { resolveReloadMagazineId, normalizeReloadRpcResult } from "./reloadPolicy.js";
import { normalizeFireModeRpcResult } from "./fireModePolicy.js";
import { evaluateBasicAttack, buildAttackRequestSignature, isAttackResultStale } from "../combat/basicAttackPolicy.js";
import { buildBasicAttackCtx, buildDirectAbilityAttackCtx, resolveAttack } from "../combat/basicAttackPayload.js";
import { evaluateDirectAbilityAttack, isDirectAbilityAttackResultStale } from "../combat/directAbilityAttackPolicy.js";
import { evaluateInstantAbilityExecution, isInstantAbilityResultStale } from "../combat/instantAbilityPolicy.js";
import { resolveInstantAbilityExecution } from "../combat/instantAbilityPayload.js";
import { evaluateDirectedAbilityExecution, isDirectedAbilityResultStale } from "../combat/directedAbilityPolicy.js";
import { resolveDirectedAbilityExecution } from "../combat/directedAbilityPayload.js";
import { isDirectAttackAbility, isInstantSelfAbility, isDirectedTargetAbility } from "../abilities/abilityAvailabilityPolicy.js";
import { buildAttackResolutionTrace, buildRollResolutionDetails } from "../combat/attackResolutionTrace.js";
import { createSelectedWeaponMemory, resolveStoredWeaponId } from "./selectedWeaponMemory.js";
import { createArmedTechniqueMemory } from "./armedTechniqueMemory.js";
import {
  appendCombatLogEntry,
  buildAttackLogEntry,
  buildAbilityExecutionLogEntry,
  buildDirectedAbilityLogEntry,
  buildReloadLogEntry,
  buildFireModeLogEntry,
} from "../log/combatResultLogPolicy.js";
import { getZoneLabel, DEFAULT_PROFILE_ID } from "../targeting/targetProfiles.js";
import { logDebugEvent } from "../debug/debugLogStore.js";
import { setupCombatSessionController } from "../session/combatSessionController.js";
import { subscribeMoveToolMessages, MOVE_TOOL_EVENTS } from "../../movement/moveToolBridge.js";
import { setupQuickbarController } from "../abilities/quickbarController.js";
import { mapCombatRuntimeToSession } from "../session/combatSessionMapper.js";
import { sessionAttackGate, sessionReloadGate, expectedVersionOf } from "../session/combatSessionPolicy.js";
import { buildSwitchActiveWeaponPayload, resolveWeaponSwitchErrorMessage } from "../session/weaponSwitchPayload.js";

// Phase 4.1A: perform_attack error codes specific to an armed attack
// technique (migration 100) — used only to classify a Debug Console event,
// never to change attack gating (the server is the sole authority there).
const ARMED_TECHNIQUE_ERROR_CODES = new Set([
  "ARMED_ACTION_INVALID",
  "ARMED_ACTION_ON_COOLDOWN",
  "NOT_ENOUGH_PSI",
  "NOT_ENOUGH_CHARGES",
  "WEAPON_REQUIREMENT_NOT_MET",
  "TARGET_REQUIREMENT_NOT_MET",
  "ACTION_STACK_CONFLICT",
  "ACTION_EFFECT_NOT_IMPLEMENTED",
]);
import { BC_HUD_COMMAND, BC_HUD_SELECTION, BC_HUD_SELECTION_REQUEST, BC_HUD_TARGETING_COMMAND } from "../overlay/overlayConstants.js";
import { createSceneSelectionAdapter } from "./sceneSelectionAdapter.js";
import { buildCanonicalArmory, pickActiveWeapon } from "../runtime/runtimeBundleMapper.js";
import { buildBroadcastPayload, normalizeViewer } from "./selectionState.js";
import { mutateSupabaseRows } from "../../bridge/supabaseBridge.js";
import { createDebouncedRefreshScheduler, singleFlightRuntimeRefresh } from "../runtime/runtimeRefreshCoordinator.js";
import { normalizeRpcError } from "../../utils/rpcErrorNormalizer.js";

const SCENE_RERESOLVE_DEBOUNCE_MS = 600;
const HUD_LIGHT_RUNTIME_SECTIONS = Object.freeze(["summary", "combat", "armory", "abilities", "effects"]);
const LIGHT_RUNTIME_RETRY_DELAY_MS = 350;
const SELECTED_RUNTIME_DEBOUNCE_MS = 200;
const TRANSIENT_EMPTY_SELECTION_GRACE_MS = 500;
const SELECTION_RESOLVE_TIMEOUT_MS = 5000;

/**
 * @param {{
 *   onSelectionState?: (payload:object) => (void|Promise<void>),
 *   shouldDeferSelection?: () => boolean,
 * }} [hooks]
 * @returns {() => void} cleanup
 */
export function setupSceneSelection(hooks = {}) {
  if (typeof OBR === "undefined" || OBR.isAvailable === false) return () => {};

  const onSelectionState = typeof hooks.onSelectionState === "function" ? hooks.onSelectionState : null;
  const shouldDeferSelection = typeof hooks.shouldDeferSelection === "function" ? hooks.shouldDeferSelection : () => false;
  let disposed = false;
  let lastPayload = null;
  let lastState = null;
  let sceneTimer = null;
  let selectedRuntimeReason = "startup";
  let currentSelectionIds = [];
  let pendingSelectionIds = [];
  let lastObservedSelectionIds = [];
  let transientEmptySelectionTimer = null;
  let selectionResolveGeneration = 0;
  let lastResolvedCharacterId = null;
  let lastResolvedTokenId = null;
  let skillAdminDeleteInFlight = null;
  let refetchCurrentPromise = null;
  let refetchCurrentQueued = false;
  let lastRefetchAt = 0;
  let combatRuntimePending = false;
  const heavyRuntimeCache = new Map();
  // Phase 3D.1: controller-local, session-scoped "last weapon per character"
  // memory — see selectedWeaponMemory.js for why this exists. We still keep it
  // for quick-action / companion continuity, but the active weapon itself now
  // always comes from the server-authoritative armory snapshot.
  const selectedWeaponMemory = createSelectedWeaponMemory();
  // Phase 4.1A: per-character "armed attack technique" memory — same lifecycle
  // as the rest of the HUD selection state (ephemeral, session-scoped, never persisted). See
  // armedTechniqueMemory.js for the max-1-until-stackGroup rule.
  const armedTechniqueMemory = createArmedTechniqueMemory();
  // Phase 3D.1: the real (server-result-only) local Combat Log — newest first,
  // capped, never persisted. Deliberately OUTSIDE `ephemeral` (not reset per
  // character) — it's a running session history, not per-character state.
  let combatLog = [];
  function pushLog(entry) { combatLog = appendCombatLogEntry(combatLog, entry); }
  const ephemeral = {
    characterId: null,
    selectedWeaponId: null,
    selectedReloadMagazineId: null,
    weaponSelectorOpen: false,
    preparedAction: null,
    targeting: { mode: "none", selectedTargetIds: [], selectedBodyPartId: "torso" },
    commandStatus: null,
    // Raw { ok, error, message } from the last loadWeaponProfileMagazine RPC
    // call, so ?debug=1 can show the server's actual verdict — see
    // buildReloadDebugInfo() in selectionState.js.
    reloadRpcResult: null,
    // Fire Mode v1: companion-popover open flag (ephemeral, like
    // weaponSelectorOpen) + the last switch_weapon_fire_mode outcome for
    // ?debug=1 — see buildFireModeDebugInfo() in selectionState.js. There is
    // NO ephemeral "selected fire mode id" override: the current mode always
    // comes fresh from armory (weapon.fireMode.selectedId), so switching
    // weapons away and back never carries a mode over from a different weapon.
    fireModeSelectorOpen: false,
    fireModeRpcResult: null,
    // Basic Weapon Attack v1: true only for the duration of an in-flight
    // perform_attack call — blocks double-submit (see handleCommand's
    // "execute" branch) and disables the Action button client-side.
    basicAttackInFlight: false,
    // Last outcome for ?debug=1 / the commandStatus toast — never a
    // fabricated hit/miss/damage, only what buildBasicAttackDebugInfo()
    // forwards from the real server response or exception.
    basicAttackResult: null,
    // Phase 4.1B.0: which direct-ability-attack request (characterActionId,
    // never a boolean) is currently in flight — per-ability, not a whole-
    // quickbar lock, so an unrelated ability/weapon attack stays interactive
    // while one request resolves.
    pendingDirectAbilityActionId: null,
    directAbilityAttackResult: null,
    // Phase 4.1B.1: same per-ability in-flight tracking, for the SEPARATE
    // instant/self ability execution command (never touches target/zone).
    pendingInstantAbilityActionId: null,
    instantAbilityExecutionResult: null,
    // Phase 4.1B.2: same per-ability in-flight tracking, for the SEPARATE
    // directed-target ability execution command — requires a selected
    // target, never a body zone.
    pendingDirectedAbilityActionId: null,
    directedAbilityExecutionResult: null,
  };
  // ephemeral.debugEnabled gates the reload/fireMode/basicAttack debug sub-objects
  // in selectionState.js (an unrelated diagnostics feature) — kept independent of
  // the Debug Console, which is always enabled via startDebugConsole().
  let debugEnabled = false;
  try { debugEnabled = new URLSearchParams(window.location.search).get("debug") === "1"; } catch (_e) { debugEnabled = false; }
  /** @type {Array<() => void>} */
  const cleanups = [];
  const queuedCombatActionKeys = new Set();
  const queuedCombatActionCharacters = new Set();
  const activeCombatActionKeys = new Set();
  const activeCombatActionCharacters = new Set();
  const characterActionQueues = new Map();
  const selectionRefreshScheduler = createDebouncedRefreshScheduler(
    (selectionIds, reason = "selection-debounced") => startSelectionResolve(selectionIds, reason),
    SELECTED_RUNTIME_DEBOUNCE_MS,
  );

  function clearTransientEmptySelectionTimer() {
    if (!transientEmptySelectionTimer) return false;
    clearTimeout(transientEmptySelectionTimer);
    transientEmptySelectionTimer = null;
    return true;
  }

  function waitMs(ms) {
    return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms) || 0)));
  }

  function normalizeOutcomeCode(result) {
    return String(result?.code ?? result?.error ?? "").trim() || null;
  }

  function buildCombatActionKey(characterId, actionId, fallbackType = "ability") {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return null;
    const normalizedActionId = String(actionId ?? "").trim() || String(fallbackType ?? "ability").trim() || "ability";
    return `${normalizedCharacterId}:${normalizedActionId}`;
  }

  function isCombatActionBusy(characterId, actionId, fallbackType = "ability") {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return false;
    const key = buildCombatActionKey(normalizedCharacterId, actionId, fallbackType);
    return queuedCombatActionCharacters.has(normalizedCharacterId) || (key ? queuedCombatActionKeys.has(key) : false);
  }

  function markCombatActionStarted(characterId, actionId, fallbackType = "ability") {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return null;
    const key = buildCombatActionKey(normalizedCharacterId, actionId, fallbackType);
    queuedCombatActionCharacters.add(normalizedCharacterId);
    if (key) queuedCombatActionKeys.add(key);
    return key;
  }

  function markCombatActionActive(characterId, actionKey = null) {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return;
    activeCombatActionCharacters.add(normalizedCharacterId);
    if (actionKey) activeCombatActionKeys.add(actionKey);
  }

  function markCombatActionFinished(characterId, actionKey = null) {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return;
    if (actionKey) {
      queuedCombatActionKeys.delete(actionKey);
      activeCombatActionKeys.delete(actionKey);
    }
    const prefix = `${normalizedCharacterId}:`;
    for (const key of queuedCombatActionKeys) {
      if (key.startsWith(prefix)) {
        break;
      }
    }
    let hasQueued = false;
    for (const key of queuedCombatActionKeys) {
      if (key.startsWith(prefix)) {
        hasQueued = true;
        break;
      }
    }
    if (!hasQueued) queuedCombatActionCharacters.delete(normalizedCharacterId);

    let hasActive = false;
    for (const key of activeCombatActionKeys) {
      if (key.startsWith(prefix)) {
        hasActive = true;
        break;
      }
    }
    if (!hasActive) activeCombatActionCharacters.delete(normalizedCharacterId);
  }

  function buildCharacterQueueKey(characterId, operation = "generic", encounterId = null) {
    const normalizedCharacterId = String(characterId ?? "").trim() || "no-character";
    const normalizedOperation = String(operation ?? "").trim() || "generic";
    const normalizedEncounterId = String(encounterId ?? "").trim() || "no-encounter";
    return `${normalizedEncounterId}:${normalizedCharacterId}:${normalizedOperation}`;
  }

  async function runCharacterActionQueue(characterId, work, {
    queueKey = null,
  } = {}) {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId || typeof work !== "function") {
      return typeof work === "function" ? work() : undefined;
    }

    const normalizedQueueKey = String(queueKey ?? "").trim() || buildCharacterQueueKey(normalizedCharacterId, "generic");
    const previous = characterActionQueues.get(normalizedCharacterId) ?? null;
    if (previous) {
      logDebugEvent(
        "runtime",
        "character-action-queue-wait",
        {
          characterId: normalizedCharacterId,
          queueKey: normalizedQueueKey,
          reason: "another action/refresh is running",
        },
        true,
        "pending",
      );
    }

    const runPromise = (previous ?? Promise.resolve())
      .catch(() => {})
      .then(async () => work());
    const settledPromise = runPromise.catch(() => {});
    characterActionQueues.set(normalizedCharacterId, settledPromise);

    try {
      return await runPromise;
    } finally {
      if (characterActionQueues.get(normalizedCharacterId) === settledPromise) {
        characterActionQueues.delete(normalizedCharacterId);
      }
      logDebugEvent(
        "runtime",
        "character-action-queue-release",
        {
          characterId: normalizedCharacterId,
          queueKey: normalizedQueueKey,
        },
        true,
      );
    }
  }

  async function executeCombatAbilityWithRetry(executor, {
    characterId,
    actionId,
    debugAction,
    retryDelaysMs = [750, 1500],
  } = {}) {
    let outcome = await executor();

    for (let index = 0; index < retryDelaysMs.length; index += 1) {
      if (normalizeOutcomeCode(outcome) !== "ACTION_BUSY_RETRY") {
        break;
      }
      const retryDelayMs = Math.max(0, Number(retryDelaysMs[index]) || 0);
      logDebugEvent(
        "abilities",
        debugAction || "ability-execute-retry",
        {
          characterId: String(characterId ?? "").trim() || null,
          characterActionId: String(actionId ?? "").trim() || null,
          reason: "ACTION_BUSY_RETRY",
          retryAttempt: index + 1,
          retryDelayMs,
          stage: outcome?.raw?.stage ?? outcome?.stage ?? null,
        },
        true,
        "pending",
      );
      await waitMs(retryDelayMs);
      outcome = await executor();
    }

    return outcome;
  }

  async function refreshCombatSessionSafe(sessionController, command) {
    if (!sessionController) return;
    try {
      await sessionController.refresh();
    } catch (error) {
      logDebugEvent("session", "refresh-result", {
        command,
        message: String(error?.message ?? error ?? "Unable to refresh combat session."),
      }, false);
    }
  }

  async function waitForCombatActionIdle(characterId, timeoutMs = 3000) {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return;
    const deadline = Date.now() + Math.max(0, Number(timeoutMs) || 0);
    while (activeCombatActionCharacters.has(normalizedCharacterId) && Date.now() < deadline) {
      await waitMs(50);
    }
  }

  function setCombatRuntimePending(next, reason = null) {
    const normalized = next === true;
    if (combatRuntimePending === normalized) return;
    combatRuntimePending = normalized;
    if (normalized && reason) {
      logDebugEvent("session", "runtime-sync-pending", { reason }, true, "pending");
    }
    if (!normalized && reason) {
      logDebugEvent("session", "runtime-sync-ready", { reason }, true);
    }
    if (lastState) publishState(lastState);
  }

  function getHeavyRuntimeCache(characterId) {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return null;
    return heavyRuntimeCache.get(normalizedCharacterId) ?? null;
  }

  function writeHeavyRuntimeCache(characterId, nextPatch = {}) {
    const normalizedCharacterId = String(characterId ?? "").trim();
    if (!normalizedCharacterId) return null;
    const previous = getHeavyRuntimeCache(normalizedCharacterId) ?? {};
    const nextValue = {
      ...previous,
      ...nextPatch,
      updatedAt: Date.now(),
    };
    if (!nextValue.canonicalArmory && nextValue.armory) {
      nextValue.canonicalArmory = buildCanonicalArmory(nextValue.armory, nextValue.inventory);
    }
    heavyRuntimeCache.set(normalizedCharacterId, nextValue);
    return nextValue;
  }

  function hydrateBundleWithHeavyCache(bundle, characterId) {
    if (!bundle || typeof bundle !== "object") return bundle;
    const cacheEntry = getHeavyRuntimeCache(characterId);
    const canonicalArmory = cacheEntry?.canonicalArmory ?? null;
    if (!canonicalArmory) return bundle;
    const merged = { ...bundle, armory: canonicalArmory };
    if (merged.sections && typeof merged.sections === "object") {
      merged.sections = { ...merged.sections, armory: canonicalArmory };
    }
    return merged;
  }

  function broadcast(payload) {
    try { OBR.broadcast.sendMessage(BC_HUD_SELECTION, payload, { destination: "LOCAL" }); } catch (_e) { /* ignore */ }
  }

  async function readLiveSelectionIds(fallbackSelection = []) {
    try {
      const liveSelection = await getSelectedTokenIds();
      if (Array.isArray(liveSelection)) {
        return liveSelection
          .map((value) => String(value ?? "").trim())
          .filter(Boolean);
      }
    } catch (_error) {
      /* best effort */
    }
    return Array.isArray(fallbackSelection)
      ? fallbackSelection.map((value) => String(value ?? "").trim()).filter(Boolean)
      : [];
  }

  async function init() {
    const [player, context, settings] = await Promise.all([
      getPlayerInfo(),
      getRoomSceneContext(),
      loadRoomSupabaseSettings(),
    ]);
    if (disposed) return;

    let viewer = normalizeViewer({ playerId: player.id, role: player.role });
    const configured = hasSupabaseSettings(settings);

    // Phase 3E.0: live combat-session layer. The session controller owns ALL
    // session fetching/commands; this controller only keeps the latest raw
    // runtime so buildBroadcastPayload can map it (via the single shared
    // mapper) into snapshot.combatSession on every publish.
    let sessionRuntime = null;
    const sessionController = configured
      ? setupCombatSessionController({
          context,
          settings,
          getViewer: () => viewer,
          onSessionRuntime: (runtime) => {
            const previousWasActive = sessionRuntime?.encounter?.status === "active";
            const nextIsActive = runtime?.encounter?.status === "active";
            sessionRuntime = runtime;
            if (lastState) publishState(lastState);
            if (previousWasActive && !nextIsActive && ephemeral.characterId) {
              scheduleLiveSelectionResolve("combat-ended", { forceResolve: true });
              void quickbarController?.refresh?.();
            }
          },
        })
      : null;
    if (sessionController) cleanups.push(() => sessionController.cleanup());

    // Bugfix pack: immediate HUD refresh after Tactical Move. The move tool's
    // OWN accepted-movement result already carries a fresh authoritative
    // combat runtime (see movement/moveToolController.js's
    // finalizeMutationSuccess) — this listener is the only piece that was
    // missing: nothing under hud/ ever consumed MOVE_TOOL_EVENTS.Applied.
    // Reuses the session controller's own applyExternalRuntime() (same
    // apply path + freshness guard end-turn/GM controls already go through)
    // rather than forking a second runtime-apply mechanism for movement.
    if (sessionController) {
      const unsubscribeMoveTool = await subscribeMoveToolMessages((event) => {
        if (event.type !== MOVE_TOOL_EVENTS.Applied) return;
        const payload = event.payload ?? {};
        if (payload.source !== "combat-movement" || !payload.runtime) return;
        sessionController.applyExternalRuntime(payload.runtime, "tactical-move");
        if (String(payload.characterId ?? "").trim() && String(payload.characterId ?? "").trim() === String(ephemeral.characterId ?? "").trim()) {
          scheduleLiveSelectionResolve("tactical-move-applied", { forceResolve: true });
          void quickbarController?.refresh?.();
        }
      });
      if (disposed) { unsubscribeMoveTool?.(); } else { cleanups.push(unsubscribeMoveTool); }
    }

    // Phase 4.0b: abilities/quickbar layer. The quickbar controller owns the
    // per-character quick-actions runtime (library + persisted layout); this
    // controller only keeps the latest SAFE mapped runtime so buildBroadcastPayload
    // folds it into snapshot.quickbar for the Skills block. The editor iframe gets
    // the same runtime via the controller's own BC_HUD_ABILITIES broadcast.
    let abilitiesRuntime = null;
    const quickbarController = configured
      ? setupQuickbarController({
          settings,
          getViewer: () => viewer,
          getSelectedCharacterId: () => ephemeral.characterId ?? null,
          onRuntime: (runtime) => {
            abilitiesRuntime = runtime;
            if (lastState) publishState(lastState);
          },
        })
      : null;
    if (quickbarController) cleanups.push(() => quickbarController.cleanup());

    /** Hotfix: the execute-direct-ability handler used to look up
     *  `ephemeral.abilitiesRuntime`, a field that has never existed —
     *  abilitiesRuntime is kept ONLY as this controller-level closure
     *  variable (assigned above in quickbarController's onRuntime callback)
     *  and handed to buildBroadcastPayload as its own separate argument, not
     *  folded onto `ephemeral`. The old lookup therefore always returned
     *  null, and every direct-attack click blocked as INVALID_ABILITY before
     *  ever reaching the RPC. This helper reads the REAL source. */
    function findQuickActionByCharacterActionId(characterActionId) {
      const id = String(characterActionId ?? "").trim();
      if (!id) return null;
      return (abilitiesRuntime?.quickActions ?? [])
        .find((action) => String(action?.characterActionId ?? "") === id) ?? null;
    }

    /** Latest mapped session for the currently selected character — used only
     *  for the client-side pre-gates + request payload context; the server
     *  re-checks everything. */
    function currentMappedSession() {
      return mapCombatRuntimeToSession(sessionRuntime, {
        viewerPlayerId: viewer?.playerId ?? null,
        viewerIsGm: String(viewer?.role ?? "").toUpperCase() === "GM",
        selectedCharacterId: ephemeral.characterId,
      });
    }

    function buildLightRuntimeKey(characterId, encounterId = null, sections = HUD_LIGHT_RUNTIME_SECTIONS) {
      const normalizedCharacterId = String(characterId ?? "").trim() || "no-character";
      const normalizedEncounterId = String(encounterId ?? "").trim() || "no-encounter";
      const normalizedSections = Array.isArray(sections) ? sections.join(",") : String(sections ?? "");
      return `${normalizedCharacterId}:light:${normalizedSections}:${normalizedEncounterId}`;
    }

    async function fetchLightRuntimeBundle(characterId, reason = "selection-runtime") {
      const selectedSession = characterId && characterId === ephemeral.characterId
        ? currentMappedSession()
        : null;
      const encounterId = selectedSession?.exists
        ? String(selectedSession.id ?? "").trim() || null
        : null;
      const key = buildLightRuntimeKey(characterId, encounterId);
      const startedAt = Date.now();
      let deduped = false;
      const refreshPromise = singleFlightRuntimeRefresh(
        key,
        async () => {
          logDebugEvent("selection", "runtime-refresh-start", {
            characterId,
            mode: "light",
            reason,
            encounterId,
          }, true, "pending");
          let attempt = 0;
          while (attempt < 2) {
            try {
              const bundle = await getCharacterRuntimeBundle(
                { character_id: characterId, sections: HUD_LIGHT_RUNTIME_SECTIONS },
                settings,
              );
              return hydrateBundleWithHeavyCache(bundle, characterId);
            } catch (error) {
              const normalized = normalizeRpcError(error);
              attempt += 1;
              if (normalized.error === "STATEMENT_TIMEOUT" && normalized.retryable && attempt < 2) {
                await waitMs(LIGHT_RUNTIME_RETRY_DELAY_MS);
                continue;
              }
              throw error;
            }
          }
          return null;
        },
        {
          onDeduped: () => {
            deduped = true;
            logDebugEvent("selection", "runtime-refresh-deduped", {
              characterId,
              mode: "light",
              reason,
              encounterId,
            }, true);
          },
        },
      );
      if (deduped) {
        return refreshPromise;
      }
      return refreshPromise
        .then((bundle) => {
          logDebugEvent("selection", "runtime-refresh-result", {
            characterId,
            mode: "light",
            reason,
            encounterId,
            ok: bundle?.ok !== false,
            deduped: false,
            elapsedMs: Date.now() - startedAt,
          }, bundle?.ok !== false);
          return bundle;
        })
        .catch((error) => {
          const normalized = normalizeRpcError(error);
          logDebugEvent("selection", "runtime-refresh-result", {
            characterId,
            mode: "light",
            reason,
            encounterId,
            ok: false,
            deduped: false,
            error: normalized.error,
            retryable: normalized.retryable,
            elapsedMs: Date.now() - startedAt,
            message: normalized.message,
          }, false);
          throw error;
        });
    }

    async function refreshHeavyCharacterData(characterId, {
      reason = "heavy-runtime",
      encounterId = null,
      armory = false,
      inventory = false,
    } = {}) {
      const normalizedCharacterId = String(characterId ?? "").trim();
      if (!normalizedCharacterId || (!armory && !inventory)) return getHeavyRuntimeCache(normalizedCharacterId);

      const nextPatch = {};

      if (armory) {
        const armoryStartedAt = Date.now();
        try {
          logDebugEvent("runtime", "heavy-fetch-start", {
            characterId: normalizedCharacterId,
            panel: "armory",
            reason,
          }, true, "pending");
          const armoryResult = await singleFlightRuntimeRefresh(
            `${normalizedCharacterId}:heavy:armory:${String(encounterId ?? "").trim() || "no-encounter"}`,
            () => getCharacterArmory(normalizedCharacterId, settings, encounterId),
          );
          nextPatch.armory = armoryResult;
          logDebugEvent("runtime", "heavy-fetch-result", {
            characterId: normalizedCharacterId,
            panel: "armory",
            reason,
            ok: armoryResult?.ok !== false,
            elapsedMs: Date.now() - armoryStartedAt,
          }, armoryResult?.ok !== false);
        } catch (error) {
          const normalized = normalizeRpcError(error);
          logDebugEvent("runtime", "heavy-fetch-failed", {
            characterId: normalizedCharacterId,
            panel: "armory",
            reason,
            error: normalized.error,
            retryable: normalized.retryable,
            elapsedMs: Date.now() - armoryStartedAt,
            message: normalized.message,
          }, false);
        }
      }

      if (inventory) {
        const inventoryStartedAt = Date.now();
        try {
          logDebugEvent("runtime", "heavy-fetch-start", {
            characterId: normalizedCharacterId,
            panel: "inventory",
            reason,
          }, true, "pending");
          const inventoryResult = await singleFlightRuntimeRefresh(
            `${normalizedCharacterId}:heavy:inventory`,
            () => getCharacterInventory(normalizedCharacterId, settings),
          );
          nextPatch.inventory = inventoryResult;
          logDebugEvent("runtime", "heavy-fetch-result", {
            characterId: normalizedCharacterId,
            panel: "inventory",
            reason,
            ok: inventoryResult?.ok !== false,
            elapsedMs: Date.now() - inventoryStartedAt,
          }, inventoryResult?.ok !== false);
        } catch (error) {
          const normalized = normalizeRpcError(error);
          logDebugEvent("runtime", "heavy-fetch-failed", {
            characterId: normalizedCharacterId,
            panel: "inventory",
            reason,
            error: normalized.error,
            retryable: normalized.retryable,
            elapsedMs: Date.now() - inventoryStartedAt,
            message: normalized.message,
          }, false);
        }
      }

      if (Object.keys(nextPatch).length === 0) {
        return getHeavyRuntimeCache(normalizedCharacterId);
      }

      if (nextPatch.armory || nextPatch.inventory) {
        const previous = getHeavyRuntimeCache(normalizedCharacterId) ?? {};
        nextPatch.canonicalArmory = buildCanonicalArmory(
          nextPatch.armory ?? previous.armory ?? null,
          nextPatch.inventory ?? previous.inventory ?? null,
        );
      }

      return writeHeavyRuntimeCache(normalizedCharacterId, nextPatch);
    }

    function normalizeSelectionIds(rawSelectionIds) {
      return Array.isArray(rawSelectionIds)
        ? rawSelectionIds.map((value) => String(value ?? "").trim()).filter(Boolean)
        : [];
    }

    function scheduleLiveSelectionResolve(reason = "selection-debounced", { delayMs = 0, forceResolve = false } = {}) {
      selectedRuntimeReason = reason;
      const normalizedDelayMs = Math.max(0, Number(delayMs) || 0);
      if (normalizedDelayMs > 0) {
        clearTransientEmptySelectionTimer();
        transientEmptySelectionTimer = setTimeout(() => {
          transientEmptySelectionTimer = null;
          void resolveLiveSelection(reason, { forceResolve: forceResolve === true }).catch(() => {});
        }, normalizedDelayMs);
        return;
      }
      clearTransientEmptySelectionTimer();
      void resolveLiveSelection(reason, { forceResolve: forceResolve === true }).catch(() => {});
    }

    function buildSelectionTransientState(status, selectionIds, message = null, code = null) {
      const normalizedSelectionIds = normalizeSelectionIds(selectionIds);
      const single = normalizedSelectionIds.length === 1 ? normalizedSelectionIds[0] : null;
      return {
        status,
        selectedItemId: single,
        characterId: null,
        viewer,
        access: { canView: false, reason: null },
        runtimeBundle: null,
        view: null,
        error: {
          code: code ?? null,
          message: message ?? null,
        },
      };
    }

    function publishSelectionTransientState(status, selectionIds, reason = "selection-loading", { message = null, code = null } = {}) {
      const state = buildSelectionTransientState(status, selectionIds, message, code);
      lastState = state;
      return publishState(state, reason);
    }

    function scheduleResolveObservedSelection(selectionIds, reason = "selection-changed") {
      const normalizedSelectionIds = normalizeSelectionIds(selectionIds);
      clearTransientEmptySelectionTimer();
      selectionRefreshScheduler.schedule(normalizedSelectionIds, reason);
    }

    function handleObservedEmptySelection(reason = "selection-changed") {
      if (currentSelectionIds.length > 0 || pendingSelectionIds.length > 0) {
        clearTransientEmptySelectionTimer();
        transientEmptySelectionTimer = setTimeout(async () => {
          transientEmptySelectionTimer = null;
          const liveSelectionIds = await readLiveSelectionIds(currentSelectionIds);
          if (liveSelectionIds.length === 0 && pendingSelectionIds.length === 0) {
            if (currentSelectionIds.length > 0 && lastPayload?.status === "ready") {
              logDebugEvent("selection", "empty-selection-ignored", {
                reason: "sticky-last-selection",
                triggerReason: reason,
                liveSelectionIds,
                currentSelectionIds,
                pendingSelectionIds,
                stickyCharacterId: lastPayload?.characterId ?? null,
                stickyTokenId: lastPayload?.selectedItemId ?? null,
              });
              if (lastState) publishState(lastState, `${reason}:sticky-last-selection`);
              return;
            }
            await startSelectionResolve([], `${reason}:empty-confirmed`);
          } else if (pendingSelectionIds.length > 0) {
            logDebugEvent("selection", "empty-selection-ignored", {
              reason: "pending-non-empty-selection",
              triggerReason: reason,
              liveSelectionIds,
              currentSelectionIds,
              pendingSelectionIds,
            });
            if (liveSelectionIds.length > 0) {
              void startSelectionResolve(liveSelectionIds, "selection-empty-recovered-live").catch(() => {});
            }
          } else {
            logDebugEvent("selection", "empty-selection-ignored", {
              reason,
              liveSelectionIds,
              currentSelectionIds,
              pendingSelectionIds,
            });
            if (liveSelectionIds.length > 0) {
              void startSelectionResolve(liveSelectionIds, "selection-empty-recovered-live").catch(() => {});
            }
          }
        }, TRANSIENT_EMPTY_SELECTION_GRACE_MS);

        logDebugEvent("selection", "empty-selection-deferred", {
          reason,
          currentSelectionIds,
          pendingSelectionIds,
          graceMs: TRANSIENT_EMPTY_SELECTION_GRACE_MS,
        }, true, "pending");
        return;
      }

      scheduleResolveObservedSelection([], reason);
    }

    function onObservedSelectionChanged(rawSelectionIds, reason = "selection-changed") {
      const observed = normalizeSelectionIds(rawSelectionIds);
      const observedSignature = observed.join("|");
      const currentSignature = currentSelectionIds.join("|");
      const pendingSignature = pendingSelectionIds.join("|");
      lastObservedSelectionIds = observed.slice();
      logDebugEvent("selection", "selection-change-observed", {
        tokenIds: observed,
        previousSelectionIds: currentSelectionIds,
        pendingSelectionIds,
        reason,
      });
      if (observed.length > 0) {
        if (clearTransientEmptySelectionTimer()) {
          logDebugEvent("selection", "empty-selection-cancelled", {
            reason,
            tokenIds: observed,
            currentSelectionIds,
            pendingSelectionIds,
          });
          logDebugEvent("selection", "empty-selection-ignored", {
            reason: "cancelled-by-live-selection",
            tokenIds: observed,
            currentSelectionIds,
            pendingSelectionIds,
          });
        }
        if (observedSignature !== currentSignature || observedSignature !== pendingSignature) {
          void startSelectionResolve(observed, reason).catch(() => {});
        }
        return;
      }

      handleObservedEmptySelection(reason);
    }

    async function resolveLiveSelection(reason = "selection-changed", { forceResolve = false } = {}) {
      const liveSelectionIds = await readLiveSelectionIds(lastObservedSelectionIds.length ? lastObservedSelectionIds : currentSelectionIds);
      const liveSignature = liveSelectionIds.join("|");
      const currentSignature = currentSelectionIds.join("|");
      lastObservedSelectionIds = liveSelectionIds.slice();
      logDebugEvent("selection", "selection-live-read", {
        tokenIds: liveSelectionIds,
        currentSelectionIds,
        reason,
      });
      if (!forceResolve && liveSignature === currentSignature && lastPayload && pendingSelectionIds.length === 0) {
        logDebugEvent("selection", "selection-live-unchanged", {
          tokenIds: liveSelectionIds,
          reason,
        });
        broadcast(lastPayload);
        return lastPayload;
      }
      return resolveAndPublish(liveSelectionIds, reason);
    }

    async function startSelectionResolve(selectionIds, reason = "selection-changed", options = {}) {
      const normalizedSelectionIds = normalizeSelectionIds(selectionIds);
      const generation = ++selectionResolveGeneration;
      pendingSelectionIds = normalizedSelectionIds.slice();
      selectedRuntimeReason = reason;
      logDebugEvent("selection", "selection-resolve-start", {
        tokenIds: normalizedSelectionIds,
        reason,
        generation,
      }, true, "pending");

      if (normalizedSelectionIds.length > 0) {
        publishSelectionTransientState("loading", normalizedSelectionIds, `${reason}:loading`);
      }

      let timedOut = false;
      let timeoutHandle = null;
      try {
        timeoutHandle = setTimeout(() => {
          if (selectionResolveGeneration !== generation) return;
          timedOut = true;
          selectionResolveGeneration += 1;
          pendingSelectionIds = [];
          logDebugEvent("selection", "selection-resolve-timeout", {
            tokenIds: normalizedSelectionIds,
            reason,
            generation,
            timeoutMs: SELECTION_RESOLVE_TIMEOUT_MS,
          }, false);
          publishSelectionTransientState("error", normalizedSelectionIds, `${reason}:timeout`, {
            code: "SELECTION_RESOLVE_TIMEOUT",
            message: "Unable to resolve selected token. Try selecting it again.",
          });
        }, SELECTION_RESOLVE_TIMEOUT_MS);

        const payload = await resolveAndPublish(normalizedSelectionIds, reason, {
          ...options,
          generation,
        });
        logDebugEvent("selection", "selection-resolve-result", {
          tokenIds: normalizedSelectionIds,
          reason,
          generation,
          status: payload?.status ?? null,
          selectedItemId: payload?.selectedItemId ?? normalizedSelectionIds[0] ?? null,
          characterId: payload?.characterId ?? null,
        }, payload?.status === "ready");
      } finally {
        if (timeoutHandle) clearTimeout(timeoutHandle);
        logDebugEvent("selection", "selection-resolve-finished", {
          tokenIds: normalizedSelectionIds,
          reason,
          generation,
          timedOut,
          pendingSelectionIds,
        }, !timedOut);
        if (!timedOut && selectionResolveGeneration === generation && pendingSelectionIds.join("|") === normalizedSelectionIds.join("|")) {
          pendingSelectionIds = [];
        }
      }
    }

    const adapter = createSceneSelectionAdapter({
      backendConfigured: configured,
      getViewer: () => viewer,
      fetchSceneTokenLink: (tokenId) => getSceneTokenLinks(
        { room_id: context.roomId, scene_id: context.sceneId, campaign_id: context.campaignId, token_id: tokenId },
        settings,
      ),
      fetchCharacterBundle: async (characterId) => {
        const bundle = await fetchLightRuntimeBundle(characterId, selectedRuntimeReason);
        if (!bundle || typeof bundle !== "object") return bundle;

        const merged = { ...bundle, __hudDebug: { requestedSections: HUD_LIGHT_RUNTIME_SECTIONS } };
        const cacheEntry = getHeavyRuntimeCache(characterId);
        const armoryForDebug = cacheEntry?.canonicalArmory ?? cacheEntry?.armory ?? merged.armory ?? merged.sections?.armory ?? null;
        if (armoryForDebug?.combat_context && characterId) {
          logDebugEvent("weapon", "armory-combat-context", {
            characterId,
            mode: armoryForDebug.combat_context?.mode ?? null,
            encounterId: armoryForDebug.combat_context?.encounter_id ?? null,
            moveCurrent: armoryForDebug.combat_context?.move_current ?? null,
            moveMax: armoryForDebug.combat_context?.move_max ?? null,
            activeEncounterCount: armoryForDebug.combat_context?.active_encounter_count ?? null,
          });
          if (armoryForDebug.combat_context?.mode === "ambiguous") {
            logDebugEvent("weapon", "armory-combat-context-ambiguous", {
              characterId,
              activeEncounterCount: armoryForDebug.combat_context?.active_encounter_count ?? null,
              warning: armoryForDebug.combat_context?.warning ?? null,
            }, false);
          }
        }
        return merged;
      },
    });

    /** @returns {boolean} true when the character actually changed (and the reset ran) */
    function resetEphemeralForCharacter(characterId) {
      if (ephemeral.characterId === characterId) return false;
      ephemeral.characterId = characterId ?? null;
      // selectedWeaponId is NOT force-reset to null here — restoreSelectedWeapon()
      // (called right after this, once the fresh armory is known) sets it from
      // selectedWeaponMemory for the NEW character, or null if none/invalid.
      ephemeral.selectedWeaponId = null;
      ephemeral.selectedReloadMagazineId = null;
      ephemeral.weaponSelectorOpen = false;
      ephemeral.preparedAction = null;
      ephemeral.targeting = { mode: "none", selectedTargetIds: [], selectedBodyPartId: "torso" };
      ephemeral.commandStatus = null;
      ephemeral.reloadRpcResult = null;
      ephemeral.fireModeSelectorOpen = false;
      ephemeral.fireModeRpcResult = null;
      // NOTE: basicAttackInFlight is intentionally NOT force-cleared here — an
      // in-flight request's own staleness check (comparing a source/weapon/
      // target signature captured at request time) is what actually protects
      // against a stale result applying to a new character; see "execute".
      ephemeral.basicAttackResult = null;
      // Phase 4.0b: load the new character's quickbar runtime. Cleared first so
      // the Skills block doesn't briefly show the previous character's quickbar.
      abilitiesRuntime = null;
      if (quickbarController) quickbarController.onSelectionChanged(characterId ?? null);
      return true;
    }

    /** Restore this character's own remembered weapon (Token A → B → A), or
     *  fall back safely (and forget the stale entry) if it's no longer a
     *  valid weapon on their CURRENT armory. Never touches server state. */
    function restoreSelectedWeapon(characterId, bundle) {
      if (!characterId) return;
      const armory = bundle?.armory ?? bundle?.sections?.armory ?? null;
      const stored = selectedWeaponMemory.get(characterId);
      const valid = resolveStoredWeaponId(stored, armory?.weapons);
      if (valid) {
        ephemeral.selectedWeaponId = valid;
      } else if (stored) {
        selectedWeaponMemory.forget(characterId); // removed/unavailable — safe fallback below
      }
    }

    function buildEphemeralForPayload() {
      const prepared = ephemeral.preparedAction;
      const activeIntent = (prepared?.kind === "skill" && prepared.id)
        ? { kind: "skill", id: prepared.id }
        : { kind: "weapon-attack", weaponId: ephemeral.selectedWeaponId };
      return {
        selectedWeaponId: ephemeral.selectedWeaponId,
        selectedReloadMagazineId: ephemeral.selectedReloadMagazineId,
        weaponSelectorOpen: ephemeral.weaponSelectorOpen,
        preparedAction: ephemeral.preparedAction,
        targeting: ephemeral.targeting,
        commandStatus: ephemeral.commandStatus,
        activeIntent,
        debugEnabled,
        reloadRpcResult: ephemeral.reloadRpcResult,
        fireModeSelectorOpen: ephemeral.fireModeSelectorOpen,
        fireModeRpcResult: ephemeral.fireModeRpcResult,
        basicAttackInFlight: ephemeral.basicAttackInFlight,
        basicAttackResult: ephemeral.basicAttackResult,
        pendingDirectAbilityActionId: ephemeral.pendingDirectAbilityActionId,
        directAbilityAttackResult: ephemeral.directAbilityAttackResult,
        pendingInstantAbilityActionId: ephemeral.pendingInstantAbilityActionId,
        instantAbilityExecutionResult: ephemeral.instantAbilityExecutionResult,
        pendingDirectedAbilityActionId: ephemeral.pendingDirectedAbilityActionId,
        directedAbilityExecutionResult: ephemeral.directedAbilityExecutionResult,
        combatLog,
        sessionRuntime,
        abilitiesRuntime,
        armedActionId: armedTechniqueMemory.get(ephemeral.characterId),
        combatRuntimePending,
      };
    }

    function publishState(state, reason = "state-update") {
      lastPayload = buildBroadcastPayload(state, buildEphemeralForPayload());
      if (lastPayload?.status === "ready") {
        lastResolvedCharacterId = lastPayload.characterId ?? lastResolvedCharacterId;
        lastResolvedTokenId = lastPayload.selectedItemId ?? lastResolvedTokenId;
      }
      broadcast(lastPayload);
      logDebugEvent("selection", "selection-payload-broadcast", {
        status: lastPayload.status ?? null,
        selectedItemId: lastPayload.selectedItemId ?? null,
        characterId: lastPayload.characterId ?? null,
        reason,
      });
      return lastPayload;
    }

    function replayLastVisibleState(reason = "state-update") {
      if (lastState) {
        return publishState(lastState, reason);
      }
      if (lastPayload) {
        broadcast(lastPayload);
        return lastPayload;
      }
      return null;
    }

    async function refetchCurrent(reason = "generic") {
      if (refetchCurrentPromise) {
        refetchCurrentQueued = true;
        return refetchCurrentPromise;
      }

      refetchCurrentPromise = (async () => {
        const now = Date.now();
        const waitMs = Math.max(0, 350 - (now - lastRefetchAt));
        if (waitMs > 0) {
          await new Promise((resolve) => setTimeout(resolve, waitMs));
        }

        await waitForCombatActionIdle(ephemeral.characterId);

        if (currentSelectionIds.length === 1) {
          await resolveLiveSelection(reason, { forceResolve: true });
        } else if (lastState) {
          publishState(lastState);
        }

        lastRefetchAt = Date.now();
      })();

      try {
        await refetchCurrentPromise;
      } finally {
        refetchCurrentPromise = null;
        if (refetchCurrentQueued) {
          refetchCurrentQueued = false;
          void refetchCurrent(`${reason}:queued`);
        }
      }
    }

    async function refreshSelectedCharacterRuntime(
      reason = "generic",
      { refreshQuickbar = false, insideCharacterQueue = false } = {},
    ) {
      const characterId = String(ephemeral.characterId ?? "").trim() || null;
      const encounterId = currentMappedSession()?.id ?? null;
      const queueKey = buildCharacterQueueKey(characterId, `refresh:${reason}`, encounterId);
      const performRefresh = async () => {
        logDebugEvent(
          "selection",
          "runtime-refresh-start",
          {
            characterId,
            reason,
            mode: "light",
            refreshQuickbar,
            queueKey,
            sections: HUD_LIGHT_RUNTIME_SECTIONS,
          },
          true,
        );
        await waitForCombatActionIdle(characterId);
        const tasks = [refetchCurrent(reason)];
        if (refreshQuickbar && quickbarController && characterId) {
          tasks.push(quickbarController.refresh());
        }
        setCombatRuntimePending(true, reason);
        try {
          await Promise.allSettled(tasks);
        } finally {
          setCombatRuntimePending(false, reason);
        }
      };

      if (insideCharacterQueue || !characterId) {
        await performRefresh();
        return;
      }
      await runCharacterActionQueue(characterId, performRefresh, { queueKey });
    }

    function applyTargetingPayload(payload) {
      const target = payload?.target && typeof payload.target === "object" ? payload.target : null;
      ephemeral.targeting = {
        mode: payload?.mode === "picking" ? "picking" : "none",
        selectedTargetIds: target?.tokenId ? [String(target.tokenId)] : [],
        selectedTargetName: target?.displayName ?? null,
        // NOTE: selectedBodyPartId here is the WIRE ZONE CODE (e.g. "TORSO"),
        // an existing, unchanged field used for display/highlight. The REAL
        // per-character body-part uuid perform_attack needs is the separate
        // resolvedBodyPartId field below — never conflate the two.
        selectedBodyPartId: target?.selectedZoneId ?? "torso",
        selectedTargetCharacterId: target?.characterId ?? null,
        resolvedBodyPartId: target?.resolvedBodyPartId ?? null,
        // COLOR-ONLY body-zone condition map (svgPartId -> ZONE_STATES value)
        // for the Target Block silhouette — see targetBodyZones.buildTargetZonesMap.
        zonesMap: target?.zonesMap && typeof target.zonesMap === "object" ? target.zonesMap : {},
        distance: Number.isFinite(Number(target?.distance?.value)) ? Number(target.distance.value) : null,
        error: payload?.error ?? null,
      };
      if (lastState) publishState(lastState);
    }

    function isCombatSyncBlockedCommand(command) {
      if (!combatRuntimePending || !command || typeof command !== "object") return false;
      const feature = String(command.feature ?? "").trim();
      const type = String(command.type ?? "").trim();
      if (feature === "basic-attack" && type === "execute") return true;
      if (feature === "quickbar" && (type === "execute-direct-ability" || type === "execute-instant-ability" || type === "execute-directed-ability" || type === "toggle-armed")) {
        return true;
      }
      if (feature === "fire-mode" && type === "select") return true;
      return type === "reload";
    }

    async function handleCommand(command) {
      if (!command || typeof command !== "object") return;
      if (!lastPayload || lastPayload.status !== "ready") return;
      if (isCombatSyncBlockedCommand(command)) {
        ephemeral.commandStatus = { type: "error", message: "Synchronizing combat..." };
        if (lastState) publishState(lastState);
        return;
      }

      if (command?.scope === "combat-hud" && command?.feature === "gm-skill-admin") {
        const viewerIsGm = String(viewer?.role ?? "").toUpperCase() === "GM";
        const deleteType = String(command.type ?? "");
        const characterSkillId = String(command.characterSkillId ?? command.skillId ?? "").trim() || null;
        const characterActionId = String(command.characterActionId ?? "").trim() || null;
        const deleteKey = deleteType === "delete-skill"
          ? `skill:${characterSkillId ?? ""}`
          : `ability:${characterActionId ?? ""}`;

        logDebugEvent("skills", "gm-delete-click", {
          type: deleteType,
          characterSkillId,
          characterActionId,
        });

        if (!viewerIsGm) {
          ephemeral.commandStatus = {
            type: "error",
            message: "GM delete is available only for the GM.",
            source: "gm-skill-admin",
            deleteKey,
          };
          if (lastState) publishState(lastState);
          return;
        }

        if (skillAdminDeleteInFlight) return;

        if (deleteType !== "delete-skill" && deleteType !== "delete-ability") return;
        if (deleteType === "delete-skill" && !characterSkillId) {
          ephemeral.commandStatus = {
            type: "error",
            message: "Missing character skill id.",
            source: "gm-skill-admin",
            deleteKey,
          };
          if (lastState) publishState(lastState);
          return;
        }
        if (deleteType === "delete-ability" && !characterActionId) {
          ephemeral.commandStatus = {
            type: "error",
            message: "Missing character ability id.",
            source: "gm-skill-admin",
            deleteKey,
          };
          if (lastState) publishState(lastState);
          return;
        }

        skillAdminDeleteInFlight = deleteKey;
        try {
          if (deleteType === "delete-skill") {
            await mutateSupabaseRows(
              `odyssey_character_skills?id=eq.${encodeURIComponent(characterSkillId)}&character_id=eq.${encodeURIComponent(ephemeral.characterId)}`,
              null,
              settings,
              { method: "DELETE", prefer: "return=minimal", fallbackMessage: "Unable to delete character skill." },
            );
          } else {
            await mutateSupabaseRows(
              `odyssey_character_abilities?id=eq.${encodeURIComponent(characterActionId)}&character_id=eq.${encodeURIComponent(ephemeral.characterId)}`,
              null,
              settings,
              { method: "DELETE", prefer: "return=minimal", fallbackMessage: "Unable to delete character ability." },
            );
            if (armedTechniqueMemory.get(ephemeral.characterId) === characterActionId) {
              armedTechniqueMemory.forget(ephemeral.characterId);
            }
          }

          ephemeral.commandStatus = {
            type: "ok",
            message: deleteType === "delete-skill" ? "Skill deleted." : "Ability deleted.",
            source: "gm-skill-admin",
            deleteKey,
          };
          logDebugEvent("skills", "gm-delete-result", { ok: true, type: deleteType, deleteKey }, true);

          await Promise.allSettled([
            quickbarController?.refresh?.(),
            refetchCurrent(),
          ]);
        } catch (error) {
          const message = String(error?.message ?? error ?? "Delete failed.");
          ephemeral.commandStatus = {
            type: "error",
            message,
            source: "gm-skill-admin",
            deleteKey,
          };
          logDebugEvent("skills", "gm-delete-result", { ok: false, type: deleteType, deleteKey, error: message }, false);
          if (lastState) publishState(lastState);
        } finally {
          skillAdminDeleteInFlight = null;
        }
        return;
      }

      // Fire Mode v1: namespaced commands ({scope:"combat-hud", feature:"fire-mode"})
      // are routed BEFORE the flat-`type` switch below, on scope+feature (not just
      // `type`), so they can never collide with weapon/magazine/reload/target/
      // skill commands regardless of what `type` string they happen to reuse.
      if (command?.scope === "combat-hud" && command?.feature === "fire-mode") {
        const fmType = String(command.type ?? "");
        if (fmType === "toggle-selector") {
          ephemeral.fireModeSelectorOpen = !ephemeral.fireModeSelectorOpen;
          logDebugEvent("fire-mode", "selector-toggled", { open: ephemeral.fireModeSelectorOpen });
          if (lastState) publishState(lastState);
          return;
        }
        if (fmType === "close-selector") {
          ephemeral.fireModeSelectorOpen = false;
          logDebugEvent("fire-mode", "selector-closed", {});
          if (lastState) publishState(lastState);
          return;
        }
        if (fmType === "select") {
          const weapon = lastPayload.hudSnapshot?.weapon?.primary ?? null;
          const weaponId = weapon?.id ?? null;
          const profileId = weapon?.activeProfileId ?? null;
          const fireModeId = String(command.fireModeId ?? "").trim() || null;
          ephemeral.fireModeSelectorOpen = false;
          ephemeral.commandStatus = null;
          logDebugEvent("fire-mode", "selected", { weaponId, fireModeId });
          if (!weaponId || !profileId || !fireModeId) {
            ephemeral.commandStatus = { type: "error", message: "Fire mode switch unavailable: missing weapon, profile, or mode." };
            ephemeral.fireModeRpcResult = { ok: false, error: "MISSING_FIELDS", message: "weaponId/profileId/fireModeId missing before RPC call." };
            logDebugEvent("fire-mode", "result", { error: "MISSING_FIELDS" }, false);
            if (lastState) publishState(lastState);
            return;
          }
          try {
            await switchWeaponFireMode(ephemeral.characterId, weaponId, fireModeId, settings);
            // Success: switch_weapon_fire_mode persists selected_fire_mode_id
            // server-side (keyed by weapon+profile) and returns the fresh
            // armory — an authoritative refresh (not a local override) is the
            // only way the Gun HUD's new mode can be trusted. No local
            // "selectedFireModeId" ephemeral is kept: the mode always comes
            // straight from armory for whichever weapon is active.
            ephemeral.fireModeRpcResult = normalizeFireModeRpcResult(null);
            ephemeral.commandStatus = { type: "ok", message: "Fire mode changed." };
            pushLog(buildFireModeLogEntry({ sourceCharacterId: ephemeral.characterId, ok: true, message: "Fire mode changed." }));
            logDebugEvent("fire-mode", "result", { weaponId, fireModeId }, true);
            const heavyEncounterId = currentMappedSession()?.id ?? null;
            await refreshHeavyCharacterData(ephemeral.characterId, {
              reason: "fire-mode-changed",
              encounterId: heavyEncounterId,
              armory: true,
              inventory: true,
            });
            await refreshSelectedCharacterRuntime("fire-mode-changed", { refreshQuickbar: true });
          } catch (error) {
            // switch_weapon_fire_mode RAISEs an exception (not {ok:false}) on
            // an invalid weapon or a mode not allowed for the active profile —
            // the real server message must reach the player, never a silent
            // local "success".
            const normalized = normalizeFireModeRpcResult(error);
            ephemeral.fireModeRpcResult = normalized;
            ephemeral.commandStatus = { type: "error", message: normalized.message || "Fire mode switch failed." };
            pushLog(buildFireModeLogEntry({ sourceCharacterId: ephemeral.characterId, ok: false, message: normalized.message }));
            logDebugEvent("fire-mode", "result", { weaponId, fireModeId, error: normalized.error, message: normalized.message }, false);
            if (lastState) publishState(lastState);
          }
          return;
        }
        return; // unknown fire-mode command → ignore, never falls through below
      }

      // Phase 4.1A: arm/disarm an attack technique from the Skills Block
      // (occupied attack_technique slot) or Combat Control's ARMED × button —
      // both funnel into the SAME toggle so max-1-armed and replace-on-arm
      // are enforced in exactly one place (armedTechniqueMemory.js). Pure
      // local ephemeral UI state — no server round-trip, no cost spent here;
      // the server re-validates everything at Attack time.
      if (command?.scope === "combat-hud" && command?.feature === "quickbar" && command?.type === "toggle-armed") {
        const actionId = String(command.characterActionId ?? "").trim() || null;
        if (actionId && ephemeral.characterId) {
          const { armedId, previousId } = armedTechniqueMemory.toggle(ephemeral.characterId, actionId);
          const eventType = armedId == null
            ? "attack-technique-disarmed"
            : (previousId ? "attack-technique-replaced" : "attack-technique-armed");
          logDebugEvent("abilities", eventType, {
            characterActionId: actionId,
            previousCharacterActionId: previousId ?? null,
          });
          if (lastState) publishState(lastState);
        }
        return;
      }

      // Phase 4.1B.0: Direct Ability Attack. A SEPARATE command from both
      // toggle-armed (above) and basic-attack (below) — clicking a direct-
      // attack-eligible technique executes it immediately server-side; it
      // never becomes ARMED and never touches armedTechniqueMemory. Uses the
      // SAME resolveAttack()/performAttack() weapon attacks use (mode:
      // "skill" instead of "weapon" — see buildDirectAbilityAttackCtx), so
      // server result handling (ok:false vs exception vs success) behaves
      // identically. No weapon/ammo/magazine/fire-mode field is ever built
      // into this payload — buildDirectAbilityAttackCtx structurally has none.
      if (command?.scope === "combat-hud" && command?.feature === "quickbar" && command?.type === "execute-direct-ability") {
        const actionId = String(command.characterActionId ?? "").trim() || null;
        logDebugEvent("abilities", "direct-attack-requested", { characterActionId: actionId });

        // Double-submit guard: per-ability (not a whole-quickbar lock), so a
        // second execute on the SAME ability while it's in flight is a
        // no-op, but every other slot/weapon-attack stays fully interactive.
        const directAbilityActionKey = buildCombatActionKey(ephemeral.characterId, actionId, "direct-ability");
        if (isCombatActionBusy(ephemeral.characterId, actionId, "direct-ability")) {
          logDebugEvent("abilities", "direct-attack-ignored", {
            characterId: ephemeral.characterId,
            characterActionId: actionId,
            reason: "ACTION_ALREADY_PENDING",
          }, false);
          return;
        }

        const action = findQuickActionByCharacterActionId(actionId);
        if (!actionId || !action || !isDirectAttackAbility(action)) {
          // Defensive only — QuickbarView.js never dispatches this command
          // for anything else; a malformed/stale command is ignored rather
          // than guessed at. Diagnostics are deliberately structured so a
          // real failure (runtime not loaded yet, action genuinely absent,
          // action present but not direct-attack-compatible) can be told
          // apart from each other in the Debug Console — never a full
          // private runtime bundle, never credentials/auth/GM-only data.
          logDebugEvent("abilities", "direct-attack-blocked", {
            characterActionId: actionId,
            reason: "INVALID_ABILITY",
            hasAbilitiesRuntime: Boolean(abilitiesRuntime),
            quickActionCount: abilitiesRuntime?.quickActions?.length ?? 0,
            matchingActionFound: Boolean(action),
            matchingActionType: action?.type ?? null,
            matchingExecutionReason: action?.state?.executionReason ?? null,
            matchingExecutionAvailable: action?.state?.executionAvailable ?? null,
          }, false);
          if (!abilitiesRuntime) {
            ephemeral.commandStatus = { type: "error", message: "Ability runtime is not loaded yet." };
            if (lastState) publishState(lastState);
            // Best-effort: ask the existing quickbar controller to (re)load
            // its runtime — never a fake success, never a perform_attack
            // call without a real, found, direct-attack-eligible action.
            void quickbarController?.refresh();
          }
          return;
        }

        const targeting = ephemeral.targeting ?? {};
        const evalCtx = {
          sourceCharacterId: ephemeral.characterId,
          abilityId: actionId,
          targetTokenId: targeting.selectedTargetIds?.[0] ?? null,
          targetCharacterId: targeting.selectedTargetCharacterId ?? null,
          bodyZoneId: targeting.selectedBodyPartId ?? null,
          resolvedBodyPartId: targeting.resolvedBodyPartId ?? null,
          inFlight: false,
        };
        const evalResult = evaluateDirectAbilityAttack(evalCtx);
        ephemeral.commandStatus = null;
        if (!evalResult.uiAllowed) {
          ephemeral.commandStatus = { type: "error", message: evalResult.uiBlockReason };
          ephemeral.directAbilityAttackResult = { ok: false, error: "PRECONDITION_FAILED", message: evalResult.uiBlockReason };
          logDebugEvent("abilities", "direct-attack-blocked", { characterActionId: actionId, reason: evalResult.uiBlockReason }, false);
          if (lastState) publishState(lastState);
          return;
        }

        // Phase 3E.0: client-side session pre-gate (UX mirror only — the
        // server re-checks turn/MAIN inside perform_attack regardless, now
        // for ability attacks too — see migration 102).
        const sessionAtRequest = currentMappedSession();
        const sessionGate = sessionAttackGate(sessionAtRequest);
        if (sessionGate.blocked) {
          ephemeral.commandStatus = { type: "error", message: sessionGate.reason };
          ephemeral.directAbilityAttackResult = { ok: false, error: "SESSION_GATE", message: sessionGate.reason };
          logDebugEvent("abilities", "direct-attack-blocked", { characterActionId: actionId, reason: sessionGate.reason }, false);
          if (lastState) publishState(lastState);
          return;
        }

        // Snapshot the source/ability/target this request is FOR — same
        // staleness discipline as basic-attack below.
        const requestCtx = { sourceCharacterId: evalCtx.sourceCharacterId, abilityId: actionId, targetCharacterId: evalCtx.targetCharacterId };
        const bodyZoneLabel = getZoneLabel(DEFAULT_PROFILE_ID, evalCtx.bodyZoneId) || evalCtx.bodyZoneId;
        const ctx = buildDirectAbilityAttackCtx({
          sourceCharacterId: evalCtx.sourceCharacterId,
          abilityId: actionId,
          targetCharacterId: evalCtx.targetCharacterId,
          bodyPartId: evalCtx.resolvedBodyPartId,
          distance: targeting.distance ?? 0,
          roomContext: sessionAtRequest.exists
            ? { encounterId: sessionAtRequest.id ?? undefined }
            : {},
          expectedEncounterVersion: expectedVersionOf(sessionAtRequest),
          includeRuntimeRefresh: false,
          resultMode: "compact",
        });

        const inFlightDirectAbilityActionKey = markCombatActionStarted(ephemeral.characterId, actionId, "direct-ability") ?? directAbilityActionKey;
        ephemeral.pendingDirectAbilityActionId = actionId;
        logDebugEvent("abilities", "direct-attack-payload-prepared", { characterActionId: actionId, targetCharacterId: ctx.targetCharacterId, bodyZone: evalCtx.bodyZoneId });
        logDebugEvent("attack", "perform_attack-request", {
          encounterId: sessionAtRequest.id ?? null,
          attackerCharacterId: ctx.attackerCharacterId,
          targetCharacterId: ctx.targetCharacterId,
          compact: true,
          source: "direct-ability",
        }, true, "pending");
        if (lastState) publishState(lastState); // slot shows pending immediately

        let outcome;
        try {
          outcome = await resolveAttack(ctx, { performAttack: (payload) => performAttack(payload, settings) });
        } catch (error) {
          // resolveAttack() already catches RPC/network errors internally —
          // this catch only guards a thrown ValidationError (a locally-
          // missing required field).
          outcome = { ok: false, payload: null, raw: null, normalized: null, code: null, error: String(error?.message ?? error ?? "Ability attack failed.") };
        }

        ephemeral.pendingDirectAbilityActionId = null;
        markCombatActionFinished(requestCtx.sourceCharacterId, inFlightDirectAbilityActionKey);
        const currentCtx = {
          sourceCharacterId: ephemeral.characterId,
          abilityId: actionId,
          targetCharacterId: ephemeral.targeting?.selectedTargetCharacterId ?? null,
        };
        const stale = isDirectAbilityAttackResultStale(requestCtx, currentCtx);

        ephemeral.directAbilityAttackResult = { ok: outcome.ok, error: outcome.code ?? null, message: outcome.error ?? null };
        // Logged regardless of staleness — a stale result is still a REAL
        // thing that happened, attributed to the request it actually belongs
        // to. Reuses buildAttackLogEntry verbatim (Combat Log doesn't care
        // whether the outcome came from a weapon or an ability attack).
        pushLog(buildAttackLogEntry({
          sourceCharacterId: requestCtx.sourceCharacterId,
          targetCharacterId: requestCtx.targetCharacterId,
          bodyZoneLabel,
          outcome,
        }));
        logDebugEvent("abilities", "direct-attack-result", { characterActionId: actionId, ok: outcome.ok, error: outcome.code ?? null, stale }, outcome.ok);
        // Full authoritative roll trace — ONLY for a genuinely resolved
        // attack, same rule as basic-attack's own roll-resolution event.
        if (outcome.ok) {
          logDebugEvent(
            "abilities",
            "direct-attack-roll-resolution",
            buildRollResolutionDetails(buildAttackResolutionTrace(outcome)),
            true,
          );
        }
        // Phase 3E.0 + migration 102: server-confirmed session cost (MAIN
        // spent on hit AND miss identically) — now present for a resolved
        // ability attack too, logged from the server's own summary, then the
        // authoritative session state is re-read (never mutated locally).
        const sessionCost = outcome.raw?.combat_session ?? null;
        if (sessionCost && typeof sessionCost === "object") {
          logDebugEvent("abilities", "direct-attack-action-cost-consumed", {
            sessionId: sessionCost.encounter_id ?? null,
            round: sessionCost.round ?? null,
            participant: sessionCost.participant_entry_id ?? null,
            versionBefore: sessionCost.state_version_before ?? null,
            versionAfter: sessionCost.state_version_after ?? null,
            mainAfter: sessionCost.main_available_after ?? null,
            moveAfter: sessionCost.move_available_after ?? null,
            usedReaction: sessionCost.used_reaction ?? null,
          });
        }
        if (outcome.code === "STATE_VERSION_CONFLICT") {
          logDebugEvent("session", "stale-version", { command: "direct-ability-attack" }, true);
        }
        if ((sessionCost || outcome.code === "STATE_VERSION_CONFLICT") && sessionController) {
          await refreshCombatSessionSafe(sessionController, "direct-ability-attack");
        }

        if (stale) {
          // Source/ability/target changed mid-flight: never apply this
          // result to the new HUD state.
          if (lastState) publishState(lastState);
          return;
        }

        if (outcome.ok) {
          ephemeral.commandStatus = { type: "ok", message: "Ability attack resolved." };
          // Same rule as a weapon attack: target/zone are NEVER reset after a
          // successful ability attack — only a best-effort, non-clearing
          // refresh of the target's own body-zone condition is requested.
          try { OBR.broadcast.sendMessage(BC_HUD_TARGETING_COMMAND, { type: "refreshBodyZones" }, { destination: "LOCAL" }); } catch (_e) { /* best-effort */ }
          await refreshCombatSessionSafe(sessionController, "direct-ability-attack-success");
          await refreshSelectedCharacterRuntime("direct-ability-attack-success", { refreshQuickbar: true });
          logDebugEvent("refresh", "source-refresh-result", { reason: "direct-ability-attack-success" }, true);
        } else {
          ephemeral.commandStatus = { type: "error", message: outcome.error || "Ability attack failed." };
          await refreshCombatSessionSafe(sessionController, "direct-ability-attack-failure");
          await refreshSelectedCharacterRuntime("direct-ability-attack-failure", { refreshQuickbar: true });
          logDebugEvent("refresh", "source-refresh-result", { reason: "direct-ability-attack-failure" }, true);
        }
        return;
      }

      // Phase 4.1B.1: Instant / Self Ability Execution. A SEPARATE command
      // from execute-direct-ability (above) and basic-attack (below) —
      // clicking an instant/self-eligible ability executes it immediately
      // server-side with NO target/body-zone concept at all. Uses
      // combat_execute_action(kind:"ability") — a DIFFERENT RPC than
      // perform_attack, since use_ability's own server body explicitly
      // rejects attack-kind abilities and vice versa (see
      // docs/PHASE_4_1B_1_INSTANT_SELF_ABILITIES_AUDIT.md §7). No
      // weapon/ammo/magazine/fire-mode/target/body-part field is ever built
      // into this payload — buildInstantAbilityExecutionPayload structurally
      // has none.
      if (command?.scope === "combat-hud" && command?.feature === "quickbar" && command?.type === "execute-instant-ability") {
        const actionId = String(command.characterActionId ?? "").trim() || null;
        logDebugEvent("abilities", "ability-execute-requested", { characterActionId: actionId });

        // Double-submit guard: per-ability, not a whole-quickbar lock.
        if (isCombatActionBusy(ephemeral.characterId, actionId, "instant-ability")) {
          logDebugEvent("abilities", "ability-execute-ignored", {
            characterId: ephemeral.characterId,
            characterActionId: actionId,
            reason: "ACTION_ALREADY_PENDING",
          }, false);
          return;
        }

        const action = findQuickActionByCharacterActionId(actionId);
        if (!actionId || !action || !isInstantSelfAbility(action)) {
          // Defensive only — QuickbarView.js never dispatches this command
          // for anything else. Same rich, safe diagnostic shape the
          // execute-direct-ability hotfix introduced — never the raw
          // runtime bundle, never credentials/auth/GM-only data.
          logDebugEvent("abilities", "ability-execute-blocked", {
            characterActionId: actionId,
            reason: "INVALID_ABILITY",
            hasAbilitiesRuntime: Boolean(abilitiesRuntime),
            quickActionCount: abilitiesRuntime?.quickActions?.length ?? 0,
            matchingActionFound: Boolean(action),
            matchingActionType: action?.type ?? null,
            matchingExecutionReason: action?.state?.executionReason ?? null,
            matchingExecutionAvailable: action?.state?.executionAvailable ?? null,
          }, false);
          if (!abilitiesRuntime) {
            ephemeral.commandStatus = { type: "error", message: "Ability runtime is not loaded yet." };
            if (lastState) publishState(lastState);
            void quickbarController?.refresh();
          }
          return;
        }

        const sessionAtRequest = currentMappedSession();
        const evalCtx = {
          sourceCharacterId: ephemeral.characterId,
          abilityId: actionId,
          inFlight: false,
          sessionExists: sessionAtRequest.exists === true,
        };
        const evalResult = evaluateInstantAbilityExecution(evalCtx);
        ephemeral.commandStatus = null;
        if (!evalResult.uiAllowed) {
          ephemeral.commandStatus = { type: "error", message: evalResult.uiBlockReason };
          ephemeral.instantAbilityExecutionResult = { ok: false, error: "PRECONDITION_FAILED", message: evalResult.uiBlockReason };
          logDebugEvent("abilities", "ability-execute-blocked", { characterActionId: actionId, reason: evalResult.uiBlockReason }, false);
          if (lastState) publishState(lastState);
          return;
        }

        // Client-side session pre-gate (UX mirror only — the server
        // re-checks turn/MAIN inside combat_execute_action regardless).
        // sessionAttackGate is generic (turn + MAIN availability only, no
        // attack-specific field) — reused as-is, no second gate function.
        const sessionGate = sessionAttackGate(sessionAtRequest);
        if (sessionGate.blocked) {
          ephemeral.commandStatus = { type: "error", message: sessionGate.reason };
          ephemeral.instantAbilityExecutionResult = { ok: false, error: "SESSION_GATE", message: sessionGate.reason };
          logDebugEvent("abilities", "ability-execute-blocked", { characterActionId: actionId, reason: sessionGate.reason }, false);
          if (lastState) publishState(lastState);
          return;
        }

        const requestCtx = { sourceCharacterId: evalCtx.sourceCharacterId, abilityId: actionId };
        const ctx = {
          sourceCharacterId: evalCtx.sourceCharacterId,
          abilityId: actionId,
          selectedWeaponId: ephemeral.selectedWeaponId ?? null,
          encounterId: sessionAtRequest.id ?? "",
          actorPlayerId: viewer?.playerId ?? null,
          actorIsGm: String(viewer?.role ?? "").toUpperCase() === "GM",
          expectedEncounterVersion: expectedVersionOf(sessionAtRequest),
        };
        const queueKey = buildCharacterQueueKey(ctx.sourceCharacterId, `instant-ability:${actionId}`, ctx.encounterId);

        const inFlightInstantAbilityActionKey = markCombatActionStarted(ephemeral.characterId, actionId, "instant-ability");
        ephemeral.pendingInstantAbilityActionId = actionId;
        logDebugEvent("abilities", "ability-execute-request", {
          encounterId: ctx.encounterId || null,
          characterId: ctx.sourceCharacterId,
          characterActionId: actionId,
          selectedCharacterWeaponId: ctx.selectedWeaponId ?? null,
          includeRuntime: false,
          expectedEncounterVersion: ctx.expectedEncounterVersion ?? null,
          expectedCharacterStateVersion: null,
          queueKey,
        }, true, "pending");
        logDebugEvent("abilities", "ability-execute-payload-prepared", {
          characterActionId: actionId,
          actionType: action.type,
          semanticKind: action.semanticKind,
          queueKey,
        });
        if (lastState) publishState(lastState); // slot shows pending immediately

        try {
          await runCharacterActionQueue(
            ctx.sourceCharacterId,
            async () => {
              markCombatActionActive(requestCtx.sourceCharacterId, inFlightInstantAbilityActionKey);
              let outcome;
              try {
                outcome = await executeCombatAbilityWithRetry(
                  () => resolveInstantAbilityExecution(ctx, { executeAction: (payload) => executeAction(payload, settings) }),
                  {
                    characterId: ctx.sourceCharacterId,
                    actionId,
                    debugAction: "ability-execute-retry",
                  },
                );
              } catch (error) {
                outcome = { ok: false, payload: null, raw: null, normalized: null, code: null, error: String(error?.message ?? error ?? "Ability execution failed.") };
              }

              ephemeral.pendingInstantAbilityActionId = null;
              markCombatActionFinished(requestCtx.sourceCharacterId, inFlightInstantAbilityActionKey);
              const currentCtx = { sourceCharacterId: ephemeral.characterId, abilityId: actionId };
              const stale = isInstantAbilityResultStale(requestCtx, currentCtx);

              const outcomeCode = normalizeOutcomeCode(outcome);
              ephemeral.instantAbilityExecutionResult = { ok: outcome.ok, error: outcomeCode, message: outcome.error ?? null };
              pushLog(buildAbilityExecutionLogEntry({
                sourceCharacterId: requestCtx.sourceCharacterId,
                abilityName: action.name,
                outcome,
              }));
              logDebugEvent("abilities", "ability-execute-result", {
                characterActionId: actionId,
                actionType: action.type,
                semanticKind: action.semanticKind,
                executionReason: action.state?.executionReason ?? null,
                available: action.state?.available ?? null,
                resourceSufficient: action.state?.resourceSufficient ?? null,
                cooldown: action.cooldown ?? null,
                ok: outcome.ok,
                code: outcomeCode,
                message: outcome.error ?? null,
                stage: outcome?.raw?.stage ?? null,
                stale,
                queueKey,
              }, outcome.ok);
              if (outcome.ok && outcome.normalized) {
                logDebugEvent("abilities", "ability-execute-cost-consumed", {
                  characterActionId: actionId,
                  actionCost: outcome.normalized.actionCost,
                  moveCost: outcome.normalized.moveCost,
                  usedReaction: outcome.normalized.usedReaction,
                  resourceSpent: outcome.normalized.resourceSpent,
                  encounterStateVersionBefore: sessionAtRequest.version ?? null,
                  encounterStateVersionAfter: outcome.normalized.encounterStateVersion,
                }, true);
              }
              if (outcomeCode === "STATE_VERSION_CONFLICT") {
                logDebugEvent("session", "stale-version", { command: "instant-ability" }, true);
              }

              if (stale) {
                if (lastState) publishState(lastState);
                return;
              }

              await refreshCombatSessionSafe(sessionController, "instant-ability");

              if (outcome.ok) {
                ephemeral.commandStatus = { type: "ok", message: "Ability used." };
                await refreshSelectedCharacterRuntime("instant-ability-success", { refreshQuickbar: true, insideCharacterQueue: true });
                logDebugEvent("refresh", "source-refresh-result", { reason: "instant-ability-success", queueKey }, true);
              } else {
                ephemeral.commandStatus = { type: "error", message: outcome.error || "Ability failed." };
                await refreshSelectedCharacterRuntime("instant-ability-failure", { refreshQuickbar: true, insideCharacterQueue: true });
                logDebugEvent("refresh", "source-refresh-result", { reason: "instant-ability-failure", queueKey }, true);
              }
            },
            { queueKey },
          );
        } finally {
          ephemeral.pendingInstantAbilityActionId = null;
          markCombatActionFinished(requestCtx.sourceCharacterId, inFlightInstantAbilityActionKey);
        }
        return;
      }

      // Phase 4.1B.2: Directed Target Ability Execution. A SEPARATE command
      // from execute-instant-ability (above) — requires a selected target
      // CHARACTER, but never a body zone/body part (isDirectedTargetAbility).
      // Uses the SAME combat_execute_action(kind:"ability") RPC as
      // instant/self abilities, just with intent.target_character_id
      // included — use_ability already supports this (see
      // docs/PHASE_4_1B_2_DIRECTED_TARGET_ABILITIES_AUDIT.md §5-7). Reads
      // the SAME ephemeral.targeting state weapon-attack/direct-ability-
      // attack already read — never a second target source, never Owlbear's
      // native selection.
      if (command?.scope === "combat-hud" && command?.feature === "quickbar" && command?.type === "execute-directed-ability") {
        const actionId = String(command.characterActionId ?? "").trim() || null;
        logDebugEvent("abilities", "directed-ability-requested", { characterActionId: actionId });

        if (isCombatActionBusy(ephemeral.characterId, actionId, "directed-ability")) {
          logDebugEvent("abilities", "directed-ability-ignored", {
            characterId: ephemeral.characterId,
            characterActionId: actionId,
            reason: "ACTION_ALREADY_PENDING",
          }, false);
          return;
        }

        const action = findQuickActionByCharacterActionId(actionId);
        if (!actionId || !action || !isDirectedTargetAbility(action)) {
          logDebugEvent("abilities", "directed-ability-blocked", {
            characterActionId: actionId,
            reason: "INVALID_ABILITY",
            hasAbilitiesRuntime: Boolean(abilitiesRuntime),
            quickActionCount: abilitiesRuntime?.quickActions?.length ?? 0,
            matchingActionFound: Boolean(action),
            matchingActionType: action?.type ?? null,
            matchingExecutionReason: action?.state?.executionReason ?? null,
            matchingExecutionAvailable: action?.state?.executionAvailable ?? null,
          }, false);
          if (!abilitiesRuntime) {
            ephemeral.commandStatus = { type: "error", message: "Ability runtime is not loaded yet." };
            if (lastState) publishState(lastState);
            void quickbarController?.refresh();
          }
          return;
        }

        const sessionAtRequest = currentMappedSession();
        const targeting = ephemeral.targeting ?? {};
        const evalCtx = {
          sourceCharacterId: ephemeral.characterId,
          abilityId: actionId,
          targetTokenId: targeting.selectedTargetIds?.[0] ?? null,
          targetCharacterId: targeting.selectedTargetCharacterId ?? null,
          inFlight: false,
          sessionExists: sessionAtRequest.exists === true,
        };
        const evalResult = evaluateDirectedAbilityExecution(evalCtx);
        ephemeral.commandStatus = null;
        if (!evalResult.uiAllowed) {
          ephemeral.commandStatus = { type: "error", message: evalResult.uiBlockReason };
          ephemeral.directedAbilityExecutionResult = { ok: false, error: "PRECONDITION_FAILED", message: evalResult.uiBlockReason };
          logDebugEvent("abilities", "directed-ability-blocked", { characterActionId: actionId, reason: evalResult.uiBlockReason }, false);
          if (lastState) publishState(lastState);
          return;
        }

        // Client-side session pre-gate (UX mirror only — the server
        // re-checks turn/MAIN inside combat_execute_action regardless).
        const sessionGate = sessionAttackGate(sessionAtRequest);
        if (sessionGate.blocked) {
          ephemeral.commandStatus = { type: "error", message: sessionGate.reason };
          ephemeral.directedAbilityExecutionResult = { ok: false, error: "SESSION_GATE", message: sessionGate.reason };
          logDebugEvent("abilities", "directed-ability-blocked", { characterActionId: actionId, reason: sessionGate.reason }, false);
          if (lastState) publishState(lastState);
          return;
        }

        const requestCtx = { sourceCharacterId: evalCtx.sourceCharacterId, abilityId: actionId, targetCharacterId: evalCtx.targetCharacterId };
        const ctx = {
          sourceCharacterId: evalCtx.sourceCharacterId,
          abilityId: actionId,
          selectedWeaponId: ephemeral.selectedWeaponId ?? null,
          targetCharacterId: evalCtx.targetCharacterId,
          encounterId: sessionAtRequest.id ?? "",
          actorPlayerId: viewer?.playerId ?? null,
          actorIsGm: String(viewer?.role ?? "").toUpperCase() === "GM",
          expectedEncounterVersion: expectedVersionOf(sessionAtRequest),
        };
        const queueKey = buildCharacterQueueKey(ctx.sourceCharacterId, `directed-ability:${actionId}`, ctx.encounterId);

        const inFlightDirectedAbilityActionKey = markCombatActionStarted(ephemeral.characterId, actionId, "directed-ability");
        ephemeral.pendingDirectedAbilityActionId = actionId;
        logDebugEvent("abilities", "directed-ability-request", {
          encounterId: ctx.encounterId || null,
          characterId: ctx.sourceCharacterId,
          characterActionId: actionId,
          selectedCharacterWeaponId: ctx.selectedWeaponId ?? null,
          includeRuntime: false,
          expectedEncounterVersion: ctx.expectedEncounterVersion ?? null,
          expectedCharacterStateVersion: null,
          targetCharacterId: ctx.targetCharacterId ?? null,
          queueKey,
        }, true, "pending");
        logDebugEvent("abilities", "directed-ability-payload-prepared", {
          characterActionId: actionId,
          actionType: action.type,
          semanticKind: action.semanticKind,
          sourceCharacterId: ctx.sourceCharacterId,
          targetCharacterId: ctx.targetCharacterId,
          targetTokenId: evalCtx.targetTokenId,
          queueKey,
        });
        if (lastState) publishState(lastState); // slot shows pending immediately

        try {
          await runCharacterActionQueue(ctx.sourceCharacterId, async () => {
            markCombatActionActive(requestCtx.sourceCharacterId, inFlightDirectedAbilityActionKey);
            let outcome;
            try {
              outcome = await executeCombatAbilityWithRetry(
                () => resolveDirectedAbilityExecution(ctx, { executeAction: (payload) => executeAction(payload, settings) }),
                {
                  characterId: ctx.sourceCharacterId,
                  actionId,
                  debugAction: "directed-ability-retry",
                },
              );
            } catch (error) {
              outcome = { ok: false, payload: null, raw: null, normalized: null, code: null, error: String(error?.message ?? error ?? "Ability execution failed.") };
            }

        ephemeral.pendingDirectedAbilityActionId = null;
        markCombatActionFinished(requestCtx.sourceCharacterId, inFlightDirectedAbilityActionKey);
        const currentCtx = {
          sourceCharacterId: ephemeral.characterId,
          abilityId: actionId,
          targetCharacterId: ephemeral.targeting?.selectedTargetCharacterId ?? null,
        };
        const stale = isDirectedAbilityResultStale(requestCtx, currentCtx);

        const outcomeCode = normalizeOutcomeCode(outcome);
        ephemeral.directedAbilityExecutionResult = { ok: outcome.ok, error: outcomeCode, message: outcome.error ?? null };
        pushLog(buildDirectedAbilityLogEntry({
          sourceCharacterId: requestCtx.sourceCharacterId,
          targetCharacterId: requestCtx.targetCharacterId,
          abilityName: action.name,
          targetName: targeting.selectedTargetName ?? null,
          outcome,
        }));
        logDebugEvent("abilities", "directed-ability-result", {
          characterActionId: actionId,
          actionType: action.type,
          semanticKind: action.semanticKind,
          executionReason: action.state?.executionReason ?? null,
          available: action.state?.available ?? null,
          resourceSufficient: action.state?.resourceSufficient ?? null,
          cooldown: action.cooldown ?? null,
          sourceCharacterId: requestCtx.sourceCharacterId,
          targetCharacterId: requestCtx.targetCharacterId,
          targetTokenId: evalCtx.targetTokenId,
          ok: outcome.ok,
          code: outcomeCode,
          message: outcome.error ?? null,
          stage: outcome?.raw?.stage ?? null,
          stale,
          queueKey,
        }, outcome.ok);
        if (outcome.ok && outcome.normalized) {
          logDebugEvent("abilities", "directed-ability-cost-consumed", {
            characterActionId: actionId,
            actionCost: outcome.normalized.actionCost,
            moveCost: outcome.normalized.moveCost,
            usedReaction: outcome.normalized.usedReaction,
            resourceSpent: outcome.normalized.resourceSpent,
            encounterStateVersionBefore: sessionAtRequest.version ?? null,
            encounterStateVersionAfter: outcome.normalized.encounterStateVersion,
          }, true);
        }
        if (outcomeCode === "STATE_VERSION_CONFLICT") {
          logDebugEvent("session", "stale-version", { command: "directed-ability" }, true);
        }

        if (stale) {
          if (lastState) publishState(lastState);
          return;
        }

        await refreshCombatSessionSafe(sessionController, "directed-ability");

        if (outcome.ok) {
          ephemeral.commandStatus = { type: "ok", message: "Ability used." };
          // Target/zone are NEVER reset after a successful directed ability
          // — only a best-effort, non-clearing refresh of the target's own
          // body-zone condition is requested, same as the weapon-attack/
          // direct-ability-attack success paths.
          try {
            OBR.broadcast.sendMessage(BC_HUD_TARGETING_COMMAND, { type: "refreshBodyZones" }, { destination: "LOCAL" });
            logDebugEvent("refresh", "target-refresh-result", { reason: "directed-ability-success", targetCharacterId: requestCtx.targetCharacterId }, true);
          } catch (_e) { /* best-effort */ }
          await refreshSelectedCharacterRuntime("directed-ability-success", { refreshQuickbar: true, insideCharacterQueue: true });
          logDebugEvent("refresh", "source-refresh-result", { reason: "directed-ability-success", queueKey }, true);
        } else {
          ephemeral.commandStatus = { type: "error", message: outcome.error || "Ability failed." };
          await refreshSelectedCharacterRuntime("directed-ability-failure", { refreshQuickbar: true, insideCharacterQueue: true });
          logDebugEvent("refresh", "source-refresh-result", { reason: "directed-ability-failure", queueKey }, true);
        }
          }, { queueKey });
        } finally {
          ephemeral.pendingDirectedAbilityActionId = null;
          markCombatActionFinished(requestCtx.sourceCharacterId, inFlightDirectedAbilityActionKey);
        }
        return;
      }

      // Basic Weapon Attack v1: same namespaced-scope routing pattern as
      // fire-mode above — cannot collide with weapon/magazine/reload/target/
      // skill/arrange commands regardless of `type` string reuse.
      if (command?.scope === "combat-hud" && command?.feature === "basic-attack") {
        const baType = String(command.type ?? "");
        if (baType !== "execute") return; // unknown → ignore
        logDebugEvent("attack", "requested", {});

        // Double-submit guard: a second "execute" while one is in flight is a
        // no-op, not a queued second attack.
        if (ephemeral.basicAttackInFlight) return;

        const weapon = lastPayload.hudSnapshot?.weapon?.primary ?? null;
        const targeting = ephemeral.targeting ?? {};
        const evalCtx = {
          sourceCharacterId: ephemeral.characterId,
          weaponId: weapon?.id ?? null,
          targetTokenId: targeting.selectedTargetIds?.[0] ?? null,
          targetCharacterId: targeting.selectedTargetCharacterId ?? null,
          bodyZoneId: targeting.selectedBodyPartId ?? null,
          resolvedBodyPartId: targeting.resolvedBodyPartId ?? null,
          inFlight: false,
        };
        const evalResult = evaluateBasicAttack(evalCtx);
        ephemeral.commandStatus = null;
        if (!evalResult.uiAllowed) {
          ephemeral.commandStatus = { type: "error", message: evalResult.uiBlockReason };
          ephemeral.basicAttackResult = { ok: false, error: "PRECONDITION_FAILED", message: evalResult.uiBlockReason };
          logDebugEvent("attack", "blocked", { reason: evalResult.uiBlockReason }, false);
          if (lastState) publishState(lastState);
          return;
        }

        // Phase 3E.0: client-side session pre-gate (UX mirror only — the
        // server re-checks turn/MAIN inside perform_attack regardless). A
        // blocked attack never reaches the RPC and never spends anything.
        const sessionAtRequest = currentMappedSession();
        const sessionGate = sessionAttackGate(sessionAtRequest);
        if (sessionGate.blocked) {
          ephemeral.commandStatus = { type: "error", message: sessionGate.reason };
          ephemeral.basicAttackResult = { ok: false, error: "SESSION_GATE", message: sessionGate.reason };
          logDebugEvent("attack", "session-gate-blocked", { reason: sessionGate.reason, sessionId: sessionAtRequest.id, round: sessionAtRequest.roundNumber }, false);
          if (lastState) publishState(lastState);
          return;
        }

        // Snapshot the source/weapon/target this request is FOR. If any of
        // them changed by the time the RPC resolves, the result must not be
        // applied to the (now different) HUD state — see the staleness check
        // below.
        const requestCtx = { sourceCharacterId: evalCtx.sourceCharacterId, weaponId: evalCtx.weaponId, targetCharacterId: evalCtx.targetCharacterId };
        const bodyZoneLabel = getZoneLabel(DEFAULT_PROFILE_ID, evalCtx.bodyZoneId) || evalCtx.bodyZoneId;
        // Phase 4.1A: whichever technique is armed for THIS attacker at
        // request time travels with the request — a later re-arm/disarm while
        // the RPC is in flight must not retroactively change what this
        // specific attack asked for.
        const requestArmedActionId = armedTechniqueMemory.get(evalCtx.sourceCharacterId);
        const ctx = buildBasicAttackCtx({
          sourceCharacterId: evalCtx.sourceCharacterId,
          weaponId: evalCtx.weaponId,
          targetCharacterId: evalCtx.targetCharacterId,
          bodyPartId: evalCtx.resolvedBodyPartId,
          distance: targeting.distance ?? 0,
          // Active session → carry the authoritative session context so the
          // server can optimistic-concurrency-check it. (The server gate does
          // NOT trust these fields — it derives participation itself.)
          roomContext: sessionAtRequest.exists
            ? { encounterId: sessionAtRequest.id ?? undefined }
            : {},
          expectedEncounterVersion: expectedVersionOf(sessionAtRequest),
          armedActionIds: requestArmedActionId ? [requestArmedActionId] : [],
          includeRuntimeRefresh: false,
          resultMode: "compact",
        });

        ephemeral.basicAttackInFlight = true;
        logDebugEvent("attack", "payload-prepared", { weaponId: ctx.weaponId, targetCharacterId: ctx.targetCharacterId, bodyZone: evalCtx.bodyZoneId });
        logDebugEvent("attack", "perform_attack-request", {
          encounterId: sessionAtRequest.id ?? null,
          attackerCharacterId: ctx.attackerCharacterId,
          targetCharacterId: ctx.targetCharacterId,
          compact: true,
        }, true, "pending");
        if (requestArmedActionId) {
          logDebugEvent("abilities", "attack-modifier-validation-requested", { characterActionId: requestArmedActionId });
        }
        if (lastState) publishState(lastState); // Action disables immediately

        let outcome;
        try {
          outcome = await resolveAttack(ctx, { performAttack: (payload) => performAttack(payload, settings) });
        } catch (error) {
          // resolveAttack() already catches RPC/network errors internally and
          // returns { ok:false, ... } — this catch only guards a thrown
          // ValidationError (a locally-missing required field).
          outcome = { ok: false, payload: null, raw: null, normalized: null, code: null, error: String(error?.message ?? error ?? "Attack failed.") };
        }

        ephemeral.basicAttackInFlight = false;
        const currentCtx = {
          sourceCharacterId: ephemeral.characterId,
          weaponId: lastPayload.hudSnapshot?.weapon?.primary?.id ?? null,
          targetCharacterId: ephemeral.targeting?.selectedTargetCharacterId ?? null,
        };
        const stale = isAttackResultStale(requestCtx, currentCtx);

        ephemeral.basicAttackResult = { ok: outcome.ok, error: outcome.code ?? null, message: outcome.error ?? null };
        // Logged regardless of staleness — a stale result is still a REAL
        // thing that happened, attributed to the request it actually
        // belongs to (requestCtx), never to whatever is currently selected.
        pushLog(buildAttackLogEntry({
          sourceCharacterId: requestCtx.sourceCharacterId,
          targetCharacterId: requestCtx.targetCharacterId,
          bodyZoneLabel,
          outcome,
        }));
        logDebugEvent("attack", "result", { ok: outcome.ok, error: outcome.code ?? null, stale }, outcome.ok);
        // Full authoritative roll trace (Debug Console detail area / Copy
        // event). ONLY for a genuinely resolved attack — an { ok:false }
        // denial or an exception must never produce a fake roll-resolution
        // entry (the failure is already recorded by the `result` event above).
        if (outcome.ok) {
          logDebugEvent(
            "attack",
            "roll-resolution",
            buildRollResolutionDetails(buildAttackResolutionTrace(outcome)),
            true,
          );
        }
        // Phase 3E.0: server-confirmed session cost (MAIN spent on hit AND
        // miss identically) — logged from the server's own summary, then the
        // authoritative session state is re-read (never mutated locally).
        const sessionCost = outcome.raw?.combat_session ?? null;
        if (sessionCost && typeof sessionCost === "object") {
          logDebugEvent("attack", "action-cost-consumed", {
            sessionId: sessionCost.encounter_id ?? null,
            round: sessionCost.round ?? null,
            participant: sessionCost.participant_entry_id ?? null,
            versionBefore: sessionCost.state_version_before ?? null,
            versionAfter: sessionCost.state_version_after ?? null,
            mainAfter: sessionCost.main_available_after ?? null,
            moveAfter: sessionCost.move_available_after ?? null,
            usedReaction: sessionCost.used_reaction ?? null,
          });
        }
        if (outcome.code === "STATE_VERSION_CONFLICT") {
          logDebugEvent("session", "stale-version", { command: "attack" }, true);
        }
        if ((sessionCost || outcome.code === "STATE_VERSION_CONFLICT") && sessionController) {
          void sessionController.refresh();
        }

        if (stale) {
          // Source/weapon/target changed mid-flight: never apply this result
          // to the new HUD state (no toast, no target/zone reset, no refresh
          // tied to the OLD context) — just stop showing "resolving".
          if (lastState) publishState(lastState);
          return;
        }

        // Phase 4.1A: what happened to the armed technique for THIS request —
        // applied (consumed; clear it so it doesn't look armed for the NEXT
        // attack), rejected pre-attack or post-roll (left armed on purpose —
        // "ARMED очищается только по server confirmation", never by a bare
        // click on Attack), or nothing (no technique was armed here).
        if (requestArmedActionId) {
          const preRollValidated = outcome.ok || !ARMED_TECHNIQUE_ERROR_CODES.has(outcome.code);
          logDebugEvent("abilities", "attack-modifier-validation-result", {
            characterActionId: requestArmedActionId,
            validated: preRollValidated,
          }, preRollValidated);
          if (outcome.ok) {
            const armedActions = Array.isArray(outcome.raw?.armed_actions) ? outcome.raw.armed_actions : [];
            for (const entry of armedActions) {
              const actionId = entry?.characterActionId ?? requestArmedActionId;
              if (entry?.applied === true) {
                armedTechniqueMemory.forget(requestCtx.sourceCharacterId);
                logDebugEvent("abilities", "attack-modifiers-applied", { characterActionId: actionId, name: entry.name ?? null }, true);
                logDebugEvent("abilities", "attack-technique-cost-consumed", { characterActionId: actionId, costsConsumed: entry.costsConsumed ?? null }, true);
                if (entry.cooldownBefore !== entry.cooldownAfter) {
                  logDebugEvent("abilities", "attack-technique-cooldown-updated", {
                    characterActionId: actionId,
                    cooldownBefore: entry.cooldownBefore ?? null,
                    cooldownAfter: entry.cooldownAfter ?? null,
                  }, true);
                }
              } else {
                logDebugEvent("abilities", "attack-modifier-rejected", { characterActionId: actionId, reason: entry?.reason ?? null }, false);
              }
            }
          } else if (ARMED_TECHNIQUE_ERROR_CODES.has(outcome.code)) {
            logDebugEvent("abilities", "attack-modifier-rejected", { characterActionId: requestArmedActionId, reason: outcome.code }, false);
          }
        }

        if (outcome.ok) {
          ephemeral.commandStatus = { type: "ok", message: "Attack resolved." };
          // Phase 3D.1: the selected target + body zone are NOT reset after a
          // successful attack — the player must be able to re-attack the same
          // target without re-picking it. Target/zone are only ever cleared by
          // explicit Cancel/Escape/clear, a source-character change, or the
          // target token/link disappearing (all owned by the targeting
          // controller itself). Only a best-effort, NON-clearing refresh of the
          // target's own (safe, combat-only) body-zone condition is requested,
          // so its silhouette colors reflect the damage this attack just did.
          try { OBR.broadcast.sendMessage(BC_HUD_TARGETING_COMMAND, { type: "refreshBodyZones" }, { destination: "LOCAL" }); } catch (_e) { /* best-effort */ }
          await refreshCombatSessionSafe(sessionController, "attack-success");
          await refreshSelectedCharacterRuntime("attack-success", { refreshQuickbar: true });
          logDebugEvent("refresh", "source-refresh-result", { reason: "attack-success" }, true);
        } else {
          ephemeral.commandStatus = { type: "error", message: outcome.error || "Attack failed." };
          await refreshCombatSessionSafe(sessionController, "attack-failure");
          await refreshSelectedCharacterRuntime("attack-failure", { refreshQuickbar: true });
          logDebugEvent("refresh", "source-refresh-result", { reason: "attack-failure" }, true);
        }
        return;
      }

      const type = String(command.type ?? "");
      ephemeral.commandStatus = null;
      if (type === "select-weapon") {
        // Weapon selection is server-authoritative. The HUD asks the backend to
        // switch the active weapon, then refetches the authoritative armory/runtime.
        const weaponId = String(command.weaponId ?? "").trim() || null;
        const session = currentMappedSession();
        const activeWeaponId = String(lastPayload?.hudSnapshot?.weapon?.primary?.id ?? "").trim() || null;
        const availableWeapons = Array.isArray(lastPayload?.hudSnapshot?.weapon?.available)
          ? lastPayload.hudSnapshot.weapon.available
          : [];
        const selectedOption = availableWeapons.find((option) => String(option?.id ?? "").trim() === weaponId) ?? null;
        logDebugEvent("weapon", "switch_active_weapon:start", {
          characterId: ephemeral.characterId,
          targetWeaponId: weaponId,
          previousActiveWeaponId: activeWeaponId,
          encounterId: session?.id ?? null,
        });
        if (!weaponId || !ephemeral.characterId) {
          const message = "Weapon switch unavailable.";
          ephemeral.commandStatus = { type: "error", message, source: "weapon_overlay", operation: "switch_active_weapon", code: "WEAPON_SWITCH_UNAVAILABLE" };
          logDebugEvent("weapon", "switch_active_weapon:error", {
            characterId: ephemeral.characterId,
            targetWeaponId: weaponId,
            code: "WEAPON_SWITCH_UNAVAILABLE",
            message,
          }, false);
          replayLastVisibleState("weapon-switch-unavailable");
          return;
        }
        if (weaponId === activeWeaponId) {
          replayLastVisibleState("weapon-switch-same-weapon");
          return;
        }
        if (selectedOption?.switchAllowed === false) {
          const message = selectedOption.switchBlockedReason || "Weapon switch unavailable.";
          ephemeral.commandStatus = {
            type: "error",
            message,
            source: "weapon_overlay",
            operation: "switch_active_weapon",
            code: "SWITCH_BLOCKED",
          };
          logDebugEvent("weapon", "switch_active_weapon:error", {
            characterId: ephemeral.characterId,
            targetWeaponId: weaponId,
            code: "SWITCH_BLOCKED",
            message,
          }, false);
          replayLastVisibleState("weapon-switch-blocked");
          return;
        }
        ephemeral.selectedReloadMagazineId = null;
        ephemeral.reloadRpcResult = null;
        ephemeral.weaponSelectorOpen = false;
        // A new weapon has its own active profile / fire mode — never carry
        // the previous weapon's selector state or last RPC result forward.
        ephemeral.fireModeSelectorOpen = false;
        ephemeral.fireModeRpcResult = null;
        try {
          const expectedVersion = expectedVersionOf(session);
          const payload = buildSwitchActiveWeaponPayload({
            characterId: ephemeral.characterId,
            weaponId,
            session: session?.exists
              ? { exists: true, id: session.id, version: expectedVersion }
              : null,
          });
          logDebugEvent("weapon", "switch_active_weapon:payload", {
            characterId: ephemeral.characterId,
            targetWeaponId: weaponId,
            encounterId: payload.encounter_id ?? null,
            expectedEncounterVersion: payload.expected_encounter_version ?? null,
          });
          const result = await switchActiveWeapon(payload, settings);
          if (result?.ok === false) {
            const message = resolveWeaponSwitchErrorMessage(result);
            ephemeral.commandStatus = {
              type: "error",
              message,
              source: "weapon_overlay",
              operation: "switch_active_weapon",
              code: result.error ?? "WEAPON_SWITCH_FAILED",
            };
            logDebugEvent("weapon", "switch_active_weapon:error", {
              characterId: ephemeral.characterId,
              targetWeaponId: weaponId,
              code: result.error ?? "WEAPON_SWITCH_FAILED",
              message,
              details: result,
            }, false);
            if (result?.error === "STATE_VERSION_CONFLICT" && sessionController) {
              await refreshCombatSessionSafe(sessionController, "weapon-switched-state-version-conflict");
            }
            replayLastVisibleState("weapon-switch-failed");
            return;
          }
          ephemeral.commandStatus = {
            type: "ok",
            message: "Weapon switched.",
            source: "weapon_overlay",
            operation: "switch_active_weapon",
          };
          logDebugEvent("weapon", "switch_active_weapon:success", {
            characterId: ephemeral.characterId,
            targetWeaponId: weaponId,
            resultActiveWeaponId: String(result?.active_weapon_id ?? "").trim() || null,
            activeWeaponIdFromArmory: String(result?.armory?.active_weapon_id ?? "").trim() || null,
          }, true);
          await refreshHeavyCharacterData(ephemeral.characterId, {
            reason: "weapon-switched",
            encounterId: session?.exists ? session.id : null,
            armory: true,
            inventory: true,
          });
          await refreshCombatSessionSafe(sessionController, "weapon-switched");
          await refreshSelectedCharacterRuntime("weapon-switched", { refreshQuickbar: true });
          return;
        } catch (error) {
          const message = String(error?.message ?? error ?? "Weapon switch failed.");
          ephemeral.commandStatus = {
            type: "error",
            message,
            source: "weapon_overlay",
            operation: "switch_active_weapon",
            code: "RPC_EXCEPTION",
          };
          logDebugEvent("weapon", "switch_active_weapon:error", {
            characterId: ephemeral.characterId,
            targetWeaponId: weaponId,
            code: "RPC_EXCEPTION",
            message,
          }, false);
          replayLastVisibleState("weapon-switch-exception");
          return;
        }
      }
      if (type === "toggle-weapon-selector") {
        ephemeral.weaponSelectorOpen = !ephemeral.weaponSelectorOpen;
        logDebugEvent("weapon", "selector-toggled", { open: ephemeral.weaponSelectorOpen });
        if (ephemeral.weaponSelectorOpen && ephemeral.characterId) {
          void refreshHeavyCharacterData(ephemeral.characterId, {
            reason: "weapon-selector-opened",
            encounterId: currentMappedSession()?.id ?? null,
            armory: true,
            inventory: true,
          }).then(() => refetchCurrent("weapon-selector-opened"));
        }
        if (lastState) publishState(lastState);
        return;
      }
      if (type === "close-weapon-selector") {
        ephemeral.weaponSelectorOpen = false;
        if (lastState) publishState(lastState);
        return;
      }
      if (type === "select-reload-mag") {
        ephemeral.selectedReloadMagazineId = String(command.magazineId ?? "").trim() || null;
        logDebugEvent("magazine", "selected", { magazineId: ephemeral.selectedReloadMagazineId });
        if (lastState) publishState(lastState);
        return;
      }
      if (type === "prepare-skill") {
        const skillId = String(command.skillId ?? "").trim();
        ephemeral.preparedAction = ephemeral.preparedAction?.id === skillId ? null : { kind: "skill", id: skillId };
        if (lastState) publishState(lastState);
        return;
      }
      if (type === "pick-target" || type === "cancel-target" || type === "clear-target" || type === "select-target-zone") {
        return;
      }
      if (type === "reload") {
        const weapon = lastPayload.hudSnapshot?.weapon?.primary ?? null;
        const weaponId = String(command.weaponId ?? weapon?.id ?? "").trim();
        // The player's EXPLICIT selection wins outright — the HUD must never
        // silently substitute a different magazine (e.g. reserve[0]). See
        // reloadPolicy.js for the shared, unit-tested fallback chain.
        const magazineId = resolveReloadMagazineId(command, ephemeral, weapon) ?? "";
        const profileId = weapon?.activeProfileId ?? weapon?.active_profile_id ?? weapon?.profileId ?? null;
        logDebugEvent("magazine", "reload-requested", { weaponId, magazineId });

        // Phase 3E.0: client-side MOVE pre-gate (UX mirror — the server
        // re-checks turn/MOVE inside load_weapon_profile_magazine anyway).
        const reloadSession = currentMappedSession();
        const reloadGate = sessionReloadGate(reloadSession, weapon?.reloadCost ?? "full_move");
        if (reloadGate.blocked) {
          ephemeral.commandStatus = { type: "error", message: reloadGate.reason };
          ephemeral.reloadRpcResult = { ok: false, error: "SESSION_GATE", message: reloadGate.reason };
          logDebugEvent("reload", "session-gate-blocked", { reason: reloadGate.reason, sessionId: reloadSession.id, round: reloadSession.roundNumber }, false);
          if (lastState) publishState(lastState);
          return;
        }

        if (!weaponId || !magazineId || !profileId) {
          ephemeral.commandStatus = { type: "error", message: "Reload unavailable: missing weapon profile or magazine." };
          ephemeral.reloadRpcResult = { ok: false, error: "MISSING_FIELDS", message: "weaponId/profileId/magazineId missing before RPC call." };
          pushLog(buildReloadLogEntry({ sourceCharacterId: ephemeral.characterId, ok: false, message: ephemeral.commandStatus.message }));
          logDebugEvent("magazine", "reload-result", { error: "MISSING_FIELDS" }, false);
          if (lastState) publishState(lastState);
          return;
        }
        try {
          const expectedVersion = expectedVersionOf(reloadSession);
          const result = await loadWeaponProfileMagazine(
            {
              character_weapon_id: weaponId,
              profile_id: profileId,
              character_magazine_id: magazineId,
              ...(expectedVersion != null ? { expected_encounter_version: expectedVersion } : {}),
            },
            settings,
          );
          // The RPC returns { ok:false, error, message } as a normal (HTTP 200)
          // jsonb body on validation failures — it does NOT throw. Treating any
          // non-throwing call as success silently swallowed real backend
          // rejections (the UI reported "Reloaded." while nothing changed).
          const normalized = normalizeReloadRpcResult(result);
          ephemeral.reloadRpcResult = normalized;
          if (normalized.ok) {
            ephemeral.commandStatus = { type: "ok", message: "Reloaded." };
            ephemeral.selectedReloadMagazineId = null;
            pushLog(buildReloadLogEntry({ sourceCharacterId: ephemeral.characterId, ok: true, message: "Reloaded." }));
            logDebugEvent("magazine", "reload-result", { weaponId, magazineId }, true);
            // Phase 3E.0: server-confirmed MOVE cost — only a successful swap
            // spends it; re-read the authoritative session state afterwards.
            const reloadCost = result?.combat_session ?? null;
            if (reloadCost && typeof reloadCost === "object") {
              logDebugEvent("reload", "action-cost-consumed", {
                sessionId: reloadCost.encounter_id ?? null,
                round: reloadCost.round ?? null,
                participant: reloadCost.participant_entry_id ?? null,
                versionBefore: reloadCost.state_version_before ?? null,
                versionAfter: reloadCost.state_version_after ?? null,
                mainAfter: reloadCost.main_available_after ?? null,
                moveAfter: reloadCost.move_available_after ?? null,
              });
              if (sessionController) void sessionController.refresh();
            }
            await refreshHeavyCharacterData(ephemeral.characterId, {
              reason: "reload-success",
              encounterId: reloadSession?.id ?? null,
              armory: true,
              inventory: true,
            });
            await refreshSelectedCharacterRuntime("reload-success", { refreshQuickbar: true });
          } else {
            ephemeral.commandStatus = { type: "error", message: normalized.message || normalized.error || "Reload failed." };
            pushLog(buildReloadLogEntry({ sourceCharacterId: ephemeral.characterId, ok: false, message: ephemeral.commandStatus.message }));
            logDebugEvent("magazine", "reload-result", { weaponId, magazineId, error: normalized.error }, false);
            if (normalized.error === "STATE_VERSION_CONFLICT") {
              logDebugEvent("session", "stale-version", { command: "reload" }, true);
              if (sessionController) void sessionController.refresh();
            }
            if (lastState) publishState(lastState);
          }
        } catch (error) {
          ephemeral.reloadRpcResult = { ok: false, error: "RPC_EXCEPTION", message: String(error?.message ?? error ?? "Reload failed.") };
          ephemeral.commandStatus = { type: "error", message: String(error?.message ?? error ?? "Reload failed.") };
          pushLog(buildReloadLogEntry({ sourceCharacterId: ephemeral.characterId, ok: false, message: ephemeral.commandStatus.message }));
          logDebugEvent("magazine", "reload-result", { error: "RPC_EXCEPTION", message: ephemeral.commandStatus.message }, false);
          if (lastState) publishState(lastState);
        }
      }
    }

    async function resolveAndPublish(selectionIds, reason = "selection-change", options = {}) {
      const allowWhileDeferred = options?.allowWhileDeferred === true;
      const generation = Number.isFinite(Number(options?.generation)) ? Number(options.generation) : null;
      if (shouldDeferSelection() && !allowWhileDeferred) {
        logDebugEvent("selection", "selection-refresh-deferred", { tokenIds: selectionIds, reason }, true, "pending");
        return;
      }
      selectedRuntimeReason = reason;
      const nextSelectionIds = Array.isArray(selectionIds) ? selectionIds.slice() : [];
      const previousCharacterId = lastResolvedCharacterId ?? lastPayload?.characterId ?? lastState?.characterId ?? null;
      const previousTokenId = lastResolvedTokenId ?? lastPayload?.selectedItemId ?? currentSelectionIds[0] ?? null;
      const resolveSignature = nextSelectionIds.join("|");
      pendingSelectionIds = nextSelectionIds.slice();
      logDebugEvent("selection", "source-token-selected", { tokenIds: nextSelectionIds, reason });
      let state = null;
      let resolvedFresh = false;
      try {
        const result = await adapter.resolveLatest(nextSelectionIds);
        if (disposed || result?.stale || (generation !== null && generation !== selectionResolveGeneration)) return null; // only the freshest selection updates the HUD
        state = result?.state ?? null;
        resolvedFresh = true;
      } finally {
        if (!resolvedFresh && pendingSelectionIds.join("|") === resolveSignature) {
          pendingSelectionIds = [];
        }
      }
      if (!state) {
        if (pendingSelectionIds.join("|") === resolveSignature) {
          pendingSelectionIds = [];
        }
        return null;
      }
      if (generation !== null && generation !== selectionResolveGeneration) {
        return null;
      }
      if (state.status !== "ready") {
        const unavailableReason = state.error?.code ?? state.access?.reason ?? null;
        if (state.status !== "no-selection" && unavailableReason !== "NO_TOKEN_SELECTED") {
          logDebugEvent("selection", "source-character-unavailable", { status: state.status ?? null, reason: unavailableReason }, false);
        }
        resetEphemeralForCharacter(null);
      } else {
        const changed = resetEphemeralForCharacter(state.characterId ?? null);
        if (changed) restoreSelectedWeapon(state.characterId ?? null, state.runtimeBundle);
        const activeWeapon = pickActiveWeapon(state.runtimeBundle?.armory ?? state.runtimeBundle?.sections?.armory ?? null);
        const activeWeaponId = String(activeWeapon?.id ?? "").trim() || null;
        ephemeral.selectedWeaponId = activeWeaponId;
        if (state.characterId) {
          if (activeWeaponId) selectedWeaponMemory.set(state.characterId, activeWeaponId);
          else selectedWeaponMemory.forget(state.characterId);
        }
      }
      currentSelectionIds = nextSelectionIds.slice();
      lastState = state;
      const nextCharacterId = state?.characterId ?? null;
      const nextTokenId = state?.selectedItemId ?? nextSelectionIds[0] ?? null;
      if (previousCharacterId !== nextCharacterId || previousTokenId !== nextTokenId) {
        logDebugEvent("selection", "selected-character-changed", {
          previousCharacterId,
          nextCharacterId,
          previousTokenId,
          nextTokenId,
          reason,
        });
      }
      if (pendingSelectionIds.join("|") === resolveSignature) {
        pendingSelectionIds = [];
      }
      const payload = publishState(state, reason);
      if (reason === "selection-request-hydrate") {
        logDebugEvent("selection", "selection-hydrate-resolved", {
          tokenIds: currentSelectionIds,
          status: state?.status ?? null,
          characterId: state?.characterId ?? null,
          error: state?.error?.code ?? null,
        }, state?.status === "ready");
      }
      if (onSelectionState) {
        try { await onSelectionState(payload); } catch (_e) { /* controller handles its own errors */ }
      }
      return payload;
    }

    // Initial resolve from the LIVE current selection, not only the startup
    // player snapshot. In Owlbear the initial snapshot can lag behind the
    // actual selection state when the HUD/background boots after the user has
    // already selected a linked token.
    await resolveAndPublish(await readLiveSelectionIds(player.selection), "startup");

    // Selection / role changes (OBR.player.onChange carries selection + role).
    cleanups.push(await subscribePlayerChanges((p) => {
      viewer = normalizeViewer({ playerId: p.id, role: p.role });
      if (shouldDeferSelection()) return;
      void readLiveSelectionIds(p.selection)
        .then((selectionIds) => {
          onObservedSelectionChanged(selectionIds, "selection-changed");
        })
        .catch(() => {
          onObservedSelectionChanged(p.selection, "selection-changed:fallback");
        });
    }));

    // Scene items can change a token's link while it stays selected. Debounced,
    // single-selection-only re-resolve keeps the binding fresh without RPC spam.
    cleanups.push(await subscribeSceneItems(() => {
      if (sceneTimer) clearTimeout(sceneTimer);
      sceneTimer = setTimeout(() => {
        if (shouldDeferSelection()) return;
        readLiveSelectionIds(currentSelectionIds)
          .then((sel) => { if (Array.isArray(sel) && sel.length === 1) return scheduleLiveSelectionResolve("scene-items-changed", { forceResolve: true }); })
          .catch(() => {});
      }, SCENE_RERESOLVE_DEBOUNCE_MS);
    }));

    // Replay the latest state to a module iframe that just mounted.
    cleanups.push(OBR.broadcast.onMessage(BC_HUD_SELECTION_REQUEST, (event) => {
      const requestedSelectionIds = Array.isArray(event?.data?.selectionIds)
        ? event.data.selectionIds.map((value) => String(value ?? "").trim()).filter(Boolean)
        : [];
      const requestedSignature = requestedSelectionIds.join("|");
      const currentSignature = currentSelectionIds.join("|");
      const pendingSignature = pendingSelectionIds.join("|");
      const shouldHydrateFromRequest = event?.data?.hydrateIfStale === true
        && requestedSelectionIds.length === 1
        && requestedSignature !== currentSignature
        && requestedSignature !== pendingSignature
        && (!lastPayload || lastPayload.status === "no-selection" || lastPayload.status === "loading");
      if (event?.data?.hydrateIfStale === true && requestedSelectionIds.length === 1 && requestedSignature === pendingSignature) {
        logDebugEvent("selection", "selection-hydrate-skipped", {
          reason: "same-pending-selection",
          requestedSelectionIds,
          currentSelectionIds,
          pendingSelectionIds,
        });
      }
      if (shouldHydrateFromRequest) {
        void readLiveSelectionIds(currentSelectionIds)
          .then((liveSelectionIds) => {
            const liveSignature = liveSelectionIds.join("|");
            if (liveSignature !== requestedSignature) {
              logDebugEvent("selection", "selection-hydrate-skipped", {
                reason: "requested-selection-not-live",
                requestedSelectionIds,
                liveSelectionIds,
                currentSelectionIds,
                currentStatus: lastPayload?.status ?? null,
                currentCharacterId: lastPayload?.characterId ?? null,
              });
              if (lastPayload && lastPayload.selectedItemId === currentSelectionIds[0]) {
                broadcast(lastPayload);
              }
              return;
            }
            pendingSelectionIds = liveSelectionIds.slice();
            logDebugEvent("selection", "selection-hydrate-requested", {
              tokenIds: liveSelectionIds,
              previousStatus: lastPayload?.status ?? null,
              previousCharacterId: lastPayload?.characterId ?? null,
              currentSelectionIds,
              reason: "selection-request",
            }, true, "pending");
            void resolveAndPublish(liveSelectionIds, "selection-request-hydrate", { allowWhileDeferred: true }).catch((error) => {
              logDebugEvent("selection", "selection-hydrate-failed", {
                tokenIds: liveSelectionIds,
                message: String(error?.message ?? error ?? "Unable to hydrate selection."),
                reason: "selection-request",
              }, false);
            });
          })
          .catch((error) => {
            logDebugEvent("selection", "selection-hydrate-skipped", {
              reason: "live-selection-read-failed",
              requestedSelectionIds,
              currentSelectionIds,
              message: String(error?.message ?? error ?? "Unable to read live selection."),
            }, false);
            if (lastPayload && lastPayload.selectedItemId === currentSelectionIds[0]) {
              broadcast(lastPayload);
            }
          });
        return;
      }
      if (lastPayload && pendingSelectionIds.length === 1 && lastPayload.selectedItemId !== pendingSelectionIds[0]) {
        logDebugEvent("selection", "selection-replay-skipped", {
          reason: "pending-selection-mismatch",
          payloadSelectedItemId: lastPayload.selectedItemId ?? null,
          currentSelectionIds,
          pendingSelectionIds,
          requestedSelectionIds,
        });
        return;
      }
      if (lastPayload) {
        broadcast(lastPayload);
        logDebugEvent("selection", "selection-replayed", {
          status: lastPayload.status ?? null,
          characterId: lastPayload.characterId ?? null,
          selectedItemId: lastPayload.selectedItemId ?? null,
          reason: "selection-request",
        });
        return;
      }
      scheduleLiveSelectionResolve("selection-request-initial", { forceResolve: true });
    }));

    cleanups.push(OBR.broadcast.onMessage(BC_HUD_COMMAND, (event) => {
      void handleCommand(event?.data).catch((error) => {
        logDebugEvent("routing", "unexpected-exception", {
          type: String(event?.data?.type ?? ""),
          feature: event?.data?.feature ?? null,
          message: String(error?.message ?? error ?? "unknown error"),
        }, false);
      });
    }));

    cleanup.applyTargetingPayload = applyTargetingPayload;
  }

  OBR.onReady(() => {
    if (disposed) return;
    void init().catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[combatHud/scene] selection setup failed", error);
    });
  });

  function cleanup() {
    disposed = true;
    if (sceneTimer) { clearTimeout(sceneTimer); sceneTimer = null; }
    clearTransientEmptySelectionTimer();
    selectionRefreshScheduler.cancel();
    for (const fn of cleanups.splice(0)) { try { fn(); } catch (_e) { /* ignore */ } }
  }

  cleanup.applyTargetingPayload = () => {};
  return cleanup;
}
