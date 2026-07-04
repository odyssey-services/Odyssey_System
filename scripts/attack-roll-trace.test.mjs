// Odyssey Debug Console — authoritative attack roll-resolution trace tests.
//
// Verifies hud/combat/attackResolutionTrace.js (the SINGLE normalization
// point shared by the Debug Console's roll-resolution event and the Combat
// Log's compact attack line) against a realistic perform_attack response
// shape (see supabase/17_combat_resolution_schema.sql + migration 44's
// damage-object extension).

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  NOT_RETURNED,
  buildAttackResolutionTrace,
  buildCombatLogLines,
  buildRollResolutionDetails,
  isReturnedNumber,
} from "../hud/combat/attackResolutionTrace.js";
import { buildAttackLogEntry } from "../hud/log/combatResultLogPolicy.js";
import { normalizeResult } from "../screens/resolveAttack/resolveAttackService.js";
import { detailLines, buildEntryCopyText } from "../hud/debug/DebugConsolePanel.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");

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

console.log("\nAttack roll-resolution trace\n");

/** A realistic FULL perform_attack success response (weapon/ranged path). */
function fullRawResult() {
  return {
    ok: true,
    attack_type: "ranged",
    hit: true,
    attacker_character_id: "11111111-2222-3333-4444-555555555555",
    target_character_id: "66666666-7777-8888-9999-000000000000",
    weapon: { id: "wpn-1", model_id: "mdl-1", name: "Marauder Rifle", base_accuracy_bonus: 4, base_melee_damage: 0 },
    fire_mode: { id: "fm-1", code: "semi", accuracy_modifier: 5 },
    ammo: { caliber: "7.62", ammo_type: "standard", bullet_damage: 8, damage_modifier: 0, accuracy_modifier: 2, armor_pierce: 3 },
    range: { distance_m: 12, band: "effective", modifier: -5 },
    attack: { roll: 47, skill_level: 20, skill_bonus: 20, manual_bonus: 10, manual_penalty: 0, total: 81 },
    defense: { roll: 39, skill_level: 10, effective_skill_level: 10, skill_source: "dodge", hostile_adjacent_count: 1, manual_bonus: 10, manual_penalty: 0, total: 49 },
    damage: {
      damage_attack_total: 89, damage_defense_total: 55, diff: 34, level: "serious",
      minor_delta: 0, serious_delta: 1, critical_delta: 0,
      body_minor_delta: 0, body_serious_delta: 1, body_critical_delta: 0,
      armor_value_used: 6, armor_pierce_used: 3,
      armor_minor_absorbed: 0, armor_serious_absorbed: 0, armor_critical_absorbed: 0,
      armor_critical_delta: 0, melee_strength_bonus: 0,
    },
    body_part: { id: "bp-1", name: "Torso", armor_value: 6, effective_armor: 3, minor: 0, serious: 2, critical: 0, disabled: false, destroyed: false },
    magazine: { id: "mag-1", bullets_spent: 1, remaining_rounds: 11 },
    target_state: { is_alive: true, is_conscious: true, secret_flag: "PRIVATE" },
    post_attack_perks: { consumed_effect_ids: [], retry_effect: { ok: true } },
    log_id: "log-1",
    auto: null,
  };
}

function fullOutcome() {
  const raw = fullRawResult();
  return { ok: true, payload: {}, raw, normalized: normalizeResult(raw), code: null, error: null };
}

// ── 1. Returned totals reach roll-resolution ────────────────────────────────

test("1. real returned attack/defense totals land in the trace and its summary", () => {
  const trace = buildAttackResolutionTrace(fullOutcome());
  assert.equal(trace.accuracy.attackTotal, 81);
  assert.equal(trace.accuracy.defenseTotal, 49);
  assert.equal(trace.accuracy.hit, true);
  assert.equal(trace.summary, "HIT · 81 vs 49 · serious");
  const details = buildRollResolutionDetails(trace);
  assert.equal(details.summary, "HIT · 81 vs 49 · serious");
});

// ── 2. Raw rolls ────────────────────────────────────────────────────────────

test("2. raw d100 rolls are copied verbatim when the server returns them", () => {
  const trace = buildAttackResolutionTrace(fullOutcome());
  assert.equal(trace.accuracy.attackRoll, 47);
  assert.equal(trace.accuracy.defenseRoll, 39);
});

// ── 3. Bonuses and penalties ────────────────────────────────────────────────

