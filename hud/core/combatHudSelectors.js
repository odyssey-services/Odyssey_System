// Combat HUD — selectors (Phase 0).
//
// Small, pure read helpers over the store state. They contain NO DOM and NO
// CSS — they only derive view-ready values future components will need.
// Keeping derivation here (not inside components) keeps the rendering layer
// thin and makes the logic testable.

import {
  HUD_STATUS,
  TOKEN_KINDS,
  DEFAULT_BODY_PART_ID,
} from "../models/combatHudContracts.js";

const COMPACT_LOG_LIMIT = 5;

/**
 * High-level HUD mode for the shell. Collapse wins over everything so a
 * collapsed HUD always renders the reopen pill.
 * @returns {"collapsed"|"idle"|"loading"|"ready"|"empty"|"error"}
 */
export function selectHudMode(state) {
  if (state?.ui?.isHudCollapsed) return "collapsed";
  return state?.status ?? HUD_STATUS.idle;
}

/** The primary displayed entity (mech while piloting, else the character). */
export function selectCurrentEntity(state) {
  return state?.snapshot?.entity ?? null;
}

/**
 * The character the viewer actually controls (player-owned & accessible),
 * or null. Distinct from selectCurrentEntity, which also returns NPCs the GM
 * is inspecting.
 */
export function selectControlledCharacter(state) {
  if (state?.status !== HUD_STATUS.ready) return null;
  if (!state?.access?.canViewSelectedCharacter) return null;
  const entity = state?.snapshot?.entity ?? null;
  if (!entity) return null;
  // GM inspecting an NPC is "ready" but not "controlled" by a player.
  const type = entity.summary?.characterType;
  if (state.viewer?.role === "player") return entity;
  if (type === TOKEN_KINDS.player || type === TOKEN_KINDS.mech) return entity;
  return null;
}

/** The active combat session record (always present; inactive when no combat). */
export function selectCombatSession(state) {
  return state?.snapshot?.combatSession ?? null;
}

/** Is it the viewer's turn right now? */
export function selectIsViewerTurn(state) {
  return Boolean(state?.snapshot?.combatSession?.isViewerTurn);
}

/**
 * Can the controlled character act at all right now? Combines turn ownership,
 * consciousness, and having at least one action economy point available.
 */
export function selectCanAct(state) {
  const entity = selectCurrentEntity(state);
  if (!entity) return false;
  if (!entity.flags?.conscious || !entity.flags?.alive) return false;
  const session = selectCombatSession(state);
  // Outside active combat we still allow acting (free-play / prep).
  if (session && session.status === "active" && !session.isViewerTurn) return false;
  return Boolean(entity.actions?.main || entity.actions?.move);
}

/** The currently drafted skill (technique takes priority over ability). */
export function selectSelectedSkill(state) {
  const id = state?.ui?.selectedTechniqueId ?? state?.ui?.selectedAbilityId ?? null;
  if (!id) return null;
  const library = state?.snapshot?.skills?.library ?? [];
  return library.find((s) => s.id === id) ?? null;
}

/** The action cost of the current draft action (defaults to MAIN for a basic attack). */
export function selectCurrentActionCost(state) {
  const skill = selectSelectedSkill(state);
  if (skill) return skill.actionCost;
  // No skill selected → a basic weapon attack costs MAIN.
  return "MAIN";
}

/**
 * First human-relevant reason the main action is disabled, or null when it is
 * enabled. Order mirrors the spec's "explain the first relevant failure".
 * @returns {string|null}
 */
export function selectDisabledReason(state) {
  if (state?.status !== HUD_STATUS.ready) return "No character loaded.";
  const entity = selectCurrentEntity(state);
  if (!entity) return "No character loaded.";
  if (!entity.flags?.alive) return "Character is dead.";
  if (!entity.flags?.conscious) return "Character is unconscious.";

  const session = selectCombatSession(state);
  if (session && session.status === "active" && !session.isViewerTurn) {
    return "Not your turn.";
  }

  const skill = selectSelectedSkill(state);
  if (skill?.disabledReason) return skill.disabledReason;

  const cost = selectCurrentActionCost(state);
  if (cost === "MAIN" && !entity.actions?.main) return "MAIN action already spent.";
  if (cost === "MOVE" && !entity.actions?.move) return "MOVE action already spent.";

  // Targeting requirement for token/point actions.
  if (skill && skill.targeting !== "none") {
    const targeting = state?.ui?.targeting ?? {};
    if (skill.usesPoint && !targeting.selectedPoint) return "Pick a target point.";
    if (!skill.usesPoint && (targeting.selectedTargetIds?.length ?? 0) === 0) {
      return "Pick a target on the map.";
    }
  }

  return null;
}

/**
 * Reserve magazines that should be offered for reload: compatible caliber,
 * non-empty, and NOT the currently inserted magazine.
 * @returns {import("../models/combatHudContracts.js").Magazine[]}
 */
export function selectVisibleReserveMagazines(state) {
  const weapon = state?.snapshot?.weapon?.primary ?? null;
  if (!weapon || !weapon.usesMagazine) return [];
  const loaded = weapon.loadedMagazine ?? null;
  const loadedId = loaded?.id ?? null;
  const loadedCaliber = loaded?.caliber ?? null;
  const reserve = Array.isArray(weapon.reserveMagazines) ? weapon.reserveMagazines : [];
  return reserve.filter((mag) => {
    if (!mag) return false;
    if (mag.id === loadedId) return false;          // exclude inserted
    if ((mag.current ?? 0) <= 0) return false;       // exclude empty
    if (loadedCaliber && mag.caliber !== loadedCaliber) return false; // incompatible
    return true;
  });
}

/** The selected spare magazine (reload candidate), or null. */
export function selectSelectedReloadMagazine(state) {
  const id = state?.ui?.selectedReloadMagazineId
    ?? state?.snapshot?.weapon?.primary?.reloadCandidateId
    ?? null;
  if (!id) return null;
  return selectVisibleReserveMagazines(state).find((m) => m.id === id) ?? null;
}

/** Compact battle log: at most the five most recent entries (newest last). */
export function selectCompactBattleLog(state) {
  const entries = state?.snapshot?.battleLog?.entries ?? [];
  if (entries.length <= COMPACT_LOG_LIMIT) return entries.slice();
  return entries.slice(entries.length - COMPACT_LOG_LIMIT);
}

/** Full battle log (ordered as provided). */
export function selectFullBattleLog(state) {
  return (state?.snapshot?.battleLog?.entries ?? []).slice();
}

/** Quick-slot layout for the skill bar. */
export function selectQuickSlots(state) {
  return state?.snapshot?.skills?.quickSlots ?? [];
}

/** Resolve a quick slot's skill object (or null for empty/unknown). */
export function selectSkillById(state, skillId) {
  if (!skillId) return null;
  const library = state?.snapshot?.skills?.library ?? [];
  return library.find((s) => s.id === skillId) ?? null;
}

/** Modifiers grouped passive/active/narrative. */
export function selectModifierGroups(state) {
  return state?.snapshot?.modifiers ?? { passive: [], active: [], narrative: [] };
}

/** The currently selected target body part (defaults to torso). */
export function selectSelectedBodyPart(state) {
  return state?.ui?.targeting?.selectedBodyPartId ?? DEFAULT_BODY_PART_ID;
}

/** Human-readable empty reason code (or null when not empty). */
export function selectEmptyReason(state) {
  if (state?.status !== HUD_STATUS.empty) return null;
  return state?.access?.reason ?? null;
}
