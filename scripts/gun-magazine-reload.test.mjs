// Combat HUD — partial-magazine reload fix + magazine-selector redesign tests.
//
// Covers:
//  - eligibility ignores fullness (12/12, 8/12 allowed; 0/12 blocked)
//  - a selected partial magazine keeps its real id through the broadcast wire
//    (regression test for the 1.8.29 bug: buildEphemeralForPayload omitted
//    selectedReloadMagazineId, so every reload silently used reserve[0])
//  - the reload payload/candidate matches the canonical Character → Inventory
//    shape and is never swapped for a different magazine
//  - a backend { ok:false } result is surfaced, not reported as success
//  - MagazineSelectorPanel renders full-width label/rounds rows, not pills
//  - companion popover height depends on row count, not a fixed oversized rect

import assert from "node:assert/strict";
import { selectVisibleReserveMagazines, selectSelectedReloadMagazine } from "../hud/core/combatHudSelectors.js";
import { renderMagazineSelectorPanel } from "../hud/components/MagazineSelectorPanel.js";
import { buildBroadcastPayload, SELECTION_STATUS } from "../hud/scene/selectionState.js";
import { resolveReloadMagazineId, isReloadRpcOk, normalizeReloadRpcResult } from "../hud/scene/reloadPolicy.js";
import { computeCompanionSelectorHeight, COMPANION_SELECTOR_WIDTH } from "../hud/overlay/hudPopoverLifecycle.js";

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

function baseWeapon(overrides = {}) {
  return {
    id: "w1",
    name: "Marksman Rifle",
    activeProfileId: "profile-1",
    usesMagazine: true,
    requiresAmmo: true,
    canReload: true,
    loadedMagazine: { id: "m-loaded", current: 0, max: 12, ammoType: ".45exp", caliber: "45" },
    reserveMagazines: [
      { id: "m-full", current: 12, max: 12, ammoType: ".45exp", caliber: "45" },
      { id: "m-partial", current: 8, max: 12, ammoType: ".45pen", caliber: "45" },
      { id: "m-empty", current: 0, max: 12, ammoType: ".45exp", caliber: "45" },
    ],
    ...overrides,
  };
}

function gunState(uiOverrides = {}) {
  return {
    status: "ready",
    snapshot: { weapon: { primary: baseWeapon(), secondary: null } },
    ui: { selectedReloadMagazineId: null, ...uiOverrides },
  };
}

function readyRuntimeBundleState(weaponOverrides = {}) {
  const bundle = {
    character: { id: "char-1", display_name: "Hero", owner_player_id: "p1" },
    state: { is_alive: true, is_conscious: true },
    sections: {
      armory: {
        weapons: [{
          id: "w1",
          name: "Marksman Rifle",
          model: { caliber: "45" },
          active_profile_id: "profile-1",
          active_profile: { id: "profile-1" },
          loaded_magazine: { id: "m-loaded", current_rounds: 0, capacity: 12, ammo_type_name: ".45exp" },
          ...weaponOverrides,
        }],
        magazines: [
          { id: "m-loaded", current_rounds: 0, magazine_def: { capacity: 12, caliber: "45" }, ammo_type_name: ".45exp" },
          { id: "m-full", current_rounds: 12, magazine_def: { capacity: 12, caliber: "45" }, ammo_type_name: ".45exp" },
          { id: "m-partial", current_rounds: 8, magazine_def: { capacity: 12, caliber: "45" }, ammo_type_name: ".45pen" },
          { id: "m-empty", current_rounds: 0, magazine_def: { capacity: 12, caliber: "45" }, ammo_type_name: ".45exp" },
        ],
      },
    },
  };
  return {
    status: SELECTION_STATUS.ready,
    selectedItemId: "tok-1",
    characterId: "char-1",
    viewer: { playerId: "p1", role: "PLAYER" },
    access: { canView: true, reason: null },
    runtimeBundle: bundle,
    view: { name: "Hero" },
    error: { code: null, message: null },
  };
}

console.log("\nGun Magazine Reload (partial-magazine fix)\n");

// ── B: eligibility ignores fullness ─────────────────────────────────────────

test("1. full magazine (12/12) is eligible for reload", () => {
  const visible = selectVisibleReserveMagazines(gunState());
  assert.ok(visible.some((m) => m.id === "m-full"));
});

test("2. partially filled magazine (8/12) is eligible for reload", () => {
  const visible = selectVisibleReserveMagazines(gunState());
  assert.ok(visible.some((m) => m.id === "m-partial"));
});

test("3. empty magazine (0/12) is NOT eligible for reload", () => {
  const visible = selectVisibleReserveMagazines(gunState());
  assert.ok(!visible.some((m) => m.id === "m-empty"));
});

// ── ID stability through the broadcast wire ─────────────────────────────────

test("4. a selected partially filled magazine keeps its real id after selection", () => {
  const state = gunState({ selectedReloadMagazineId: "m-partial" });
  const selected = selectSelectedReloadMagazine(state);
  assert.ok(selected);
  assert.equal(selected.id, "m-partial");
  assert.equal(selected.current, 8);
});

test("selectedReloadMagazineId survives buildBroadcastPayload (regression: it used to be dropped)", () => {
  const payload = buildBroadcastPayload(readyRuntimeBundleState(), { selectedReloadMagazineId: "m-partial" });
  assert.equal(payload.ui.selectedReloadMagazineId, "m-partial");
});

// ── Reload payload matches the canonical Character → Inventory shape ───────

