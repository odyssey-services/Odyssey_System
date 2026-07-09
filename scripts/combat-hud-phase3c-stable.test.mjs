// Combat HUD - Phase 3C stabilisation tests.
//
// Covers the v1 weapon/ammo/target stabilisation work:
// - canonical armory shape -> HUD weapon view model (inserted + reserve mags)
// - loaded_magazine and active_profile.loaded_magazine both supported
// - inventory magazines priority, armory.magazines fallback (buildCanonicalArmory)
// - weapon selector closed by default; opens as a flow block (no duplicate Gun)
// - weapon selection changes the PRIMARY view model (not just a CSS class),
//   and is not overwritten by weapons[0] on refresh
// - inserted / empty / incompatible reserve magazines filtered correctly
// - clickable body zones live ON the silhouette - NO text zone chips/buttons
// - humanoid target default zone = TORSO; activeIntent weapon-attack/skill
// - targeting state machine: selectZone / clearTarget / cancel / source guard

import assert from "node:assert/strict";

import { renderTargetBlock } from "../hud/components/TargetBlock.js";
import { renderGunBlock } from "../hud/components/GunBlock.js";
import {
  HUMANOID_PROFILE,
  zoneIdToSvgPart,
  svgPartToZoneId,
} from "../hud/targeting/targetProfiles.js";
import {
  mapWeapon,
  mapBundleToHudSnapshot,
  buildCanonicalArmory,
} from "../hud/runtime/runtimeBundleMapper.js";
import { selectVisibleReserveMagazines } from "../hud/core/combatHudSelectors.js";
import {
  createInitialTargetState,
  startPicking,
  cancelPicking,
  clearTarget,
  selectZone,
  applySource,
  applyResolvedTarget,
} from "../hud/targeting/targetSelectionState.js";
import {
  buildBroadcastPayload,
  deriveSelectionState,
} from "../hud/scene/selectionState.js";

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  Promise.resolve()
    .then(fn)
    .then(() => {
      passed += 1;
      console.log(`  PASS ${name}`);
    })
    .catch((err) => {
      failed += 1;
      failures.push({ name, err });
      console.error(`  FAIL ${name}\n      ${err.message}`);
    });
}

function canonicalArmory() {
  return {
    ok: true,
    weapons: [
      {
        id: "w1",
        name: "Marksman Rifle",
        model: { weapon_class_name: "Rifle", caliber: "5.56" },
        active_profile_id: "p1",
        active_profile: {
          id: "p1",
          name: "Standard",
          selected_fire_mode: { id: "fm1", name: "Semi" },
          available_fire_modes: [{ id: "fm1", name: "Semi" }, { id: "fm2", name: "Auto" }],
        },
        loaded_magazine: {
          id: "m1",
          current_rounds: 20,
          capacity: 30,
          ammo_type_name: "FMJ",
          magazine_def: { capacity: 30, caliber: "5.56", caliber_name: "5.56mm" },
        },
      },
      {
        id: "w2",
        name: "Sidearm",
        model: { weapon_class_name: "Pistol", caliber: "9mm" },
        active_profile_id: "p2",
        active_profile: {
          id: "p2",
          name: "Default",
          loaded_magazine: {
            id: "m4",
            current_rounds: 12,
            capacity: 15,
            ammo_type_name: "JHP",
            magazine_def: { capacity: 15, caliber: "9mm", caliber_name: "9mm" },
          },
          selected_fire_mode: { id: "fm3", name: "Semi" },
          available_fire_modes: [{ id: "fm3", name: "Semi" }],
        },
      },
    ],
    magazines: [
      { id: "m1", current_rounds: 20, magazine_def: { capacity: 30, caliber: "5.56" }, ammo_type_name: "FMJ" },
      { id: "m2", current_rounds: 30, magazine_def: { capacity: 30, caliber: "5.56" }, ammo_type_name: "AP" },
      { id: "m3", current_rounds: 0, magazine_def: { capacity: 30, caliber: "5.56" }, ammo_type_name: "FMJ" },
      { id: "m4", current_rounds: 12, magazine_def: { capacity: 15, caliber: "9mm" }, ammo_type_name: "JHP" },
    ],
  };
}