test("3. attack/defense bonuses and penalties are copied verbatim", () => {
  const trace = buildAttackResolutionTrace(fullOutcome());
  assert.equal(trace.accuracy.attackSkillBonus, 20);
  assert.equal(trace.accuracy.attackManualBonus, 10);
  assert.equal(trace.accuracy.attackManualPenalty, 0);
  assert.equal(trace.accuracy.weaponAccuracyBonus, 4);
  assert.equal(trace.accuracy.fireModeAccuracyModifier, 5);
  assert.equal(trace.accuracy.ammoAccuracyModifier, 2);
  assert.equal(trace.accuracy.defenseManualBonus, 10);
  assert.equal(trace.accuracy.defenseManualPenalty, 0);
  assert.equal(trace.accuracy.defenseSkillSource, "dodge");
});

// ── 4. Damage / armor / ammo ────────────────────────────────────────────────

test("4. damage, armor, and ammo fields are copied verbatim when returned", () => {
  const trace = buildAttackResolutionTrace(fullOutcome());
  assert.equal(trace.damage.attackTotalUsed, 89);
  assert.equal(trace.damage.defenseTotalUsed, 55);
  assert.equal(trace.damage.damageDiff, 34);
  assert.equal(trace.damage.damageLevel, "serious");
  assert.equal(trace.damage.bulletDamage, 8);
  assert.equal(trace.damage.armorValueUsed, 6);
  assert.equal(trace.damage.armorPierceUsed, 3);
  assert.equal(trace.damage.effectiveArmor, 3);
  assert.equal(trace.damage.bodySeriousDelta, 1);
  assert.equal(trace.ammo.spent, 1);
  assert.equal(trace.ammo.remaining, 11);
  assert.equal(trace.ammo.caliber, "7.62");
});

// ── 5. Missing fields are honest ────────────────────────────────────────────

test("5. a field the server did not return shows NOT_RETURNED — never a substituted 0", () => {
  const raw = fullRawResult();
  delete raw.defense; // e.g. an older backend that omits the defense object
  delete raw.magazine;
  const trace = buildAttackResolutionTrace({ ok: true, raw, normalized: normalizeResult(raw) });
  assert.equal(trace.accuracy.defenseRoll, NOT_RETURNED);
  assert.equal(trace.accuracy.defenseTotal, NOT_RETURNED);
  assert.equal(trace.ammo.spent, NOT_RETURNED);
  assert.notEqual(trace.accuracy.defenseRoll, 0);
  // ammo "before" is genuinely not in the RPC response — always honest:
  assert.equal(buildAttackResolutionTrace(fullOutcome()).ammo.before, NOT_RETURNED);
  // and SQL null (e.g. melee ammo_type) is also NOT_RETURNED, not "null":
  const melee = fullRawResult();
  melee.ammo.ammo_type = null;
  assert.equal(buildAttackResolutionTrace({ ok: true, raw: melee }).ammo.ammoType, NOT_RETURNED);
});

// ── 6. No client-side combat math ───────────────────────────────────────────

test("6a. the trace never computes a total the server didn't return (roll+bonuses present, total absent → NOT_RETURNED)", () => {
  const raw = fullRawResult();
  delete raw.attack.total; // roll/bonuses still present — a computing client would sum them
  const trace = buildAttackResolutionTrace({ ok: true, raw });
  assert.equal(trace.accuracy.attackTotal, NOT_RETURNED);
});

test("6b. attackResolutionTrace.js contains no dice/random and no roll arithmetic", () => {
  const src = fs.readFileSync(path.join(repoRoot, "hud", "combat", "attackResolutionTrace.js"), "utf8");
  assert.ok(!/Math\.random|d100|roll\s*\+|\+\s*bonus|total\s*=[^=]/.test(src));
});

// ── 7. One normalized result for Combat Log AND Debug Console ───────────────

test("7. Combat Log entry and Debug Console trace agree — same module, same numbers", () => {
  const outcome = fullOutcome();
  const trace = buildAttackResolutionTrace(outcome);
  const logEntry = buildAttackLogEntry({ sourceCharacterId: "s", targetCharacterId: "t", bodyZoneLabel: "Torso", outcome });
  assert.deepEqual(logEntry.details, buildCombatLogLines(trace, "Torso"));
  assert.ok(logEntry.details.includes("Attack: 81 vs Defense: 49"));
  assert.ok(logEntry.details.includes("Hit"));
  assert.ok(logEntry.details.includes("Damage: serious"));
  assert.ok(logEntry.details.includes("Ammo left: 11"));
});

// ── 8. Copy event includes the full trace ───────────────────────────────────