test("5. reload payload shape matches Character → Inventory (character_weapon_id/profile_id/character_magazine_id)", () => {
  const weapon = { id: "w1", activeProfileId: "profile-1", reserveMagazines: [{ id: "m-full" }, { id: "m-partial" }] };
  const magazineId = resolveReloadMagazineId({ magazineId: "m-partial" }, { selectedReloadMagazineId: null }, weapon);
  const payload = { character_weapon_id: weapon.id, profile_id: weapon.activeProfileId, character_magazine_id: magazineId };
  assert.deepEqual(payload, { character_weapon_id: "w1", profile_id: "profile-1", character_magazine_id: "m-partial" });
});

test("6. reload does NOT swap the selected partial magazine for reserve[0] (the 1.8.29 regression)", () => {
  const weapon = { id: "w1", activeProfileId: "profile-1", reserveMagazines: [{ id: "m-full" }, { id: "m-partial" }] };
  // reserve[0] is the FULL magazine — resolveReloadMagazineId must still honour
  // the player's explicit partial-magazine selection, not silently substitute it.
  const magazineId = resolveReloadMagazineId(
    { magazineId: "m-partial" },
    { selectedReloadMagazineId: "m-partial" },
    weapon,
  );
  assert.equal(magazineId, "m-partial");
  assert.notEqual(magazineId, weapon.reserveMagazines[0].id);
});

test("6b. with no explicit command id, the ephemeral selection (not reserve[0]) is used", () => {
  const weapon = { id: "w1", activeProfileId: "profile-1", reserveMagazines: [{ id: "m-full" }, { id: "m-partial" }] };
  const magazineId = resolveReloadMagazineId({}, { selectedReloadMagazineId: "m-partial" }, weapon);
  assert.equal(magazineId, "m-partial");
});

// ── ok:false must not be reported as success ────────────────────────────────

test("a backend { ok:false } reload result is NOT treated as success", () => {
  assert.equal(isReloadRpcOk({ ok: false, error: "MAGAZINE_INCOMPATIBLE" }), false);
  assert.equal(isReloadRpcOk({ ok: true }), true);
  assert.equal(isReloadRpcOk(undefined), true); // no explicit ok:false → treat as legacy success shape
});

test("normalizeReloadRpcResult surfaces the real backend error/message", () => {
  const normalized = normalizeReloadRpcResult({ ok: false, error: "MAGAZINE_INCOMPATIBLE", message: "Magazine is not compatible with the selected weapon profile." });
  assert.equal(normalized.ok, false);
  assert.equal(normalized.error, "MAGAZINE_INCOMPATIBLE");
  assert.match(normalized.message, /not compatible/);
});

// ── 7: authoritative refresh path is reachable only on ok:true ─────────────

test("7. reload debug info reports the ok candidate that WOULD be sent for the current selection", () => {
  const payload = buildBroadcastPayload(readyRuntimeBundleState(), {
    selectedReloadMagazineId: "m-partial",
    debugEnabled: true,
  });
  assert.equal(payload.debug.reload.selectedReloadMagazineId, "m-partial");
  assert.equal(payload.debug.reload.reloadPayload.character_magazine_id, "m-partial");
  assert.equal(payload.debug.reload.reloadUiAllowed, true);
});

test("debug.reload is absent unless debugEnabled is set (never leaks bundle data by default)", () => {
  const payload = buildBroadcastPayload(readyRuntimeBundleState(), { selectedReloadMagazineId: "m-partial" });
  assert.equal(payload.debug.reload, undefined);
});

// ── 8/9: MagazineSelectorPanel row shape + content-sized popover ───────────

test("8. MagazineSelectorPanel renders separate left label / right rounds fields, not pills", () => {
  const html = renderMagazineSelectorPanel(gunState());
  assert.ok(html.includes("ohud-reserve-mag-label"));
  assert.ok(html.includes("ohud-reserve-mag-rounds"));
  assert.ok(html.includes("8/12"));
  assert.ok(html.includes("12/12"));
});

test("MagazineSelectorPanel highlights the actually-selected magazine", () => {
  const selectedHtml = renderMagazineSelectorPanel(gunState({ selectedReloadMagazineId: "m-partial" }));
  const partialTag = selectedHtml.match(/<button[^>]*data-magazine-id="m-partial"[^>]*>/)?.[0] ?? "";
  const fullTag = selectedHtml.match(/<button[^>]*data-magazine-id="m-full"[^>]*>/)?.[0] ?? "";
  assert.ok(partialTag.includes("is-selected"));
  assert.ok(!fullTag.includes("is-selected"));

  const noneSelectedHtml = renderMagazineSelectorPanel(gunState());
  assert.ok(!noneSelectedHtml.includes("is-selected"));
});

test("MagazineSelectorPanel never lists the empty (0/12) magazine", () => {
  const html = renderMagazineSelectorPanel(gunState());
  assert.ok(!html.includes('data-magazine-id="m-empty"'));
});

test("9. companion popover height grows with row count and stays within the 220px cap", () => {
  const oneRow = computeCompanionSelectorHeight(1);
  const twoRows = computeCompanionSelectorHeight(2);
  const manyRows = computeCompanionSelectorHeight(50);
  assert.ok(twoRows > oneRow);
  assert.ok(manyRows <= 220);
  assert.ok(COMPANION_SELECTOR_WIDTH >= 180 && COMPANION_SELECTOR_WIDTH <= 230);
});

test("companion popover height for zero rows still yields a sane, non-empty minimum", () => {
  const height = computeCompanionSelectorHeight(0);
  assert.ok(height > 0 && height < 220);
});

setTimeout(() => {
  console.log(`\nGun Magazine Reload: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`FAILED: ${name}`);
      console.error(err?.stack ?? err);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 50);
