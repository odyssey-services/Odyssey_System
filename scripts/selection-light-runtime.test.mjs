import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { createSceneSelectionAdapter } from "../hud/scene/sceneSelectionAdapter.js";
import { SELECTION_STATUS } from "../hud/scene/selectionState.js";
import { normalizeRpcError } from "../utils/rpcErrorNormalizer.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const readText = (...segments) =>
  fs.readFileSync(path.join(repoRoot, ...segments), "utf8").replace(/\r\n/g, "\n");

const sceneControllerSrc = readText("hud", "scene", "sceneSelectionController.js");
const resolverSrc = readText("selection", "stableOwlbearSelectionResolver.js");

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  PASS ${name}`);
  } catch (error) {
    failed += 1;
    failures.push({ name, error });
    console.error(`  FAIL ${name}\n      ${error.message}`);
  }
}

async function asyncTest(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`  PASS ${name}`);
  } catch (error) {
    failed += 1;
    failures.push({ name, error });
    console.error(`  FAIL ${name}\n      ${error.message}`);
  }
}

console.log("\nSelection Light Runtime\n");

function createAdapter(fetchCharacterBundle) {
  return createSceneSelectionAdapter({
    backendConfigured: true,
    getViewer: () => ({ playerId: "player-1", role: "GM" }),
    fetchSceneTokenLink: async () => ({
      ok: true,
      links: [{
        token_id: "token-1",
        is_active: true,
        character: { id: "char-1", display_name: "Hero" },
      }],
    }),
    fetchCharacterBundle,
  });
}

await asyncTest("selection ready uses light runtime success", async () => {
  const adapter = createAdapter(async () => ({
    ok: true,
    character: { owner_player_id: "player-1", character_key: "hero" },
    state: { is_alive: true, is_conscious: true, status_summary: "Ready" },
    sections: { summary: {}, combat: {} },
  }));

  const state = await adapter.resolve(["token-1"]);
  assert.equal(state.status, SELECTION_STATUS.ready);
  assert.equal(state.access.canView, true);
  assert.equal(state.characterId, "char-1");
});

test("inventory failure does not make selection unavailable in staged runtime flow", () => {
  assert.ok(sceneControllerSrc.includes("const runtimeBundle = await fetchLightRuntimeBundle(resolvedState.characterId, reason);"));
  assert.ok(!sceneControllerSrc.includes("Promise.all([\n          getCharacterRuntimeBundle("));
  assert.ok(sceneControllerSrc.includes("panel: \"inventory\""));
  assert.ok(sceneControllerSrc.includes("heavy-fetch-failed"));
  assert.ok(sceneControllerSrc.includes("heavy-fetch-result"));
});

test("armory failure does not make selection unavailable in staged runtime flow", () => {
  assert.ok(sceneControllerSrc.includes("panel: \"armory\""));
  assert.ok(sceneControllerSrc.includes("return hydrateBundleWithHeavyCache(bundle, characterId);"));
  assert.ok(sceneControllerSrc.includes("refreshHeavyCharacterData("));
});

test("light runtime hydrates heavy weapon data before the first ready payload when cache is stale", () => {
  assert.ok(sceneControllerSrc.includes("if (isWeaponHeavyCacheStale(characterId, encounterId)) {"));
  assert.ok(sceneControllerSrc.includes("reason: `${reason}:hydrate-heavy-before-ready`"));
  assert.ok(sceneControllerSrc.includes("armory: true"));
  assert.ok(sceneControllerSrc.includes("inventory: true"));
});

test("runtime-only refresh rehydrates heavy armory cache before replacing the ready bundle", () => {
  assert.ok(sceneControllerSrc.includes("const hydratedRuntimeBundle = hydrateBundleWithHeavyCache(runtimeBundle, characterId);"));
  assert.ok(sceneControllerSrc.includes("runtimeBundle: hydratedRuntimeBundle"));
  assert.ok(sceneControllerSrc.includes("view: buildReadySelectionView(hydratedRuntimeBundle)"));
});

test("weapon heavy preload is scheduled after ready selection without blocking selection resolve", () => {
  assert.ok(sceneControllerSrc.includes("safeScheduleWeaponHeavyPreload(nextCharacterId, nextTokenId, \"selection-ready-preload\")"));
  assert.ok(sceneControllerSrc.includes("weapon-data-preloaded"));
  assert.ok(sceneControllerSrc.includes("shouldPreloadWeaponData("));
  assert.ok(sceneControllerSrc.includes("weapon-data-preload-schedule-failed"));
});

test("heavy armory and inventory fetches are parallelized and cache-aware", () => {
  assert.ok(sceneControllerSrc.includes("const settled = await Promise.allSettled(tasks.map(async (task) => {"));
  assert.ok(sceneControllerSrc.includes("item.value.panel === \"armory\""));
  assert.ok(sceneControllerSrc.includes("item.value.panel === \"inventory\""));
  assert.ok(sceneControllerSrc.includes("isWeaponHeavyCacheStale("));
  assert.ok(sceneControllerSrc.includes("applyHeavyCacheToLastReadyState("));
  assert.ok(sceneControllerSrc.includes("getCurrentEncounterIdSafe("));
  assert.ok(sceneControllerSrc.includes("weapon-data-preload-start"));
  assert.ok(sceneControllerSrc.includes("weapon-data-preload-skipped"));
});

test("companion force replay uses last ready payload without live selection resolve", () => {
  assert.ok(sceneControllerSrc.includes("replayLastVisibleState(\"companion-force-replay\")"));
  assert.ok(sceneControllerSrc.includes("forceReplay === true"));
});

test("applyHeavyCacheToLastReadyState preserves ready view without buildReadySelectionView dependency", () => {
  assert.ok(sceneControllerSrc.includes("view: lastState.view"));
  assert.ok(!sceneControllerSrc.includes("view: buildReadySelectionView(hydratedBundle)"));
});

test("weapon and magazine selector cache apply is guarded from unexpected exceptions", () => {
  assert.ok(sceneControllerSrc.includes("weapon-selector-cache-apply-failed"));
  assert.ok(sceneControllerSrc.includes("magazine-selector-cache-apply-failed"));
});

test("weapon selector keeps renderable snapshot visible while stale cache refresh runs in background", () => {
  assert.ok(sceneControllerSrc.includes("const WEAPON_HEAVY_CACHE_STALE_MS = 60000;"));
  assert.ok(sceneControllerSrc.includes("function hasRenderableWeaponSnapshot()"));
  assert.ok(sceneControllerSrc.includes("weapon-selector-background-refresh"));
  assert.ok(sceneControllerSrc.includes("magazine-selector-background-refresh"));
  assert.ok(sceneControllerSrc.includes("ephemeral.weaponDataLoading = !hasSnapshot;"));
});

test("post-ready preload failures no longer downgrade a ready selection into error", () => {
  assert.ok(sceneControllerSrc.includes("post-ready-refresh-error-ignored"));
  assert.ok(sceneControllerSrc.includes("normalized.message?.includes(\"currentMappedSession is not defined\")"));
});

test("light runtime timeout is normalized to STATEMENT_TIMEOUT", () => {
  const normalized = normalizeRpcError(new Error("canceling statement due to statement timeout"));
  assert.equal(normalized.error, "STATEMENT_TIMEOUT");
  assert.equal(normalized.retryable, true);
});

test("light runtime timeout retries once", () => {
  assert.ok(sceneControllerSrc.includes("if (normalized.error === \"STATEMENT_TIMEOUT\" && normalized.retryable && attempt < 2)"));
  assert.ok(sceneControllerSrc.includes("await waitMs(LIGHT_RUNTIME_RETRY_DELAY_MS);"));
});

test("startup resolve prefers live OBR selection over the initial player snapshot", () => {
  assert.ok(sceneControllerSrc.includes('stableSelectionResolver?.scheduleSelectionSync({ force: true, reason: "startup" });'));
  assert.ok(resolverSrc.includes("getSelectedOwlbearTokens"));
  assert.ok(resolverSrc.includes("const signature = buildSelectionSignature(selectedTokens);"));
});

test("selection request with existing payload replays only lastPayload", () => {
  assert.ok(sceneControllerSrc.includes("scheduleLiveSelectionResolve(\"selection-request-initial\", { forceResolve: true })"));
  assert.ok(sceneControllerSrc.includes("selection-request-hydrate"));
  assert.ok(sceneControllerSrc.includes("event?.data?.hydrateIfStale === true"));
  assert.ok(sceneControllerSrc.includes("forceResolveIfDifferent"));
  assert.ok(sceneControllerSrc.includes("selection-hydrate-requested"));
  assert.ok(sceneControllerSrc.includes("selection-request-received"));
  assert.ok(sceneControllerSrc.includes("selection-request-resolve-start"));
  assert.ok(sceneControllerSrc.includes("void readLiveSelectionIds(currentSelectionIds)"));
  assert.ok(sceneControllerSrc.includes("if (liveSignature !== requestedSignature)"));
  assert.ok(sceneControllerSrc.includes("selection-hydrate-skipped"));
  assert.ok(sceneControllerSrc.includes("reason: \"requested-selection-not-live\""));
  assert.ok(sceneControllerSrc.includes('stableSelectionResolver?.scheduleSelectionSync({ force: true, reason: "selection-request-hydrate" });'));
});

test("selection request hydrate now supports ready -> ready token recovery", () => {
  assert.ok(!sceneControllerSrc.includes("&& (!lastPayload || lastPayload.status === \"no-selection\" || lastPayload.status === \"loading\")"));
  assert.ok(sceneControllerSrc.includes("const shouldResolveRequestedSelection = ("));
  assert.ok(sceneControllerSrc.includes("forceReplay === true"));
  assert.ok(sceneControllerSrc.includes("&& (event?.data?.hydrateIfStale === true || forceResolveIfDifferent)"));
  assert.ok(sceneControllerSrc.includes("previousCharacterId: lastPayload?.characterId ?? null"));
});

test("stale payload replay is blocked while another selection is pending", () => {
  assert.ok(sceneControllerSrc.includes("selection-replay-skipped"));
  assert.ok(sceneControllerSrc.includes("reason: \"pending-selection-mismatch\""));
  assert.ok(sceneControllerSrc.includes("lastPayload.selectedItemId !== pendingSelectionIds[0]"));
});

test("stale replay for a different requested ready token is blocked", () => {
  assert.ok(sceneControllerSrc.includes("selection-replay-blocked"));
  assert.ok(sceneControllerSrc.includes("reason: \"requested-selection-differs-from-last-payload\""));
  assert.ok(sceneControllerSrc.includes("requestedSignature !== String(lastPayload.selectedItemId)"));
});

test("duplicate requested token replays are deduped before async live-selection read", () => {
  assert.ok(sceneControllerSrc.includes("let pendingSelectionRequestSignature = \"\";"));
  assert.ok(sceneControllerSrc.includes("let pendingSelectionRequestReason = \"\";"));
  assert.ok(sceneControllerSrc.includes("selection-request-deduped"));
  assert.ok(sceneControllerSrc.includes("pendingSelectionRequestSignature === requestedSignature"));
  assert.ok(sceneControllerSrc.includes("pendingSelectionRequestSignature = requestedSignature;"));
  assert.ok(sceneControllerSrc.includes("pendingSelectionIds = requestedSelectionIds.slice();"));
});

test("empty and same-selection request noise is ignored instead of creating pending chains", () => {
  assert.ok(sceneControllerSrc.includes("selection-request-ignored"));
  assert.ok(sceneControllerSrc.includes("reason: \"empty-live-selection\""));
  assert.ok(sceneControllerSrc.includes("reason: \"empty-request-while-ready-sticky\""));
  assert.ok(sceneControllerSrc.includes("reason: \"same-current-selection\""));
  assert.ok(sceneControllerSrc.includes("reason: \"same-pending-selection\""));
  assert.ok(sceneControllerSrc.includes("broadcast(lastPayload);"));
});

test("selection replay is blocked while targeting is actively deferring source selection", () => {
  assert.ok(sceneControllerSrc.includes("if (shouldDeferSelection()) {"));
  assert.ok(sceneControllerSrc.includes('reason: "selection-deferred-targeting-active"'));
  assert.ok(sceneControllerSrc.includes("lastPayloadSelectedItemId: lastPayload?.selectedItemId ?? null"));
  assert.ok(sceneControllerSrc.includes("lastPayloadStatus: lastPayload?.status ?? null"));
  assert.ok(sceneControllerSrc.includes("requestReason: event?.data?.reason ?? null"));
  assert.ok(sceneControllerSrc.includes("if (lastPayload) broadcast(lastPayload);"));
});

test("abilities runtime now updates the selected HUD via module patch instead of selection replay", () => {
  assert.ok(!sceneControllerSrc.includes('event?.data?.reason === "abilities-runtime-updated"'));
  assert.ok(sceneControllerSrc.includes('broadcastReadyStateUpdate(["skills"], "abilities-runtime-loaded");'));
  assert.ok(sceneControllerSrc.includes('logDebugEvent("patch", "module-patch-broadcast"'));
});

test("native selection-changed path remains primary and is logged", () => {
  assert.ok(sceneControllerSrc.includes("selection-change-observed"));
  assert.ok(sceneControllerSrc.includes("previousSelectionIds: currentSelectionIds"));
  assert.ok(sceneControllerSrc.includes("void handleObservedNonEmptySelection(observed, reason).catch(() => {});"));
  assert.ok(sceneControllerSrc.includes("stableSelectionResolver?.runSelectionSync({ force: forceResolve === true, reason })"));
  assert.ok(resolverSrc.includes('log("selection", "selection-resolve-start"'));
  assert.ok(resolverSrc.includes('log("selection", "source-token-selected"'));
});

test("transient empty selection events use grace delay and live-read execution", () => {
  assert.ok(sceneControllerSrc.includes("const TRANSIENT_EMPTY_SELECTION_GRACE_MS = 500;"));
  assert.ok(sceneControllerSrc.includes("if (currentSelectionIds.length > 0 || pendingSelectionIds.length > 0)"));
  assert.ok(sceneControllerSrc.includes("empty-selection-deferred"));
  assert.ok(sceneControllerSrc.includes("empty-selection-ignored"));
  assert.ok(sceneControllerSrc.includes("if (liveSelectionIds.length === 0 && pendingSelectionIds.length === 0)"));
  assert.ok(sceneControllerSrc.includes("reason: \"hud-interaction-active\""));
  assert.ok(sceneControllerSrc.includes("reason: \"sticky-last-selection\""));
  assert.ok(sceneControllerSrc.includes("publishState(lastState, `${reason}:sticky-last-selection`)"));
  assert.ok(sceneControllerSrc.includes("selection-empty-recovered-live"));
  assert.ok(sceneControllerSrc.includes("reason: \"pending-non-empty-selection\""));
  assert.ok(sceneControllerSrc.includes("reason: \"cancelled-by-live-selection\""));
});

test("selection noise from unlinked and non-character items is classified and ignored during HUD interaction", () => {
  assert.ok(sceneControllerSrc.includes("async function classifySelectionIds(selectionIds)"));
  assert.ok(sceneControllerSrc.includes("linked-character-token"));
  assert.ok(sceneControllerSrc.includes("unlinked-token"));
  assert.ok(sceneControllerSrc.includes("drawing-item"));
  assert.ok(sceneControllerSrc.includes("hud-preview-item"));
  assert.ok(sceneControllerSrc.includes("unknown-non-token"));
  assert.ok(sceneControllerSrc.includes("selection-noise-ignored"));
  assert.ok(sceneControllerSrc.includes("function shouldIgnoreUnlinkedSelectionNoise(selectionIds, classification, reason = \"selection-changed\")"));
  assert.ok(sceneControllerSrc.includes("function shouldIgnoreNonCharacterSelection(classification)"));
  assert.ok(sceneControllerSrc.includes("currentCharacterId: lastPayload?.characterId ?? null"));
  assert.ok(sceneControllerSrc.includes("currentSelectedItemId: lastPayload?.selectedItemId ?? null"));
});

test("selected character change and payload broadcast are explicitly logged", () => {
  assert.ok(sceneControllerSrc.includes("selected-character-changed"));
  assert.ok(sceneControllerSrc.includes("selection-payload-broadcast"));
  assert.ok(sceneControllerSrc.includes("module-patch-broadcast"));
  assert.ok(sceneControllerSrc.includes("let payloadRevision = 0;"));
  assert.ok(sceneControllerSrc.includes("payloadRevision += 1;"));
  assert.ok(sceneControllerSrc.includes("revision: payloadRevision"));
  assert.ok(sceneControllerSrc.includes("hasQuickbar: !!lastPayload?.hudSnapshot?.quickbar"));
  assert.ok(sceneControllerSrc.includes("hasWeapon: !!lastPayload?.hudSnapshot?.weapon"));
  assert.ok(sceneControllerSrc.includes("const previousCharacterId = lastResolvedCharacterId"));
  assert.ok(sceneControllerSrc.includes("nextCharacterId"));
});

test("ready selection preserves an already-restored selectedWeaponId instead of always resetting to activeWeaponId", () => {
  assert.ok(sceneControllerSrc.includes('ephemeral.selectedWeaponId = String(ephemeral.selectedWeaponId ?? "").trim() || activeWeaponId;'));
  assert.ok(sceneControllerSrc.includes("if (ephemeral.selectedWeaponId) selectedWeaponMemory.set(nextCharacterId, ephemeral.selectedWeaponId);"));
});

test("opening the weapon selector always re-syncs selectedWeaponId to the currently displayed weapon", () => {
  assert.ok(sceneControllerSrc.includes('const currentlyDisplayedWeaponId = String(lastPayload?.hudSnapshot?.weapon?.primary?.id ?? "").trim() || null;'));
  assert.ok(sceneControllerSrc.includes('if (ephemeral.weaponSelectorOpen && currentlyDisplayedWeaponId) {'));
  assert.ok(sceneControllerSrc.includes("ephemeral.selectedWeaponId = currentlyDisplayedWeaponId;"));
});

test("non-empty observed selection schedules resolve when it differs from current or pending", () => {
  assert.ok(sceneControllerSrc.includes("if (observedSignature !== currentSignature || observedSignature !== pendingSignature)"));
  assert.ok(sceneControllerSrc.includes('stableSelectionResolver?.scheduleSelectionSync({ force: false, reason });'));
  assert.ok(sceneControllerSrc.includes("empty-selection-cancelled"));
});

test("shared resolver owns signature dedupe and latest-wins request id", () => {
  assert.ok(resolverSrc.includes("let selectionRequestId = 0;"));
  assert.ok(resolverSrc.includes("let lastSelectionSignature = \"\";"));
  assert.ok(resolverSrc.includes("const requestId = ++selectionRequestId;"));
  assert.ok(resolverSrc.includes("if (!isCurrentRequest(requestId))"));
  assert.ok(resolverSrc.includes("if (!force && signature === lastSelectionSignature)"));
  assert.ok(resolverSrc.includes('log("selection", "selection-resolve-result"'));
  assert.ok(resolverSrc.includes('log("selection", "selection-resolve-finished"'));
  assert.ok(sceneControllerSrc.includes("stableSelectionResolver.getCurrentRequestId() !== requestId"));
});

await asyncTest("after repeated light runtime failure selection shows runtime fetch failed", async () => {
  const adapter = createAdapter(async () => {
    throw new Error("canceling statement due to statement timeout");
  });

  const state = await adapter.resolve(["token-1"]);
  assert.equal(state.status, SELECTION_STATUS.error);
  assert.equal(state.error.code, "RUNTIME_FETCH_FAILED");
  assert.match(String(state.error.message), /statement timeout/i);
});

if (failed > 0) {
  console.error(`\nSelection Light Runtime: ${failed} failed, ${passed} passed.`);
  process.exitCode = 1;
} else {
  console.log(`\nSelection Light Runtime: all ${passed} passed.`);
}