function targetState(targetingOverride = {}) {
  return {
    status: "ready",
    selectedCharacterId: "char-1",
    snapshot: {
      entity: { name: "Hero", svgRef: "humanoid" },
      combatSession: { status: "inactive", participants: [] },
    },
    ui: {
      targeting: {
        mode: "none",
        selectedTargetIds: [],
        selectedTargetName: null,
        selectedBodyPartId: "TORSO",
        distance: null,
        ...targetingOverride,
      },
    },
  };
}

function gunState({ weaponSelectorOpen = false, available = [] } = {}) {
  return {
    snapshot: {
      weapon: {
        primary: {
          id: "w1",
          name: "Marksman Rifle",
          svgRef: "rifle",
          usesMagazine: true,
          requiresAmmo: true,
          canReload: false,
          loadedMagazine: { id: "m1", current: 20, max: 30, ammoType: "FMJ", caliber: "5.56" },
          reserveMagazines: [],
          fireModes: ["Semi"],
          currentFireMode: "Semi",
          ammo: { current: 20, max: 30 },
        },
        secondary: null,
        available,
      },
    },
    ui: { weaponSelectorOpen, selectedReloadMagazineId: null, targeting: { selectedBodyPartId: "torso" } },
  };
}

function readyPayload(ephemeralOverride = {}) {
  const character = { id: "c1", display_name: "Hero", character_key: "HERO", owner_player_id: "p1" };
  const state = deriveSelectionState(
    { ok: true, links: [{ token_id: "t1", is_active: true, character }] },
    { ok: true, character, state: { is_alive: true, is_conscious: true }, sections: {} },
    { playerId: "p1", role: "PLAYER" },
  );
  return buildBroadcastPayload(state, {
    selectedWeaponId: null,
    weaponSelectorOpen: false,
    preparedAction: null,
    targeting: { mode: "none", selectedTargetIds: [], selectedBodyPartId: "TORSO" },
    commandStatus: null,
    activeIntent: { kind: "weapon-attack", weaponId: null },
    ...ephemeralOverride,
  });
}

function gunStateWithReserve(weaponVM) {
  return { snapshot: { weapon: { primary: weaponVM } }, ui: {} };
}

console.log("\nCombat HUD - Phase 3C stabilization verification\n");

test("zoneIdToSvgPart maps wire ids to svg parts", () => {
  assert.equal(zoneIdToSvgPart("TORSO"), "torso");
  assert.equal(zoneIdToSvgPart("HEAD"), "head");
  assert.equal(zoneIdToSvgPart("LEFT_ARM"), "l_arm");
  assert.equal(zoneIdToSvgPart("UNKNOWN"), null);
});

test("svgPartToZoneId reverse maps svg parts to wire ids", () => {
  assert.equal(svgPartToZoneId("torso"), "TORSO");
  assert.equal(svgPartToZoneId("l_leg"), "LEFT_LEG");
  assert.equal(svgPartToZoneId("nope"), null);
});

test("mapWeapon keeps inserted canonical magazine", () => {
  const w = mapWeapon(canonicalArmory(), "w1");
  assert.ok(w?.loadedMagazine);
  assert.equal(w.loadedMagazine.current, 20);
  assert.equal(w.loadedMagazine.max, 30);
  assert.equal(w.ammo.current, 20);
  assert.equal(w.ammo.max, 30);
});

test("mapWeapon honors active_profile.loaded_magazine", () => {
  const w = mapWeapon(canonicalArmory(), "w2");
  assert.ok(w?.loadedMagazine);
  assert.equal(w.loadedMagazine.current, 12);
  assert.equal(w.loadedMagazine.max, 15);
});

test("mapWeapon reserve excludes inserted and incompatible magazines", () => {
  const w = mapWeapon(canonicalArmory(), "w1");
  const ids = w.reserveMagazines.map((m) => m.id);
  assert.ok(!ids.includes("m1"));
  assert.ok(!ids.includes("m4"));
  assert.ok(ids.includes("m2"));
});

test("selectVisibleReserveMagazines filters empty inserted wrong-caliber", () => {
  const w = mapWeapon(canonicalArmory(), "w1");
  const visible = selectVisibleReserveMagazines(gunStateWithReserve(w));
  assert.deepEqual(visible.map((m) => m.id), ["m2"]);
});