test("8. Copy event text includes the full nested trace (accuracy + damage + ammo sections)", () => {
  const details = buildRollResolutionDetails(buildAttackResolutionTrace(fullOutcome()));
  const entry = { timestamp: Date.now(), category: "attack", action: "roll-resolution", details, success: true };
  const text = buildEntryCopyText(entry);
  assert.ok(text.includes("accuracy:"));
  assert.ok(text.includes("attackRoll: 47"));
  assert.ok(text.includes("defenseRoll: 39"));
  assert.ok(text.includes("attackTotal: 81"));
  assert.ok(text.includes("defenseTotal: 49"));
  assert.ok(text.includes("damage:"));
  assert.ok(text.includes("damageLevel: serious"));
  assert.ok(text.includes("ammo:"));
  assert.ok(text.includes("remaining: 11"));
  assert.ok(text.includes(`before: ${NOT_RETURNED}`));
});

test("detail lines render the nested trace with indentation and full wrapped values", () => {
  const details = buildRollResolutionDetails(buildAttackResolutionTrace(fullOutcome()));
  const lines = detailLines(details);
  assert.ok(lines.includes("accuracy:"));
  assert.ok(lines.includes("  attackRoll: 47"));
  assert.ok(lines.includes("  hit: true"));
  assert.ok(lines.some((l) => l.startsWith("  before: Not returned by server")));
});

// ── 9/10. Failures never fabricate a hit ────────────────────────────────────

test("9. an { ok:false } denial produces a failure trace with no hit claim and no fabricated numbers", () => {
  const outcome = { ok: false, raw: { ok: false, error: "NO_MAGAZINE" }, normalized: null, code: "NO_MAGAZINE", error: "No magazine inserted." };
  const trace = buildAttackResolutionTrace(outcome);
  assert.equal(trace.ok, false);
  assert.equal(trace.accuracy.hit, NOT_RETURNED);
  assert.equal(trace.accuracy.attackRoll, NOT_RETURNED);
  assert.equal(trace.summary, "No magazine inserted.");
  assert.ok(!trace.summary.includes("HIT"));
});

test("10. an exception outcome (raw:null) also yields no hit claim, and the controller only logs roll-resolution on ok", () => {
  const outcome = { ok: false, raw: null, normalized: null, code: null, error: "Network or RPC error." };
  const trace = buildAttackResolutionTrace(outcome);
  assert.equal(trace.ok, false);
  assert.equal(trace.accuracy.hit, NOT_RETURNED);
  // Controller contract: roll-resolution is gated on outcome.ok — verify the
  // guard exists at the single call site.
  const src = fs.readFileSync(path.join(repoRoot, "hud", "scene", "sceneSelectionController.js"), "utf8");
  const idx = src.indexOf('"roll-resolution"');
  assert.ok(idx > -1, "controller logs a roll-resolution event");
  const guardIdx = src.lastIndexOf("if (outcome.ok)", idx);
  assert.ok(guardIdx > -1 && idx - guardIdx < 400, "roll-resolution is inside the outcome.ok guard");
});

// ── 11. No private data in the trace ────────────────────────────────────────

test("11. trace/copy text never contains target_state, inventory, armory, PSI, skills lists, tokens, or auth data", () => {
  const trace = buildAttackResolutionTrace(fullOutcome());
  const json = JSON.stringify(buildRollResolutionDetails(trace));
  // Sensitive material appears as whole JSON keys/values — match those, not
  // substrings of the trace's own camelCase field names (defenseSkillSource).
  assert.ok(!/"(target_state|inventory|armory|psi|skills|abilities|effects|auth|access_token|post_attack_perks|pending_checks|target_token_id|log_id)"/i.test(json));
  assert.ok(!/is_conscious|secret_flag|PRIVATE|Bearer /.test(json));
});

// ── 12. Required event actions all present in the controller ────────────────

test("12. requested / payload-prepared / result / roll-resolution / source-refresh / target-zone-refresh events all have call sites", () => {
  const scene = fs.readFileSync(path.join(repoRoot, "hud", "scene", "sceneSelectionController.js"), "utf8");
  const targeting = fs.readFileSync(path.join(repoRoot, "hud", "targeting", "targetSelectionController.js"), "utf8");
  for (const action of ["\"requested\"", "\"payload-prepared\"", "\"result\"", "\"roll-resolution\"", "\"source-refresh-result\""]) {
    assert.ok(scene.includes(action), `missing ${action}`);
  }
  assert.ok(targeting.includes("target-body-zone-refresh-result"));
});

test("isReturnedNumber treats only real finite numbers as returned", () => {
  assert.equal(isReturnedNumber(0), true);
  assert.equal(isReturnedNumber(81), true);
  assert.equal(isReturnedNumber(NOT_RETURNED), false);
  assert.equal(isReturnedNumber(null), false);
  assert.equal(isReturnedNumber("81"), false);
});

setTimeout(() => {
  console.log(`\nAttack roll-resolution trace: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`FAILED: ${name}`);
      console.error(err?.stack ?? err);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 50);
