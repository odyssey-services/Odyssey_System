// Combat HUD - weapon-selector companion data-flow regression tests.
//
// Bug: the weapon-selector companion popover showed "No weapons available"
// even though the Gun HUD displayed the active weapon. Root cause: the
// companion fed the raw broadcast payload straight into
// renderWeaponSelectorPanel(), which reads `state.snapshot.weapon.available`.
// The broadcast payload carries the weapon view model at
// `hudSnapshot.weapon.available`; the `snapshot` shape only exists after
// buildSyntheticState() (the path the Gun module already uses). So
// `state.snapshot` was undefined -> empty list -> false empty state.
//
// Fix: buildCompanionSelectorState() normalizes the payload through the same
// synthetic-state path, so the companion sees an identical weapon view model.
//   node scripts/weapon-selector-companion.test.mjs

import assert from "node:assert/strict";

import { buildCompanionSelectorState } from "../hud/scene/selectionView.js";
import { renderWeaponSelectorPanel } from "../hud/components/WeaponSelectorPanel.js";
import { renderMagazineSelectorPanel } from "../hud/components/MagazineSelectorPanel.js";
import { mapBundleToHudSnapshot } from "../hud/runtime/runtimeBundleMapper.js";

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  Promise.resolve()
    .then(fn)
    .then(() => { passed += 1; console.log(`  PASS ${name}`); })
    .catch((err) => {
      failed += 1;
      failures.push({ name, err });
      console.error(`  FAIL ${name}\n      ${err.message}`);
    });
}

function mixedArmory() {
  return {
    ok: true,
    weapons: [
      {
        id: "w-katana",
        name: "Plasma Katana",
        model: { weapon_class_name: "Melee" },
        active_profile_id: "pk",
        active_profile: { id: "pk", name: "Edge" },
      },
      {
        id: "w-rifle",
        name: "Standard Rifle",
        model: { weapon_class_name: "Rifle", caliber: "5.56" },
        active_profile_id: "pr",
        active_profile: { id: "pr", name: "Standard", selected_fire_mode: { id: "f1", name: "Auto" } },
        loaded_magazine: {
          id: "mr",
          current_rounds: 30,
          capacity: 30,
          ammo_type_name: "FMJ",
          magazine_def: { capacity: 30, caliber: "5.56" },
        },
      },
      {
        id: "w-pistol",
        name: "Frontier Pistol",
        model: { weapon_class_name: "Pistol", caliber: ".45" },
        active_profile_id: "pp",
        active_profile: { id: "pp", name: "Default", selected_fire_mode: { id: "f2", name: "Semi" } },
        loaded_magazine: {
          id: "mp",
          current_rounds: 12,
          capacity: 12,
          ammo_type_name: "exp",
          magazine_def: { capacity: 12, caliber: ".45" },
        },
      },
    ],
    magazines: [
      { id: "mr", current_rounds: 30, magazine_def: { capacity: 30, caliber: "5.56" }, ammo_type_name: "FMJ" },
      { id: "mp", current_rounds: 12, magazine_def: { capacity: 12, caliber: ".45" }, ammo_type_name: "exp" },
    ],
  };
}

function readyPayload(armory, ephemeral = {}) {
  return {
    status: "ready",
    access: { canView: true, reason: null },
    characterId: "c1",
    selectedItemId: "t1",
    viewer: { playerId: "p1", role: "PLAYER" },
    hudSnapshot: mapBundleToHudSnapshot({ sections: { armory } }, ephemeral),
    ui: {
      selectedWeaponId: ephemeral.selectedWeaponId ?? null,
      weaponSelectorOpen: ephemeral.weaponSelectorOpen ?? false,
      selectedReloadMagazineId: null,
    },
  };
}

test("broadcast payload exposes 3 weapons under hudSnapshot.weapon.available", () => {
  const p = readyPayload(mixedArmory());
  assert.equal(p.hudSnapshot.weapon.available.length, 3);
  assert.equal(p.snapshot, undefined, "raw payload has no snapshot key");
});

test("companion selector state exposes the same weapon count as the Gun module", () => {
  const p = readyPayload(mixedArmory());
  const selState = buildCompanionSelectorState(p);
  assert.ok(selState, "companion state built");
  assert.equal(selState.snapshot.weapon.available.length, p.hudSnapshot.weapon.available.length);
  assert.equal(selState.snapshot.weapon.available.length, 3);
});

