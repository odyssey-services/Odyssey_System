// Combat HUD — pure state transitions (Phase 0).
//
// These functions take the current state (plus inputs) and return a NEW
// state object. They never mutate their arguments and never touch the DOM,
// the adapter, or any I/O. The store composes them; tests exercise them
// directly. Keeping transitions here (rather than as ad-hoc mutations inside
// the store) is what makes "explicit state actions, not generic mutation"
// real.

import {
  HUD_STATUS,
  HUD_SOURCE,
  VIEWER_ROLES,
  EMPTY_REASONS,
  EMPTY_REASON_TEXT,
  cloneDeep,
  createEmptySnapshot,
  createDefaultUiState,
  createDefaultTargeting,
} from "../models/combatHudContracts.js";

/**
 * Build the initial store state.
 * @param {"mock"|"supabase"} source
 * @returns {import("../models/combatHudContracts.js").CombatHudState}
 */
export function createInitialState(source = HUD_SOURCE.mock) {
  return {
    status: HUD_STATUS.idle,
    source,
    viewer: { playerId: "", playerName: "", role: VIEWER_ROLES.player },
    selectedTokenId: null,
    selectedCharacterId: null,
    access: { canViewSelectedCharacter: false, reason: null },
    snapshot: createEmptySnapshot(),
    ui: createDefaultUiState(),
    error: null,
  };
}

/**
 * Resolve whether the viewer may see the selected character.
 * This is the FRONTEND VISIBILITY RULE only — never security (see spec §2.6).
 * @param {import("../models/combatHudContracts.js").Viewer} viewer
 * @param {import("../models/combatHudContracts.js").EntityRuntime|null} entity
 * @returns {{canView:boolean, reason:(string|null)}}
 */
export function computeAccess(viewer, entity) {
  if (!entity) {
    return { canView: false, reason: EMPTY_REASONS.noCharacterLink };
  }
  if (viewer?.role === VIEWER_ROLES.gm) {
    return { canView: true, reason: null };
  }
  const ownerId = entity.summary?.ownerPlayerId ?? null;
  if (ownerId && viewer?.playerId && ownerId === viewer.playerId) {
    return { canView: true, reason: null };
  }
  return { canView: false, reason: EMPTY_REASONS.notOwner };
}

/** Human-readable text for an empty reason code (Phase 0 diagnostics copy). */
export function describeEmptyReason(reasonCode) {
  if (!reasonCode) return "";
  return EMPTY_REASON_TEXT[reasonCode] ?? reasonCode;
}

/**
 * Apply a viewer record (identity + role). Returns new state; does not
 * recompute the snapshot — the store rebuilds afterwards.
 */
export function applyViewer(state, viewer) {
  return {
    ...state,
    viewer: {
      playerId: String(viewer?.playerId ?? ""),
      playerName: String(viewer?.playerName ?? ""),
      role: viewer?.role === VIEWER_ROLES.gm ? VIEWER_ROLES.gm : VIEWER_ROLES.player,
    },
  };
}

/** Set status = loading, clearing any prior error. */
export function applyLoading(state) {
  return { ...state, status: HUD_STATUS.loading, error: null };
}

/**
 * Apply a fully-resolved selection result built by the store from adapter
 * reads. `resolved` carries already-cloned, contract-shaped data.
 *
 * @param {import("../models/combatHudContracts.js").CombatHudState} state
 * @param {{
 *   viewer: import("../models/combatHudContracts.js").Viewer,
 *   selectedTokenId: (string|null),
 *   characterId: (string|null),
 *   entity: (import("../models/combatHudContracts.js").EntityRuntime|null),
 *   snapshot: import("../models/combatHudContracts.js").CombatHudSnapshot,
 * }} resolved
 * @returns {import("../models/combatHudContracts.js").CombatHudState}
 */
export function applySelectionResult(state, resolved) {
  const base = applyViewer(state, resolved.viewer);

  // No token selected at all.
  if (!resolved.selectedTokenId) {
    return {
      ...base,
      status: HUD_STATUS.empty,
      selectedTokenId: null,
      selectedCharacterId: null,
      access: { canViewSelectedCharacter: false, reason: EMPTY_REASONS.noToken },
      snapshot: createEmptySnapshot(),
      error: null,
    };
  }

  // Token selected but not linked to a character.
  if (!resolved.characterId || !resolved.entity) {
    return {
      ...base,
      status: HUD_STATUS.empty,
      selectedTokenId: resolved.selectedTokenId,
      selectedCharacterId: null,
      access: { canViewSelectedCharacter: false, reason: EMPTY_REASONS.noCharacterLink },
      snapshot: createEmptySnapshot(),
      error: null,
    };
  }

  // Linked, but the viewer may not control it.
  const access = computeAccess(resolved.viewer, resolved.entity);
  if (!access.canView) {
    return {
      ...base,
      status: HUD_STATUS.empty,
      selectedTokenId: resolved.selectedTokenId,
      selectedCharacterId: resolved.characterId,
      access: { canViewSelectedCharacter: false, reason: access.reason },
      snapshot: createEmptySnapshot(),
      error: null,
    };
  }

  // Ready.
  return {
    ...base,
    status: HUD_STATUS.ready,
    selectedTokenId: resolved.selectedTokenId,
    selectedCharacterId: resolved.characterId,
    access: { canViewSelectedCharacter: true, reason: null },
    snapshot: resolved.snapshot,
    error: null,
  };
}

