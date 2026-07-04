// Combat HUD — real combat-result log normalizer (PURE).
//
// This is a LOCAL, runtime-only log for the current HUD session — no Supabase
// persistence, no shared/realtime distribution (that's a future, separate
// "shared Battle Log" phase). It only ever records what the SERVER actually
// returned; it never recomputes or invents a roll/damage/hit value.
//
// Every builder returns the same compact, safe shape:
//   { timestamp, type, outcome, title, details, sourceCharacterId, targetCharacterId }
// `details` is a plain array of short strings — never private target data
// (inventory/skills/PSI/hidden statuses).
//
// Attack entries source their numbers from hud/combat/attackResolutionTrace.js
// — the SAME shared normalization the Debug Console's roll-resolution event
// uses, so the game log and the debug trace can never disagree about one
// server result.

import { buildAttackResolutionTrace, buildCombatLogLines } from "../combat/attackResolutionTrace.js";

export const LOG_TYPE = Object.freeze({
  attack: "attack",
  reload: "reload",
  fireMode: "fire-mode",
});

export const LOG_OUTCOME = Object.freeze({
  success: "success",
  failure: "failure",
});

/** Cap for the in-memory log list — oldest entries fall off past this. */
export const COMBAT_LOG_MAX_ENTRIES = 100;

/**
 * Push `entry` onto `list` (newest first) and cap at COMBAT_LOG_MAX_ENTRIES.
 * Pure — returns a NEW array, never mutates `list`.
 */
export function appendCombatLogEntry(list, entry) {
  const next = [entry, ...(Array.isArray(list) ? list : [])];
  return next.length > COMBAT_LOG_MAX_ENTRIES ? next.slice(0, COMBAT_LOG_MAX_ENTRIES) : next;
}

/**
 * Build a Basic Weapon Attack log entry from the resolveAttackService-shaped
 * outcome (`{ ok, normalized, error, code }`) — never fabricates a roll/damage
 * field the server didn't actually return.
 *
 * @param {{
 *   sourceCharacterId:(string|null), targetCharacterId:(string|null),
 *   bodyZoneLabel:(string|null), outcome:{ok:boolean, normalized:object|null, error:(string|null)},
 * }} input
 */
export function buildAttackLogEntry({ sourceCharacterId, targetCharacterId, bodyZoneLabel, outcome }) {
  const ok = !!outcome?.ok;
  const details = ok
    ? buildCombatLogLines(buildAttackResolutionTrace(outcome), bodyZoneLabel)
    : [String(outcome?.error || "Attack denied.")];
  return {
    timestamp: Date.now(),
    type: LOG_TYPE.attack,
    outcome: ok ? LOG_OUTCOME.success : LOG_OUTCOME.failure,
    title: ok ? "Attack" : "Attack failed",
    details,
    sourceCharacterId: sourceCharacterId ?? null,
    targetCharacterId: targetCharacterId ?? null,
  };
}

/**
 * @param {{ sourceCharacterId:(string|null), ok:boolean, message:(string|null) }} input
 */
export function buildReloadLogEntry({ sourceCharacterId, ok, message }) {
  return {
    timestamp: Date.now(),
    type: LOG_TYPE.reload,
    outcome: ok ? LOG_OUTCOME.success : LOG_OUTCOME.failure,
    title: ok ? "Reload" : "Reload failed",
    details: [String(message || (ok ? "Reloaded." : "Reload denied."))],
    sourceCharacterId: sourceCharacterId ?? null,
    targetCharacterId: null,
  };
}

/**
 * @param {{ sourceCharacterId:(string|null), ok:boolean, message:(string|null) }} input
 */
export function buildFireModeLogEntry({ sourceCharacterId, ok, message }) {
  return {
    timestamp: Date.now(),
    type: LOG_TYPE.fireMode,
    outcome: ok ? LOG_OUTCOME.success : LOG_OUTCOME.failure,
    title: ok ? "Fire mode changed" : "Fire mode change failed",
    details: [String(message || (ok ? "Fire mode changed." : "Fire mode change denied."))],
    sourceCharacterId: sourceCharacterId ?? null,
    targetCharacterId: null,
  };
}