test("REGRESSION: raw payload (hudSnapshot, no snapshot) still yields weapons", () => {
  const p = readyPayload(mixedArmory());
  const selState = buildCompanionSelectorState(p);
  const html = renderWeaponSelectorPanel(selState);
  assert.ok(!html.includes("No weapons available"), "must not show false empty");
  assert.ok(html.includes("Standard Rifle"));
});

test("melee weapon (no magazine) appears in the selector", () => {
  const html = renderWeaponSelectorPanel(buildCompanionSelectorState(readyPayload(mixedArmory())));
  assert.ok(html.includes("Plasma Katana"), "melee weapon listed");
});

test("weapon without caliber appears, with a '-' ammo label", () => {
  const p = readyPayload(mixedArmory());
  const katana = p.hudSnapshot.weapon.available.find((w) => w.id === "w-katana");
  assert.ok(katana, "katana present in available");
  assert.equal(katana.ammoLabel, "-", "melee weapon shows '-' for ammo");
  const html = renderWeaponSelectorPanel(buildCompanionSelectorState(p));
  assert.ok(html.includes("Plasma Katana") && html.includes("Standard Rifle") && html.includes("Frontier Pistol"));
});

test("null state -> 'Loading weapons...' (snapshot not arrived)", () => {
  const html = renderWeaponSelectorPanel(null);
  assert.ok(html.includes("Loading weapons"), "controlled loading state");
  assert.ok(!html.includes("No weapons available"));
});

test("not-ready / no-snapshot payload -> companion state null -> loading", () => {
  assert.equal(buildCompanionSelectorState(null), null);
  assert.equal(buildCompanionSelectorState({ status: "loading", access: { canView: false } }), null);
  assert.equal(buildCompanionSelectorState({ status: "ready", access: { canView: true }, hudSnapshot: null }), null);
});

test("ready snapshot with empty weapons -> 'No weapons available'", () => {
  const p = readyPayload({ ok: true, weapons: [], magazines: [] });
  const selState = buildCompanionSelectorState(p);
  assert.ok(selState, "state present even with zero weapons");
  const html = renderWeaponSelectorPanel(selState);
  assert.ok(html.includes("No weapons available"));
  assert.ok(!html.includes("Loading weapons"));
});

test("ready payload available immediately -> list, never false empty", () => {
  const html = renderWeaponSelectorPanel(buildCompanionSelectorState(readyPayload(mixedArmory())));
  assert.ok(!html.includes("No weapons available"));
  assert.ok(!html.includes("Loading weapons"));
  assert.ok(html.includes("ohud-weapon-option"));
});

test("active_weapon_id picks a non-default primary and marks it in the list", () => {
  const def = readyPayload(mixedArmory());
  assert.equal(def.hudSnapshot.weapon.primary.id, "w-katana");

  const chosenArmory = mixedArmory();
  chosenArmory.active_weapon_id = "w-pistol";
  const chosen = readyPayload(chosenArmory, { selectedWeaponId: "w-pistol" });
  assert.equal(chosen.hudSnapshot.weapon.primary.id, "w-pistol", "Gun primary follows active weapon");
  const selState = buildCompanionSelectorState(chosen);
  const marked = selState.snapshot.weapon.available.find((w) => w.selected);
  assert.equal(marked?.id, "w-pistol", "selector marks the active weapon");
  const html = renderWeaponSelectorPanel(selState);
  assert.ok(html.includes("is-selected"));
});

test("weaponSelectorOpen flag does not change the available weapon list", () => {
  const open = buildCompanionSelectorState(readyPayload(mixedArmory(), { weaponSelectorOpen: true }));
  const closed = buildCompanionSelectorState(readyPayload(mixedArmory(), { weaponSelectorOpen: false }));
  assert.equal(open.snapshot.weapon.available.length, closed.snapshot.weapon.available.length);
  assert.equal(closed.snapshot.weapon.available.length, 3, "list survives regardless of open state");
});

test("magazine companion: null state -> loading, ready state -> reads snapshot", () => {
  assert.ok(renderMagazineSelectorPanel(null).includes("Loading magazines"));
  const armory = mixedArmory();
  armory.active_weapon_id = "w-rifle";
  const selState = buildCompanionSelectorState(readyPayload(armory, { selectedWeaponId: "w-rifle" }));
  const html = renderMagazineSelectorPanel(selState);
  assert.ok(!html.includes("Loading magazines"), "snapshot present -> not loading");
});

setTimeout(() => {
  console.log(`\nWeapon selector companion: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`  FAIL: ${name}`);
      console.error(`    ${err?.stack ?? err}`);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 200);