/** Apply an error state, preserving the last good snapshot for reconciliation. */
export function applyError(state, message, cause = null) {
  return {
    ...state,
    status: HUD_STATUS.error,
    error: { message: String(message ?? "Unknown error"), cause: cause ? String(cause) : null },
  };
}

/* ----------------- ephemeral UI transitions ----------------- */

/** Collapse / expand the HUD shell (UI-only). */
export function setCollapsed(state, isCollapsed) {
  return { ...state, ui: { ...state.ui, isHudCollapsed: Boolean(isCollapsed) } };
}

/**
 * Reset the action draft: technique/ability/reload/modifier/targeting all
 * return to defaults. Crucially this does NOT touch `snapshot` (runtime data),
 * `status`, `access`, or the collapsed flag.
 */
export function resetActionDraft(state) {
  return {
    ...state,
    ui: {
      ...state.ui,
      selectedTechniqueId: null,
      selectedAbilityId: null,
      selectedReloadMagazineId: null,
      selectedModifierIds: [],
      targeting: createDefaultTargeting(),
      // isHudCollapsed and isBattleLogExpanded are view prefs, intentionally kept.
    },
  };
}

/* ----------------- snapshot assembly ----------------- */

/**
 * Assemble a normalized snapshot from already-fetched adapter pieces. The
 * store passes raw adapter results; this clones them (so the store never
 * mutates adapter-owned objects) and shapes them into CombatHudSnapshot.
 *
 * For restricted views the store should pass `entity:null`; this function is
 * only called for the ready path.
 *
 * @param {{
 *   entity: object,
 *   weapon: ({primary:object|null, secondary:object|null}|null),
 *   skills: {library:object[], quickSlots:object[]},
 *   combatSession: object|null,
 *   modifiers: object[],
 *   battleLog: {entries:object[]},
 *   selectedCharacterId: (string|null),
 * }} pieces
 * @returns {import("../models/combatHudContracts.js").CombatHudSnapshot}
 */
export function assembleSnapshot(pieces) {
  const snapshot = createEmptySnapshot();

  snapshot.entity = cloneDeep(pieces.entity) ?? null;

  if (pieces.weapon) {
    snapshot.weapon = {
      primary: cloneDeep(pieces.weapon.primary) ?? null,
      secondary: cloneDeep(pieces.weapon.secondary) ?? null,
    };
  }

  snapshot.skills = {
    library: cloneDeep(pieces.skills?.library ?? []),
    quickSlots: cloneDeep(pieces.skills?.quickSlots ?? []),
  };

  const session = pieces.combatSession ? cloneDeep(pieces.combatSession) : null;
  if (session) {
    session.isViewerTurn = computeIsViewerTurn(session, pieces.selectedCharacterId);
    snapshot.combatSession = normalizeCombatSession(session);
  }

  // Group modifiers by kind for the modifier block.
  const groups = { passive: [], active: [], narrative: [] };
  for (const mod of cloneDeep(pieces.modifiers ?? [])) {
    const bucket = groups[mod.kind] ? mod.kind : "active";
    groups[bucket].push(mod);
  }
  snapshot.modifiers = groups;

  snapshot.battleLog = { entries: cloneDeep(pieces.battleLog?.entries ?? []) };

  return snapshot;
}

/** Determine if the selected character is the current combat participant. */
export function computeIsViewerTurn(session, selectedCharacterId) {
  if (!session || session.status !== "active") return false;
  if (!selectedCharacterId) return false;
  return session.currentParticipantId === selectedCharacterId;
}

/** Ensure a combat session has all contract fields with safe defaults. */
function normalizeCombatSession(session) {
  return {
    id: session.id ?? null,
    status: session.status ?? "inactive",
    round: Number(session.round ?? 0) || 0,
    currentParticipantId: session.currentParticipantId ?? null,
    participants: Array.isArray(session.participants) ? session.participants : [],
    isViewerTurn: Boolean(session.isViewerTurn),
  };
}
