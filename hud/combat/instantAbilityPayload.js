// Combat HUD — Instant / Self Ability Execution (Phase 4.1B.1) payload
// adapter (PURE). In combat this goes through public.combat_execute_action
// (so MAIN/MOVE are spent server-side). Out of combat it falls back to
// public.use_ability(jsonb), preserving resource/cooldown costs without
// requiring combat actions.
//
// No target_character_id/target_body_part_id/weapon_id/ammo/magazine/
// fire_mode field is ever built — this ability class has none of those
// concepts; use_ability resolves the target to the acting character itself
// when none is supplied (confirmed server-side). No `context` wrapper is
// sent either: the audited combat_execute_action body never reads a
// `context`/`room_id`/`scene_id`/`token_id` field, so one is not fabricated
// just to match the phase spec's own "conceptual" payload shape.

import { describeError, ERROR_MESSAGES } from "../../screens/resolveAttack/resolveAttackService.js";

export { describeError, ERROR_MESSAGES };

/**
 * @param {{
 *   sourceCharacterId: string,
 *   abilityId: string,
 *   selectedWeaponId?: (string|null),
 *   encounterId?: (string|null),
 *   expectedEncounterVersion?: (number|null),
 *   actorPlayerId?: (string|null),
 *   actorIsGm?: boolean,
 * }} input
 * @returns {object} the exact RPC payload
 */
export function buildInstantAbilityExecutionPayload(input = {}) {
  const encounterId = String(input.encounterId ?? "").trim();
  if (!encounterId) {
    return {
      character_id: String(input.sourceCharacterId ?? "").trim(),
      character_ability_id: String(input.abilityId ?? "").trim(),
      selected_character_weapon_id: String(input.selectedWeaponId ?? "").trim(),
      include_combat_state: false,
    };
  }
  const payload = {
    kind: "ability",
    include_runtime: false,
    character_id: String(input.sourceCharacterId ?? "").trim(),
    encounter_id: encounterId,
    actor_player_id: String(input.actorPlayerId ?? "").trim(),
    actor_is_gm: !!input.actorIsGm,
    intent: {
      character_ability_id: String(input.abilityId ?? "").trim(),
      selected_character_weapon_id: String(input.selectedWeaponId ?? "").trim(),
    },
  };
  // Phase 3E.0 optimistic-concurrency check — only ever set when the caller
  // supplies a real number (active session); never fabricated. Mirrors
  // buildAttackPayload's identical convention.
  if (input.expectedEncounterVersion !== null
      && input.expectedEncounterVersion !== undefined
      && Number.isFinite(Number(input.expectedEncounterVersion))) {
    payload.expected_encounter_version = Number(input.expectedEncounterVersion);
  }
  return payload;
}

/* ----- safe getters for tolerant result rendering ----- */
function asObject(v) {
  return v && typeof v === "object" ? v : {};
}

/**
 * Normalize combat_execute_action's response into a flat, render-friendly
 * summary. Every field may be null — the UI shows a neutral fallback for
 * nulls. Tolerant of a missing/malformed nested `result` (use_ability's own
 * response) — never throws.
 */
export function normalizeInstantAbilityResult(raw) {
  const r = asObject(raw);
  const spent = asObject(r.spent);
  const nestedResult = asObject(r.result);
  const result = nestedResult && Object.keys(nestedResult).length > 0 ? nestedResult : r;
  const ability = asObject(result.ability);
  const resource = asObject(result.resource);
  const resultTimings = asObject(result.timings_ms);
  const rawTimings = asObject(r.timings_ms);
  const timingsMs = Object.keys(resultTimings).length > 0
    ? resultTimings
    : (Object.keys(rawTimings).length > 0 ? rawTimings : null);
  return {
    ok: r.ok !== false,
    actionCost: spent.action_cost ?? null,
    moveCost: spent.move_cost ?? null,
    usedReaction: spent.used_reaction ?? null,
    abilityCode: ability.code ?? null,
    abilityName: ability.name ?? null,
    effectMode: ability.effect_mode ?? null,
    resourceSpent: resource.spent ?? resource.cost ?? resource.amount_spent ?? null,
    resourceRemaining: resource.remaining ?? resource.current_value ?? null,
    narrativeOnly: result.result?.narrative_only === true,
    encounterStateVersion: r.encounter_state_version ?? null,
    characterStateVersion: r.character_state_version ?? result.combat_state?.state_version ?? null,
    timingsMs,
  };
}

/**
 * Run the instant-ability execution RPC. In combat this uses
 * combat_execute_action; out of combat it falls back to use_ability.
 */
export async function resolveInstantAbilityExecution(ctx, deps) {
  const payload = buildInstantAbilityExecutionPayload(ctx);
  const inCombat = String(ctx?.encounterId ?? "").trim().length > 0;

  let raw;
  try {
    raw = inCombat
      ? await deps.executeAction(payload)
      : await deps.useAbility(payload);
  } catch (error) {
    const code = error?.code ?? error?.details?.code ?? error?.details?.error ?? null;
    return {
      ok: false,
      payload,
      raw: error?.details ?? null,
      normalized: null,
      code,
      error: error?.message || "Network or RPC error.",
    };
  }

  if (!raw || raw.ok === false) {
    const code = raw?.code ?? raw?.error ?? null;
    return {
      ok: false,
      payload,
      raw: raw ?? null,
      normalized: raw ? normalizeInstantAbilityResult(raw) : null,
      code,
      error: raw?.message || describeError(code, "The ability could not be executed."),
    };
  }

  return { ok: true, payload, raw, normalized: normalizeInstantAbilityResult(raw), code: null, error: null };
}