test("buildCanonicalArmory prefers inventory magazines", () => {
  const merged = buildCanonicalArmory(
    { ok: true, weapons: [{ id: "w1" }], magazines: [{ id: "a1" }] },
    { magazines: [{ id: "i1" }, { id: "i2" }] },
  );
  assert.deepEqual(merged.magazines.map((m) => m.id), ["i1", "i2"]);
});

test("buildCanonicalArmory falls back to armory magazines", () => {
  const merged = buildCanonicalArmory(
    { ok: true, weapons: [{ id: "w1" }], magazines: [{ id: "a1" }] },
    null,
  );
  assert.deepEqual(merged.magazines.map((m) => m.id), ["a1"]);
});

test("buildCanonicalArmory returns null for invalid armory", () => {
  assert.equal(buildCanonicalArmory(null, null), null);
  assert.equal(buildCanonicalArmory({ ok: false }, null), null);
  assert.equal(buildCanonicalArmory({ ok: true }, null), null);
});

test("mapBundleToHudSnapshot default primary is weapons[0]", () => {
  const snap = mapBundleToHudSnapshot({ sections: { armory: canonicalArmory() } }, {});
  assert.equal(snap.weapon.primary.id, "w1");
});

test("mapBundleToHudSnapshot respects active_weapon_id", () => {
  const armory = canonicalArmory();
  armory.active_weapon_id = "w2";
  const snap = mapBundleToHudSnapshot({ sections: { armory } }, { selectedWeaponId: "w2" });
  assert.equal(snap.weapon.primary.id, "w2");
  assert.equal(snap.weapon.primary.name, "Sidearm");
});

test("active weapon stays stable across refreshes", () => {
  const armory = canonicalArmory();
  armory.active_weapon_id = "w2";
  const bundle = { sections: { armory } };
  const first = mapBundleToHudSnapshot(bundle, { selectedWeaponId: "w2" });
  const second = mapBundleToHudSnapshot(bundle, { selectedWeaponId: "w2" });
  assert.equal(first.weapon.primary.id, "w2");
  assert.equal(second.weapon.primary.id, "w2");
});

test("available weapon inventory marks the active weapon", () => {
  const armory = canonicalArmory();
  armory.active_weapon_id = "w2";
  const snap = mapBundleToHudSnapshot({ sections: { armory } }, { selectedWeaponId: "w2" });
  const selected = snap.weapon.available.find((option) => option.selected);
  assert.equal(selected?.id, "w2");
});

test("GunBlock closed by default hides weapon list", () => {
  const html = renderGunBlock(gunState({
    weaponSelectorOpen: false,
    available: [
      { id: "w1", name: "Rifle", type: "Rifle", selected: true, ammoLabel: "20/30" },
      { id: "w2", name: "Sidearm", type: "Pistol", selected: false, ammoLabel: "12/15" },
    ],
  }));
  assert.ok(!html.includes("ohud-weapon-list"));
});

test("GunBlock weapon selector is companion popover not in Gun block HTML", () => {
  const html = renderGunBlock(gunState({
    weaponSelectorOpen: true,
    available: [
      { id: "w1", name: "Rifle", type: "Rifle", selected: true, ammoLabel: "20/30" },
      { id: "w2", name: "Sidearm", type: "Pistol", selected: false, ammoLabel: "12/15" },
    ],
  }));
  assert.ok(!html.includes("ohud-weapon-list"));
  assert.equal((html.match(/class="ohud-gun"/g) || []).length, 1);
  assert.ok(html.includes('data-action="toggle-weapon-selector"'));
});

test("TargetBlock without target shows pick button", () => {
  const html = renderTargetBlock(targetState({ mode: "none", selectedTargetIds: [] }));
  assert.ok(html.includes('data-action="pick-target"'));
  assert.ok(!html.includes('data-action="select-target-zone"'));
});

test("TargetBlock with target shows six clickable silhouette zones", () => {
  const html = renderTargetBlock(targetState({
    mode: "none",
    selectedTargetIds: ["tok-X"],
    selectedTargetName: "Enemy",
    selectedBodyPartId: "TORSO",
    distance: 5,
  }));
  assert.equal((html.match(/data-action="select-target-zone"/g) || []).length, 6);
  for (const zone of HUMANOID_PROFILE.zones) {
    assert.ok(html.includes(`data-zone-id="${zone.id}"`));
  }
});

