// Combat HUD selection render (PURE, DOM-free string builder).
//
// Given a broadcast selection payload + a module id, returns the HTML for that
// module iframe.
//
// Routing:
//   ready + hudSnapshot present  -> real block renderer with synthetic state
//   ready + hudSnapshot absent   -> minimal identity / fallback card
//   non-ready player             -> status prompt card
//   non-ready secondary          -> persistent module card with honest status

import { ICON_MARK } from "../components/hudIcons.js";
import { esc } from "../components/hudDom.js";
import { panel } from "../components/HudPanel.js";
import { SELECTION_STATUS, PRIMARY_MODULE_ID, normalizeSelectionPayload } from "./selectionState.js";
import { createInactiveCombatSession } from "../models/combatHudContracts.js";

import { renderPlayerBlock } from "../components/PlayerBlock.js";
import { renderGunBlock } from "../components/GunBlock.js";
import { renderSkillBlock } from "../components/SkillBlock.js";
import { renderCombatControlBlock } from "../components/CombatControlBlock.js";
import { renderBattleLogPanel } from "../components/BattleLogBlock.js";

const LIVE_RENDERERS = {
  player: renderPlayerBlock,
  gun: renderGunBlock,
  skills: renderSkillBlock,
  combatControl: renderCombatControlBlock,
  log: renderBattleLogPanel,
};

const MODULE_LABELS = Object.freeze({
  gun: "Weapon",
  skills: "Skills",
  combatControl: "Combat",
  log: "Combat Log",
});

const PLAYER_PROMPTS = Object.freeze({
  [SELECTION_STATUS.noSelection]: { t: "SELECT YOUR CHARACTER", h: "Choose a controlled token on the map" },
  [SELECTION_STATUS.multipleSelection]: { t: "SELECT ONE CHARACTER", h: "Multiple tokens selected" },
  [SELECTION_STATUS.unlinkedToken]: { t: "NO CHARACTER LINK", h: "This token is not linked to an Odyssey character" },
  [SELECTION_STATUS.notOwned]: { t: "CHARACTER NOT AVAILABLE", h: "Select one of your controlled characters" },
  [SELECTION_STATUS.unavailable]: { t: "CHARACTER DATA UNAVAILABLE", h: "Try selecting the token again" },
  [SELECTION_STATUS.error]: { t: "CHARACTER DATA UNAVAILABLE", h: "Try selecting the token again" },
});

function promptCard(title, hint, devDetail) {
  return `<div class="ohud-state-wrap"><div class="ohud-empty">
    <span class="ohud-empty-mark" aria-hidden="true">${ICON_MARK}</span>
    <div class="ohud-empty-title">${esc(title)}</div>
    <div class="ohud-empty-hint">${esc(hint)}</div>${devDetail || ""}
  </div></div>`;
}

function loadingCard() {
  return `<div class="ohud-state-wrap"><div class="ohud-empty ohud-empty--loading">
    <div class="ohud-empty-title">LOADING…</div>
  </div></div>`;
}

function secondaryPrompt(moduleId, payload) {
  const status = payload?.status ?? SELECTION_STATUS.loading;
  const syncPending = payload?.ui?.combatRuntimePending === true;
  const label = MODULE_LABELS[moduleId] ?? moduleId;
  const titleByStatus = {
    [SELECTION_STATUS.loading]: "Loading…",
    [SELECTION_STATUS.noSelection]: "Select a character",
    [SELECTION_STATUS.multipleSelection]: "Select one token",
    [SELECTION_STATUS.unlinkedToken]: "No character link",
    [SELECTION_STATUS.notOwned]: "Character not available",
    [SELECTION_STATUS.unavailable]: "Character data unavailable",
    [SELECTION_STATUS.error]: "Character data unavailable",
  };
  const hintByStatus = {
    [SELECTION_STATUS.loading]: syncPending ? "Synchronizing combat data…" : "Waiting for character data.",
    [SELECTION_STATUS.noSelection]: "Choose a controlled token on the map.",
    [SELECTION_STATUS.multipleSelection]: "Reduce the selection to one token.",
    [SELECTION_STATUS.unlinkedToken]: "Link this token to an Odyssey character first.",
    [SELECTION_STATUS.notOwned]: "Select a character you can control.",
    [SELECTION_STATUS.unavailable]: "Try selecting the token again.",
    [SELECTION_STATUS.error]: payload?.error?.message || "Try selecting the token again.",
  };
  return panel({
    key: moduleId,
    label,
    bodyHtml: `<div class="ohud-state-wrap"><div class="ohud-empty${status === SELECTION_STATUS.loading ? " ohud-empty--loading" : ""}">
      <div class="ohud-empty-title">${esc(titleByStatus[status] ?? "Waiting for character")}</div>
      <div class="ohud-empty-hint">${esc(hintByStatus[status] ?? "Waiting for character data.")}</div>
    </div></div>`,
  });
}

function readyPlayerCard(view) {
  const v = view || {};
  const badge = v.gmView
    ? `<span class="ohud-bind-badge ohud-bind-badge--gm">GM VIEW</span>`
    : `<span class="ohud-bind-badge ohud-bind-badge--owned">CONTROLLED</span>`;
  const fallbackStatus = `${v.isAlive === false ? "Down" : "Alive"} · ${v.isConscious === false ? "Unconscious" : "Conscious"}`;
  const statusLine = v.statusSummary ? esc(v.statusSummary) : esc(fallbackStatus);
  const owner = v.ownerName ? `<div class="ohud-bind-owner">Owner: ${esc(v.ownerName)}</div>` : "";
  return `<div class="ohud-bind">
    ${badge}
    <div class="ohud-bind-name" title="${esc(v.name || "")}">${esc(v.name || "Unnamed character")}</div>
    <div class="ohud-bind-status">${statusLine}</div>
    ${owner}
  </div>`;
}

