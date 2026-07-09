// Odyssey — migration 109 regression tests (weapon switch / overlay refresh /
// combat-context ambiguity / WEAPON_NOT_ACTIVE / modifier merge).
//
// No live Postgres is available in this environment, so — matching the
// existing "SQL:" test convention in scripts/abilities-quickbar.test.mjs —
// these assert directly against the migration's own SQL source text for the
// specific invariants the ticket requires. Frontend-reachable pieces (the
// abilityRuntimeMapper.js passthrough) are covered by real unit tests in
// scripts/abilities-quickbar.test.mjs instead.

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const sql109 = fs.readFileSync(path.join(repoRoot, "supabase", "109_weapon_switch_refresh_and_combat_context_fixes.sql"), "utf8");

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  PASS ${name}`);
  } catch (err) {
    failed += 1;
    failures.push({ name, err });
    console.error(`  FAIL ${name}\n      ${err.message}`);
  }
}

console.log("\nOdyssey — Weapon Switch / Combat Context (migration 109)\n");

test("SQL: get_character_armory takes an optional p_encounter_id (old 1-arg overload dropped first, so PostgREST never sees an ambiguous pair)", () => {
  assert.ok(/drop function if exists public\.get_character_armory\(uuid\);/.test(sql109));
  assert.ok(/create or replace function public\.get_character_armory\(\s*p_character_id uuid,\s*p_encounter_id uuid default null\s*\)/.test(sql109));
  assert.ok(/grant execute on function public\.get_character_armory\(uuid, uuid\)/.test(sql109));
});

test("SQL: get_character_armory never silently picks the newest active encounter when more than one exists and no encounter_id was given — it reports combat_context.mode = 'ambiguous' and stays out of switch/reload gating", () => {
  const fn = sql109.slice(
    sql109.indexOf("create or replace function public.get_character_armory("),
    sql109.indexOf("grant execute on function public.get_character_armory"),
  );
  assert.ok(fn.includes("v_active_encounter_count"), "counts active encounters before picking one");
  assert.ok(/elsif v_active_encounter_count > 1 then/.test(fn));
  assert.ok(fn.includes("'mode', 'ambiguous'"));
  assert.ok(fn.includes("Multiple active encounters found for this character. Pass encounter_id explicitly."));
  // The ambiguous branch never falls through to the "order by e.created_at
  // desc ... limit 1" query below it (that query is now reached only via the
  // final `else` branch, i.e. exactly one active encounter).
  const ambiguousBranch = fn.slice(fn.indexOf("elsif v_active_encounter_count > 1 then"), fn.indexOf("else"));
  assert.ok(!/order by e\.created_at desc/.test(ambiguousBranch), "ambiguous branch must not also run the newest-encounter query");
});

test("SQL: an explicit p_encounter_id is honored outright — it is the ONLY thing switch/reload gating is based on when present", () => {
  const fn = sql109.slice(
    sql109.indexOf("create or replace function public.get_character_armory("),
    sql109.indexOf("grant execute on function public.get_character_armory"),
  );
  const explicitBranch = fn.slice(fn.indexOf("if p_encounter_id is not null then"), fn.indexOf("elsif v_active_encounter_count > 1"));
  assert.ok(explicitBranch.includes("and e.id = p_encounter_id"));
});

test("SQL: switch_active_weapon reads encounter_id from the payload and threads it through the cost function and the returned armory", () => {
  const fn = sql109.slice(
    sql109.indexOf("create or replace function public.switch_active_weapon("),
    sql109.indexOf("grant execute on function public.switch_active_weapon"),
  );
  assert.ok(/v_encounter_id uuid := public\.odyssey_try_parse_uuid\(p_payload->>'encounter_id'\)/.test(fn));
  assert.ok(/odyssey_apply_weapon_operation_session_cost\(\s*v_character_id,\s*'switch_weapon',\s*null,\s*v_expected_session_version,\s*v_encounter_id\s*\)/.test(fn));
  // Both the "already active" early-return AND the real switch path return
  // get_character_armory keyed to the SAME encounter context — the charged
  // encounter and the displayed encounter must never disagree.
  const armoryCalls = fn.match(/get_character_armory\(v_character_id, v_encounter_id\)/g) ?? [];
  assert.equal(armoryCalls.length, 2, "both the no-op and real switch paths pass the same v_encounter_id to get_character_armory");
});

test("SQL: odyssey_apply_weapon_operation_session_cost treats an ambiguous participation as free/neutral rather than guessing which encounter to charge", () => {
  const fn = sql109.slice(
    sql109.indexOf("create or replace function public.odyssey_apply_weapon_operation_session_cost("),
    sql109.indexOf("grant execute on function public.odyssey_apply_weapon_operation_session_cost"),
  );
  assert.ok(fn.includes("v_participation->>'is_ambiguous'"));
  const ambiguousBlock = fn.slice(fn.indexOf("if coalesce((v_participation->>'is_ambiguous')"), fn.indexOf("if p_expected_session_version"));
  assert.ok(ambiguousBlock.includes("'spent', false"), "ambiguous participation never spends Move");
  assert.ok(ambiguousBlock.includes("'mode', 'ambiguous'"));
});

test("SQL: odyssey_get_active_participation exposes active_encounter_count/is_ambiguous additively — existing single-arg callers (perform_attack etc.) are unaffected", () => {
  assert.ok(/drop function if exists public\.odyssey_get_active_participation\(uuid\);/.test(sql109));
  assert.ok(/p_encounter_id uuid default null/.test(sql109));
  assert.ok(sql109.includes("'is_ambiguous', (p_encounter_id is null and v_active_count > 1)"));
});

test("SQL: perform_attack rejects a weapon-attack payload whose character_weapon_id is not the character's active weapon, before the weapon-lock check, without touching odyssey_perform_ability_attack's separate dispatch", () => {
  const doBlock = sql109.slice(sql109.indexOf("proname = 'perform_attack'") - 200, sql109.indexOf("-- 4. odyssey_merge_weapon_feature_data"));
  assert.ok(doBlock.includes("WEAPON_NOT_ACTIVE"));
  assert.ok(doBlock.includes("odyssey_get_character_active_weapon_id(v_attacker_character_id)"));
  // Idempotent hot-patch: skip if already applied.
  assert.ok(/position\('WEAPON_NOT_ACTIVE' in v_function_def\) > 0 then/.test(doBlock));
  assert.ok(/return;/.test(doBlock));
});

test("SQL: odyssey_get_character_quick_actions_runtime exposes combatCost/combatResourceState and folds insufficient ACTION into available/disabledReason only when in an unambiguous active encounter", () => {
  const fn = sql109.slice(
    sql109.indexOf("create or replace function public.odyssey_get_character_quick_actions_runtime("),
    sql109.indexOf("comment on function public.odyssey_get_character_quick_actions_runtime"),
  );
  assert.ok(fn.includes("'combatCost', jsonb_build_object("));
  assert.ok(fn.includes("'combatResourceState', jsonb_build_object("));
  assert.ok(fn.includes("v_in_combat := v_participation is not null and not coalesce((v_participation->>'is_ambiguous')"));
  assert.ok(fn.includes("'No ACTION available'"));
  // Signature is unchanged (additive only) — no drop/grant-signature-change needed here.
  assert.ok(!/drop function if exists public\.odyssey_get_character_quick_actions_runtime/.test(sql109));
});

test("SQL: odyssey_merge_weapon_feature_data — an override's own modifiers/on_hit REPLACE the base definition's instead of concatenating (root cause of Plasma Edge's +40/+40 bug)", () => {
  const fn = sql109.slice(
    sql109.indexOf("create or replace function public.odyssey_merge_weapon_feature_data("),
    sql109.indexOf("grant execute on function public.odyssey_merge_weapon_feature_data"),
  );
  // The old concatenation branch ("both present -> base || override") must be gone.
  assert.ok(!/\(base_data->'modifiers'\) \|\| \(override_data->'modifiers'\)/.test(fn), "must never concatenate base+override modifiers");
  assert.ok(!/\(base_data->'on_hit'\) \|\| \(override_data->'on_hit'\)/.test(fn), "must never concatenate base+override on_hit");
  // Override wins outright when present.
  assert.ok(/when jsonb_typeof\(override_data->'modifiers'\) = 'array'\s*\n\s*then override_data->'modifiers'/.test(fn));
});

test("SQL: a data-hygiene pass clears any EXISTING weapon_model_features.modifiers that exactly duplicate the linked feature_def's own modifiers (provable accidental copy, never touches a genuine override)", () => {
  assert.ok(sql109.includes("update public.odyssey_weapon_model_features link"));
  assert.ok(sql109.includes("jsonb_typeof(link.data->'modifiers') = 'array'"));
  assert.ok(sql109.includes("jsonb_typeof(def.data->'modifiers') = 'array'"));
});

setTimeout(() => {
  console.log(`\nWeapon Switch / Combat Context: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`FAILED: ${name}`);
      console.error(err?.stack ?? err);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 50);
