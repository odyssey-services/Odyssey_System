// Combat HUD — pure layout/presentation model helpers (Phase 2).
//
// Tiny, framework-free, DOM-free functions that turn store state + the
// responsive layout mode into render-ready decisions. Kept separate from the
// DOM components so they can be unit-tested under plain Node, and separate from
// the Phase 0 store so no business logic is duplicated in the renderer.

import { HUD_STATUS, ZONE_STATES, EMPTY_REASONS } from "../models/combatHudContracts.js";
import { isTwoRowMode } from "../overlay/overlayConstants.js";

/**
 * How the Battle Log should present at a given layout mode + expand flag.
 *  - wide   → full compact card (optionally expanded to taller list)
 *  - medium → collapsible: a button unless the user expanded it
 *  - compact/mini → button only (tap to expand into an overlay panel)
 * @param {"wide"|"medium"|"compact"|"mini"} mode
 * @param {boolean} expanded  local user toggle
 * @returns {"card"|"expanded"|"button"}
 */
export function resolveBattleLogMode(mode, expanded) {
  if (mode === "wide") return expanded ? "expanded" : "card";
  if (mode === "medium") return expanded ? "expanded" : "button";
  // compact / mini
  return expanded ? "expanded" : "button";
}

/** Whether the Battle Log is rendered as its own standing column (vs floating). */
export function battleLogIsColumn(mode) {
  return mode === "wide";
}

/** Whether the dev controls strip can be shown inline (hidden when cramped). */
export function devStripFitsInline(mode) {
  return !isTwoRowMode(mode);
}

/**
 * Build the EmptyHudState model from store state. Centralises the copy so the
 * component is purely presentational.
 * @returns {{title:string, hint:string}}
 */
export function buildEmptyStateModel(state) {
  const reason = state?.access?.reason ?? null;
  switch (reason) {
    case EMPTY_REASONS.notOwner:
      return {
        title: "SELECT YOUR CHARACTER",
        hint: "You do not control this token. Choose a controlled token on the map.",
      };
    case EMPTY_REASONS.noCharacterLink:
      return {
        title: "NO CHARACTER LINKED",
        hint: "This token is not linked to a character sheet.",
      };
    case EMPTY_REASONS.noToken:
    default:
      return {
        title: "SELECT YOUR CHARACTER",
        hint: "Choose a controlled token on the map.",
      };
  }
}

/**
 * Coarse render model for the whole HUD body, derived from status.
 * @returns {"ready"|"empty"|"error"|"loading"}
 */
export function resolveBodyMode(state) {
  switch (state?.status) {
    case HUD_STATUS.ready: return "ready";
    case HUD_STATUS.empty: return "empty";
    case HUD_STATUS.error: return "error";
    default: return "loading";
  }
}

/** Map a semantic zone state → the CSS modifier suffix used in the stylesheet.
 *  An unrecognized/missing state maps to "unknown" — it must NEVER silently
 *  render as "healthy" (that was the Phase 3D.1 bug: a target whose combat
 *  data hadn't arrived yet, or was denied by RLS, looked perfectly healthy). */
export function zoneStateClass(stateName) {
  switch (stateName) {
    case ZONE_STATES.healthy: return "healthy";
    case ZONE_STATES.wounded: return "wounded";
    case ZONE_STATES.serious: return "serious";
    case ZONE_STATES.critical: return "critical";
    case ZONE_STATES.disabled: return "disabled";
    default: return "unknown";
  }
}

/** Map a skill's semantic colour role → the CSS accent suffix. */
export function accentClass(colorSemantic) {
  switch (colorSemantic) {
    case "attack": return "attack";
    case "psionic": return "psionic";
    case "implant": return "implant";
    case "intervention": return "intervention";
    case "positive": return "positive";
    case "negative": return "negative";
    case "neutral":
    default: return "neutral";
  }
}