function readyFallbackCard(moduleId) {
  const label = MODULE_LABELS[moduleId] ?? moduleId;
  return `<section class="ohud-panel" data-block="${esc(moduleId)}">
    <div class="ohud-bind-fallback">
      <div class="ohud-bind-fallback-label">${esc(label)}</div>
      <div class="ohud-bind-fallback-hint">Data loading…</div>
    </div>
  </section>`;
}

function debugReason(payload, opts) {
  if (!opts?.dev || !payload?.debug?.reason) return "";
  return `<div class="ohud-bind-dev">HUD DEBUG: ${esc(payload.debug.reason)}</div>`;
}

function buildSyntheticState(payload) {
  const snap = payload.hudSnapshot;
  const role = String(payload.viewer?.role ?? "UNKNOWN").toLowerCase();
  const prepared = payload.ui?.preparedAction ?? null;
  const selectedAbilityId = prepared?.kind === "skill" ? prepared.id : null;
  const targeting = payload.ui?.targeting ?? {};

  return {
    status: "ready",
    source: "supabase",
    viewer: {
      playerId: payload.viewer?.playerId ?? null,
      playerName: null,
      role: role === "gm" ? "gm" : "player",
    },
    selectedTokenId: payload.selectedItemId ?? null,
    selectedCharacterId: payload.characterId ?? null,
    access: { canViewSelectedCharacter: true, reason: null },
    snapshot: snap ?? {
      entity: null,
      weapon: { primary: null, secondary: null },
      skills: { library: [], quickSlots: [] },
      combatSession: createInactiveCombatSession(),
      modifiers: { passive: [], active: [], narrative: [] },
      battleLog: { entries: [] },
    },
    ui: {
      isHudCollapsed: false,
      selectedTechniqueId: null,
      selectedAbilityId,
      selectedReloadMagazineId: payload.ui?.selectedReloadMagazineId ?? null,
      selectedModifierIds: [],
      weaponSelectorOpen: !!payload.ui?.weaponSelectorOpen,
      fireModeSelectorOpen: !!payload.ui?.fireModeSelectorOpen,
      combatRuntimePending: !!payload.ui?.combatRuntimePending,
      activeIntent: payload.ui?.activeIntent ?? { kind: "weapon-attack", weaponId: null },
      basicAttack: payload.ui?.basicAttack ?? { inFlight: false, uiAllowed: false, uiBlockReason: "No character loaded." },
      targeting: {
        mode: targeting.mode ?? "none",
        selectedTargetIds: Array.isArray(targeting.selectedTargetIds) ? targeting.selectedTargetIds : [],
        selectedTargetName: targeting.selectedTargetName ?? null,
        selectedBodyPartId: targeting.selectedBodyPartId ?? "torso",
        distance: Number.isFinite(Number(targeting.distance)) ? Number(targeting.distance) : null,
        zonesMap: targeting.zonesMap && typeof targeting.zonesMap === "object" ? targeting.zonesMap : {},
        error: targeting.error ?? null,
        selectedPoint: null,
        radius: null,
      },
      isBattleLogExpanded: false,
    },
    error: null,
  };
}

export function renderSelectionModule(moduleId, payload, opts = {}) {
  const status = payload?.status;
  const isReady = status === SELECTION_STATUS.ready && payload?.access?.canView;

  if (moduleId === PRIMARY_MODULE_ID) {
    if (isReady) {
      if (payload.hudSnapshot) {
        const syntheticState = buildSyntheticState(payload);
        return `${renderPlayerBlock(syntheticState)}${debugReason(payload, opts)}`;
      }
      if (payload.view) return `${readyPlayerCard(payload.view)}${debugReason(payload, opts)}`;
    }
    if (status === SELECTION_STATUS.loading || !status) return loadingCard();
    const p = PLAYER_PROMPTS[status] || PLAYER_PROMPTS[SELECTION_STATUS.noSelection];
    const devDetail = opts.dev && payload?.error?.message
      ? `<div class="ohud-bind-dev">${esc(payload.error.code || "")}: ${esc(payload.error.message)}</div>`
      : "";
    return promptCard(p.t, p.h, devDetail);
  }

  if (isReady) {
    if (payload.hudSnapshot) {
      const fn = LIVE_RENDERERS[moduleId];
      if (fn) {
        const syntheticState = buildSyntheticState(payload);
        if (moduleId === "skills") {
          return fn(syntheticState, opts?.skillsUiState ?? {});
        }
        return fn(syntheticState);
      }
    }
    return readyFallbackCard(moduleId);
  }

  return secondaryPrompt(moduleId, payload);
}

export function buildCompanionSelectorState(rawPayload) {
  const payload = normalizeSelectionPayload(rawPayload);
  if (!payload) return null;
  const isReady = payload.status === SELECTION_STATUS.ready && payload.access?.canView;
  if (!isReady || !payload.hudSnapshot) return null;
  return buildSyntheticState(payload);
}
