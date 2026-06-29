import assert from "node:assert/strict";
import { renderGunBlock } from "../hud/components/GunBlock.js";
import { renderWeaponSelectorPanel } from "../hud/components/WeaponSelectorPanel.js";
import { renderMagazineSelectorPanel } from "../hud/components/MagazineSelectorPanel.js";
import { selectVisibleReserveMagazines } from "../hud/core/combatHudSelectors.js";

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  Promise.resolve()
    .then(fn)
    .then(() => { passed += 1; console.log(`  PASS ${name}`); })
    .catch((err) => { failed += 1; failures.push({ name, err }); console.error(`  FAIL ${name}\n      ${err.message}`); });
}

function baseWeapon() {
  return {
    id: "w1",
    name: "Marksman Rifle",
    svgRef: "rifle",
    usesMagazine: true,
    requiresAmmo: true,
    canReload: true,
    currentFireMode: "Semi",
    fireModes: ["Semi"],
    loadedMagazine: { id: "m-loaded", current: 20, max: 30, ammoType: ".45exp", caliber: "5.56" },
    reserveMagazines: [
      { id: "m2", current: 30, max: 30, ammoType: ".45exp", caliber: "5.56" },
      { id: "m3", current: 0, max: 30, ammoType: ".45exp", caliber: "5.56" },
    ],
  };
}

function gunState() {
  return {
    status: "ready",
    snapshot: {
      entity: { name: "Hero" },
      weapon: {
        primary: baseWeapon(),
        secondary: null,
        available: [
          { id: "w1", name: "Marksman Rifle", type: "Rifle", selected: true, ammoLabel: "20/30" },
          { id: "w2", name: "Sidearm", type: "Pistol", selected: false, ammoLabel: "12/15" },
        ],
      },
    },
    ui: { weaponSelectorOpen: false, selectedReloadMagazineId: null },
  };
}

console.log("\nGun Companion Popovers\n");

test("GunBlock hides weapon list inline", () => {
  const html = renderGunBlock(gunState());
  assert.ok(!html.includes("ohud-weapon-list"));
});

test("GunBlock renders toggle-weapon-selector button", () => {
  const html = renderGunBlock(gunState());
  assert.ok(html.includes('data-action="toggle-weapon-selector"'));
});

test("GunBlock does not render reserve list inline", () => {
  const html = renderGunBlock(gunState());
  assert.ok(!html.includes("ohud-reserve-list"));
});

test("GunBlock renders magazine selector button", () => {
  const html = renderGunBlock(gunState());
  assert.ok(html.includes("ohud-mag-card"));
  assert.ok(html.includes('data-action="toggle-magazine-selector"'));
});

test("GunBlock ammo shows current/max for inserted magazine", () => {
  const html = renderGunBlock(gunState());
  assert.ok(html.includes("20/30"));
});

test("GunBlock empty magazine uses empty class", () => {
  const state = gunState();
  state.snapshot.weapon.primary.loadedMagazine.current = 0;
  const html = renderGunBlock(state);
  assert.ok(html.includes("ohud-ammo-count--empty"));
});

test("GunBlock missing ammo data shows dash, not 0/0", () => {
  const state = gunState();
  state.snapshot.weapon.primary.loadedMagazine = null;
  const html = renderGunBlock(state);
  assert.ok(!html.includes("0/0"));
  assert.ok(html.includes("—"));
});

test("WeaponSelectorPanel lists available weapons", () => {
  const html = renderWeaponSelectorPanel(gunState());
  assert.ok(html.includes("Marksman Rifle"));
  assert.ok(html.includes("Sidearm"));
  assert.ok(html.includes('data-action="select-weapon"'));
});

test("WeaponSelectorPanel marks selected weapon", () => {
  const html = renderWeaponSelectorPanel(gunState());
  assert.ok(html.includes("is-selected"));
});

test("MagazineSelectorPanel shows compatible spares", () => {
  const html = renderMagazineSelectorPanel(gunState());
  assert.ok(html.includes("30/30"));
  assert.ok(html.includes("ohud-reserve-mag"));
});

test("MagazineSelectorPanel empty state without spares", () => {
  const state = gunState();
  state.snapshot.weapon.primary.reserveMagazines = [];
  const html = renderMagazineSelectorPanel(state);
  assert.ok(html.includes("is-empty"));
});

test("selectVisibleReserveMagazines returns only non-empty compatible non-inserted", () => {
  const visible = selectVisibleReserveMagazines(gunState());
  assert.equal(visible.length, 1);
  assert.equal(visible[0].id, "m2");
});

setTimeout(() => {
  console.log(`\nGun Companion Popovers: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`FAILED: ${name}`);
      console.error(err?.stack ?? err);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 200);
