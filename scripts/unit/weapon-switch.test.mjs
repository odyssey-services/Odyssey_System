import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { createTestSuite } from "./_tinyTestRunner.mjs";
import { fixtureSet } from "./_fixtures.mjs";
import { switchActiveWeaponMock } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit - Weapon Switch");
const fx = fixtureSet();

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");
const sql118 = fs.readFileSync(path.join(repoRoot, "supabase", "118_fix_switch_active_weapon_safe_swap.sql"), "utf8");
const sqlAll = fs.readFileSync(path.join(repoRoot, "supabase", "odyssey_supabase.sql"), "utf8");

function baseWeapons() {
  return [
    { id: fx.characterWeapons.katanaEquipped.id, name: "Unarmed", equipped_slot: "primary" },
    { id: fx.characterWeapons.pistolLoaded.id, name: "Standard Rifle", equipped_slot: "secondary" },
    { id: fx.characterWeapons.katanaSpare.id, name: "Plasma Katana", equipped_slot: null },
  ];
}

function countSlot(weapons, slot) {
  return weapons.filter((weapon) => weapon.equipped_slot === slot).length;
}

function assertUniqueSlots(weapons) {
  assert.ok(countSlot(weapons, "primary") <= 1, "at most one primary weapon");
  assert.ok(countSlot(weapons, "secondary") <= 1, "at most one secondary weapon");
}

function latestSwitchFunction(sqlText) {
  const marker = "create or replace function public.switch_active_weapon(";
  const start = sqlText.lastIndexOf(marker);
  const end = sqlText.indexOf("grant execute on function public.switch_active_weapon(jsonb)", start);
  return start >= 0 && end > start ? sqlText.slice(start, end) : "";
}

test("safe swap updates unarmed to rifle with one primary and one secondary", () => {
  const result = switchActiveWeaponMock({
    weapons: baseWeapons(),
    targetWeaponId: fx.characterWeapons.pistolLoaded.id,
  });
  assert.equal(result.ok, true);
  const unarmed = result.weapons.find((weapon) => weapon.id === fx.characterWeapons.katanaEquipped.id);
  const rifle = result.weapons.find((weapon) => weapon.id === fx.characterWeapons.pistolLoaded.id);
  assert.equal(rifle?.equipped_slot, "primary");
  assert.equal(unarmed?.equipped_slot, "secondary");
  assertUniqueSlots(result.weapons);
});

test("safe swap updates rifle to katana and clears old secondary", () => {
  const first = switchActiveWeaponMock({
    weapons: baseWeapons(),
    targetWeaponId: fx.characterWeapons.pistolLoaded.id,
  });
  const second = switchActiveWeaponMock({
    weapons: first.weapons,
    targetWeaponId: fx.characterWeapons.katanaSpare.id,
  });
  const rifle = second.weapons.find((weapon) => weapon.id === fx.characterWeapons.pistolLoaded.id);
  const katana = second.weapons.find((weapon) => weapon.id === fx.characterWeapons.katanaSpare.id);
  const unarmed = second.weapons.find((weapon) => weapon.id === fx.characterWeapons.katanaEquipped.id);
  assert.equal(katana?.equipped_slot, "primary");
  assert.equal(rifle?.equipped_slot, "secondary");
  assert.equal(unarmed?.equipped_slot, null);
  assertUniqueSlots(second.weapons);
});

test("repeated A to B to A switching keeps unique slot invariant", () => {
  const first = switchActiveWeaponMock({
    weapons: baseWeapons(),
    targetWeaponId: fx.characterWeapons.pistolLoaded.id,
  });
  const second = switchActiveWeaponMock({
    weapons: first.weapons,
    targetWeaponId: fx.characterWeapons.katanaEquipped.id,
  });
  const primary = second.weapons.find((weapon) => weapon.equipped_slot === "primary");
  const secondary = second.weapons.find((weapon) => weapon.equipped_slot === "secondary");
  assert.equal(primary?.id, fx.characterWeapons.katanaEquipped.id);
  assert.equal(secondary?.id, fx.characterWeapons.pistolLoaded.id);
  assertUniqueSlots(second.weapons);
});

test("already-primary target does not spend cost or change slots", () => {
  const weapons = baseWeapons();
  const before = JSON.stringify(weapons);
  const result = switchActiveWeaponMock({
    weapons,
    targetWeaponId: fx.characterWeapons.katanaEquipped.id,
  });
  assert.equal(result.ok, true);
  assert.equal(result.spent, false);
  assert.equal(JSON.stringify(result.weapons), before);
});

test("cost failure leaves weapon slots unchanged", () => {
  const weapons = baseWeapons();
  const before = JSON.stringify(weapons);
  const result = switchActiveWeaponMock({
    weapons,
    targetWeaponId: fx.characterWeapons.katanaSpare.id,
    costResult: { ok: false, error: "FULL_MOVE_NOT_AVAILABLE", spent: false },
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "FULL_MOVE_NOT_AVAILABLE");
  assert.equal(JSON.stringify(result.weapons), before);
});

test("latest SQL function uses clear-then-assign instead of CASE slot swap", () => {
  const latest = latestSwitchFunction(sqlAll);
  assert.match(latest, /equipped_slot\s*=\s*null/i, "clears current primary and secondary slots first");
  assert.match(latest, /equipped_slot\s+in\s+\('primary',\s*'secondary'\)/i, "clears both primary and secondary slots");
  assert.ok(!/\bcase\b/i.test(latest), "latest function must not use CASE slot swap");
  assert.ok(latest.includes("WEAPON_SLOT_CONFLICT"), "unique violation handler is present");
  assert.match(sql118, /equipped_slot\s*=\s*null/i, "migration patch uses clear-then-assign");
});

await run();