test("TargetBlock has no legacy text zone chips", () => {
  const html = renderTargetBlock(targetState({
    mode: "none",
    selectedTargetIds: ["tok-X"],
    selectedTargetName: "Enemy",
    selectedBodyPartId: "TORSO",
  }));
  assert.ok(!html.includes("ohud-zone-chip"));
  assert.ok(!/<button[^>]*select-target-zone/.test(html));
});

test("TargetBlock carries clickable class and highlight", () => {
  const html = renderTargetBlock(targetState({
    mode: "none",
    selectedTargetIds: ["tok-X"],
    selectedTargetName: "Enemy",
    selectedBodyPartId: "LEFT_ARM",
  }));
  assert.ok(html.includes("ohud-zone--clickable"));
  assert.ok(html.includes('data-zone="l_arm"'));
  assert.ok(html.includes("is-target"));
});

test("TargetBlock shows clear control and distance", () => {
  const html = renderTargetBlock(targetState({
    mode: "none",
    selectedTargetIds: ["tok-X"],
    selectedTargetName: "Enemy",
    selectedBodyPartId: "TORSO",
    distance: 12,
  }));
  assert.ok(html.includes('data-action="clear-target"'));
  assert.ok(html.includes("12 m"));
});

test("activeIntent defaults to weapon-attack", () => {
  const payload = readyPayload({ selectedWeaponId: "w-1", activeIntent: { kind: "weapon-attack", weaponId: "w-1" } });
  assert.equal(payload.ui.activeIntent.kind, "weapon-attack");
  assert.equal(payload.ui.activeIntent.weaponId, "w-1");
});

test("activeIntent skill override carries id", () => {
  const payload = readyPayload({
    preparedAction: { kind: "skill", id: "sk-7" },
    activeIntent: { kind: "skill", id: "sk-7" },
  });
  assert.equal(payload.ui.activeIntent.kind, "skill");
  assert.equal(payload.ui.activeIntent.id, "sk-7");
});

test("applyResolvedTarget defaults humanoid target to TORSO and preserves source", () => {
  let state = applySource(createInitialTargetState(), { tokenId: "src", characterId: "c1", characterName: "Hero" });
  state = startPicking(state);
  state = applyResolvedTarget(state, { tokenId: "tok-E", characterId: "c2", displayName: "Enemy", distance: { value: 5, unit: "m" } });
  assert.equal(state.target.selectedZoneId, "TORSO");
  assert.equal(state.source.characterId, "c1");
});

test("selectZone updates only when target exists", () => {
  let state = applySource(createInitialTargetState(), { tokenId: "src", characterId: "c1" });
  state = startPicking(state);
  state = applyResolvedTarget(state, { tokenId: "tok-E", displayName: "Enemy" });
  state = selectZone(state, "LEFT_ARM");
  assert.equal(state.target.selectedZoneId, "LEFT_ARM");
  const noTarget = selectZone(createInitialTargetState(), "HEAD");
  assert.equal(noTarget.target, null);
});

test("clearTarget removes target and returns to idle", () => {
  let state = applySource(createInitialTargetState(), { tokenId: "src", characterId: "c1" });
  state = startPicking(state);
  state = applyResolvedTarget(state, { tokenId: "tok-E", displayName: "Enemy" });
  state = clearTarget(state);
  assert.equal(state.target, null);
  assert.equal(state.mode, "idle");
});

test("cancelPicking preserves previous target and source", () => {
  let state = applySource(createInitialTargetState(), { tokenId: "src", characterId: "c1" });
  state = startPicking(state);
  state = applyResolvedTarget(state, { tokenId: "tok-E", displayName: "Enemy" });
  const currentTarget = state.target;
  state = startPicking(state);
  state = cancelPicking(state);
  assert.deepEqual(state.target, currentTarget);
  assert.equal(state.source.characterId, "c1");
});

setTimeout(() => {
  console.log(`\nPhase 3C stable: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`FAILED: ${name}`);
      console.error(err?.stack ?? err);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 200);
