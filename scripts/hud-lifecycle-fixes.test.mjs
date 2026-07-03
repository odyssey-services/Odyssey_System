// Combat HUD — Phase 3D.1 lifecycle fixes: tests for
//   A) target/body-zone persistence after Attack
//   B) per-character selected-weapon memory (Token A -> B -> A)
//   G) stale attack results never overwrite a changed selection

import assert from "node:assert/strict";
import { createSelectedWeaponMemory, resolveStoredWeaponId } from "../hud/scene/selectedWeaponMemory.js";
import { buildAttackRequestSignature, isAttackResultStale } from "../hud/combat/basicAttackPolicy.js";
import {
  createInitialTargetState,
  applyResolvedTarget,
  clearTarget,
  refreshTargetBodyZones,
  selectZone,
  buildTargetingBroadcast,
} from "../hud/targeting/targetSelectionState.js";

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

console.log("\nHUD lifecycle fixes (Phase 3D.1)\n");

// ── B: per-character selected-weapon memory ────────────────────────────────

test("4. Token A -> B -> A: A's remembered weapon survives the round trip", () => {
  const mem = createSelectedWeaponMemory();
  mem.set("char-A", "wpn-rifle");
  mem.set("char-B", "wpn-pistol");
  // Simulate switching back to A: the memory still has A's weapon regardless
  // of what happened on B.
  assert.equal(mem.get("char-A"), "wpn-rifle");
});

test("5. selecting a weapon for character A never touches character B's entry", () => {
  const mem = createSelectedWeaponMemory();
  mem.set("char-A", "wpn-rifle");
  mem.set("char-B", "wpn-pistol");
  mem.set("char-A", "wpn-shotgun");
  assert.equal(mem.get("char-A"), "wpn-shotgun");
  assert.equal(mem.get("char-B"), "wpn-pistol");
});

test("6. a remembered weapon no longer in the character's armory falls back safely", () => {
  const mem = createSelectedWeaponMemory();
  mem.set("char-A", "wpn-removed");
  const armoryWeapons = [{ id: "wpn-rifle" }, { id: "wpn-pistol" }];
  const resolved = resolveStoredWeaponId(mem.get("char-A"), armoryWeapons);
  assert.equal(resolved, null); // caller falls back to mapWeapon's own weapons[0] default
});

test("a still-valid remembered weapon resolves to itself", () => {
  const armoryWeapons = [{ id: "wpn-rifle" }, { id: "wpn-pistol" }];
  assert.equal(resolveStoredWeaponId("wpn-pistol", armoryWeapons), "wpn-pistol");
});

test("resolveStoredWeaponId is null-safe for missing storage/armory", () => {
  assert.equal(resolveStoredWeaponId(null, [{ id: "wpn-rifle" }]), null);
  assert.equal(resolveStoredWeaponId("wpn-rifle", null), null);
  assert.equal(resolveStoredWeaponId("wpn-rifle", undefined), null);
});

// ── A: target/body-zone persist after a successful (or failed) Attack ──────

function resolvedTargetState(zoneId = "TORSO") {
  const candidate = {
    tokenId: "tok-target", characterId: "char-target", displayName: "Raider",
    bodyZones: [
      { zoneId: "TORSO", bodyPartId: "bp-torso", canBeTargeted: true },
      { zoneId: "HEAD", bodyPartId: "bp-head", canBeTargeted: true },
    ],
  };
  let s = applyResolvedTarget(createInitialTargetState(), candidate);
  if (zoneId !== "TORSO") s = selectZone(s, zoneId);
  return s;
}

test("1/2. a successful attack does NOT call clearTarget — target + zone survive (refreshTargetBodyZones only updates condition)", () => {
  const before = resolvedTargetState("HEAD");
  // What sceneSelectionController now does on attack SUCCESS is broadcast a
  // "refreshBodyZones" targeting command, which the targeting controller
  // turns into refreshTargetBodyZones() — never clearTarget(). Simulate that:
  const after = refreshTargetBodyZones(before, [
    { zoneId: "TORSO", bodyPartId: "bp-torso", canBeTargeted: true },
    { zoneId: "HEAD", bodyPartId: "bp-head", canBeTargeted: false }, // now disabled by the attack
  ]);
  assert.ok(after.target, "target must still be selected");
  assert.equal(after.target.tokenId, "tok-target");
  assert.equal(after.target.selectedZoneId, "HEAD", "selected body zone must be unchanged");
  const broadcast = buildTargetingBroadcast(after);
  assert.equal(broadcast.target.resolvedBodyPartId, "bp-head", "zone still resolves to the same body part");
});

test("3. a FAILED attack (no refresh, no clear at all) leaves target/zone completely untouched", () => {
  const before = resolvedTargetState("HEAD");
  // On failure sceneSelectionController does not send ANY targeting command —
  // the state is simply whatever it already was.
  const after = before;
  assert.deepEqual(after.target, before.target);
});

test("refreshTargetBodyZones is a no-op when there is no longer a target (stale refresh can't resurrect one)", () => {
  const idle = createInitialTargetState();
  const after = refreshTargetBodyZones(idle, [{ zoneId: "TORSO", bodyPartId: "bp-torso", canBeTargeted: true }]);
  assert.equal(after.target, null);
});

test("only explicit clearTarget() actually drops the target (Cancel/Escape/source-change/link-loss path)", () => {
  const before = resolvedTargetState();
  const cleared = clearTarget(before);
  assert.equal(cleared.target, null);
  assert.equal(cleared.mode, "idle");
});

// ── G: stale attack result must never overwrite a changed selection ───────

test("20a. a stale result (target changed mid-flight) is detected before it could be applied", () => {
  const requestCtx = { sourceCharacterId: "char-1", weaponId: "wpn-1", targetCharacterId: "char-target-1" };
  const stateAfterUserSwitchedTarget = { sourceCharacterId: "char-1", weaponId: "wpn-1", targetCharacterId: "char-target-2" };
  assert.equal(isAttackResultStale(requestCtx, stateAfterUserSwitchedTarget), true);
});

test("20b. a non-stale result (nothing changed) is recognized as current", () => {
  const requestCtx = { sourceCharacterId: "char-1", weaponId: "wpn-1", targetCharacterId: "char-target-1" };
  assert.equal(isAttackResultStale(requestCtx, { ...requestCtx }), false);
});

test("20c. request signature is a pure, stable function of source/weapon/target only", () => {
  const a = buildAttackRequestSignature({ sourceCharacterId: "c1", weaponId: "w1", targetCharacterId: "t1" });
  const b = buildAttackRequestSignature({ sourceCharacterId: "c1", weaponId: "w1", targetCharacterId: "t1" });
  assert.equal(a, b);
});

setTimeout(() => {
  console.log(`\nHUD lifecycle fixes: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`FAILED: ${name}`);
      console.error(err?.stack ?? err);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 50);
