// Combat HUD — Directed Target Ability Execution (Phase 4.1B.2) payload
// adapter (PURE). In combat this stays on public.combat_execute_action.
// Out of combat it falls back to public.use_ability(jsonb), so the same
// ability can be used without spending MAIN/MOVE.
//
// No target_body_part_id/weapon_id/ammo/magazine/fire_mode field is ever
// built — this ability class needs a target CHARACTER only, never a body
// zone/part, and has no weapon concept at all.

import { describeError, ERROR_MESSAGES } from "../../screens/resolveAttack/resolveAttackService.js";

export { describeError, ERROR_MESSAGES };

/**
 * @param {{
 *   sourceCharacterId: string,
 *   abilityId: string,
 *   selectedWeaponId?: (string|null),
 *   targetCharacterId: string,
 *   encounterId?: (string|null),
 *   expectedEncounterVersion?: (number|null),
 *   actorPlayerId?: (string|null),
 *   actorIsGm?: boolean,
 * }} input
 * @returns {object} the exact RPC payload
 */
export function buildDirectedAbilityExecutionPayload(input = {}) {
  const encounterId = String(input.encounterId ?? "").trim();
  if (!encounterId) {
    return {
      character_id: String(input.sourceCharacterId ?? "").trim(),
      character_ability_id: String(input.abilityId ?? "").trim(),
      selected_character_weapon_id: String(input.selectedWeaponId ?? "").trim(),
      target_character_id: String(input.targetCharacterId ?? "").trim(),
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
      target_character_id: String(input.targetCharacterId ?? "").trim(),
    },
  };
  // Phase 3E.0 optimistic-concurrency check — only ever set when the caller
  // supplies a real number (active session); never fabricated.
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
 * summary — same shape as instantAbilityPayload's normalizeInstantAbilityResult,
 * plus the resolved targetCharacterId. Never throws.
 */
export function normalizeDirectedAbilityResult(raw) {
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
    targetCharacterId: result.target_character_id ?? null,
    resourceSpent: resource.spent ?? resource.cost ?? resource.amount_spent ?? null,
    resourceRemaining: resource.remaining ?? resource.current_value ?? null,
    narrativeOnly: result.result?.narrative_only === true,
    encounterStateVersion: r.encounter_state_version ?? null,
    characterStateVersion: r.character_state_version ?? result.combat_state?.state_version ?? null,
    timingsMs,
  };
}

/**
 * Run the directed-ability execution RPC. In combat this uses
 * combat_execute_action; out of combat it falls back to use_ability.
 */
export async function resolveDirectedAbilityExecution(ctx, deps) {
  const payload = buildDirectedAbilityExecutionPayload(ctx);
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
      normalized: raw ? normalizeDirectedAbilityResult(raw) : null,
      code,
      error: raw?.message || describeError(code, "The ability could not be executed."),
    };
  }

  return { ok: true, payload, raw, normalized: normalizeDirectedAbilityResult(raw), code: null, error: null };
}
