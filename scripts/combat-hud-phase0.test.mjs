// Combat HUD — Phase 0 verification script.
//
// Zero-dependency checks using node:assert. Run with:
//   node scripts/combat-hud-phase0.test.mjs
//
// Imports only the pure HUD core/adapters/models (no OBR SDK, no Supabase,
// no CSS), so it runs without `node_modules` installed.

import assert from "node:assert/strict";

import { createMockCombatHudAdapter } from "../hud/adapters/mockCombatHudAdapter.js";
import { createCombatHudStore } from "../hud/core/combatHudStore.js";
import {
  selectVisibleReserveMagazines,
  selectCompactBattleLog,
} from "../hud/core/combatHudSelectors.js";
import { resetActionDraft } from "../hud/core/combatHudActions.js";
import { EMPTY_REASONS } from "../hud/models/combatHudContracts.js";

/* ----------------- tiny test runner ----------------- */
let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  ✓ ${name}`);
  } catch (error) {
    failed += 1;
    failures.push({ name, error });
    console.error(`  ✗ ${name}\n      ${error.message}`);
  }
}

function freshStore(scenarioId = "A") {
  const adapter = createMockCombatHudAdapter({ scenarioId });
  const store = createCombatHudStore({ adapter });
  store.initialize();
  return { adapter, store };
}

console.log("\nCombat HUD — Phase 0 verification\n");

/* 1. Owned player token → ready. */
test("1. owned player token produces `ready`", () => {
  const { store } = freshStore("A"); // A defaults: viewer player, owns char-vega, token tok-vega
  assert.equal(store.getState().status, "ready");
  assert.equal(store.getState().access.canViewSelectedCharacter, true);
  assert.equal(store.getState().snapshot.entity.summary.id, "char-vega");
});

/* 2. Unauthorised player selection → empty. */
test("2. unauthorised player selection produces `empty`", () => {
  const { store } = freshStore("F"); // F: player selects NPC raider
  const state = store.getState();
  assert.equal(state.status, "empty");
  assert.equal(state.access.reason, EMPTY_REASONS.notOwner);
});

/* 3. GM may inspect the same target. */
test("3. GM may inspect the same target", () => {
  const { store } = freshStore("F");
  assert.equal(store.getState().status, "empty");
  store.setViewerRole("gm");
  const state = store.getState();
  assert.equal(state.status, "ready");
  assert.equal(state.access.canViewSelectedCharacter, true);
  assert.equal(state.snapshot.entity.summary.id, "char-raider");
});

/* 4. Token without character → empty. */
test("4. token without character produces `empty`", () => {
  const { store } = freshStore("A");
  store.selectToken("tok-crate"); // exists in scene, has no character link
  const state = store.getState();
  assert.equal(state.status, "empty");
  assert.equal(state.access.reason, EMPTY_REASONS.noCharacterLink);
});

/* 5. Changing mock scenario refreshes the store. */
test("5. changing mock scenario refreshes the store", () => {
  const { store } = freshStore("A");
  assert.equal(store.getState().snapshot.entity.summary.id, "char-vega");
  store.setMockScenario("C"); // C defaults to GM viewing the raider
  const state = store.getState();
  assert.equal(state.status, "ready");
  assert.equal(state.snapshot.entity.summary.id, "char-raider");
});

/* 6. Subscriptions fire after state changes. */
test("6. subscriptions fire after state changes", () => {
  const { store } = freshStore("A");
  let calls = 0;
  const unsub = store.subscribe(() => { calls += 1; });
  store.selectToken("tok-raider"); // player can't view → empty, but state changes
  store.setViewerRole("gm");        // now ready → state changes again
  assert.ok(calls >= 2, `expected >= 2 notifications, got ${calls}`);
  unsub();
});

/* 7. dispose() removes subscriptions safely. */
test("7. dispose() removes subscriptions safely", () => {
  const { store } = freshStore("A");
  let calls = 0;
  store.subscribe(() => { calls += 1; });
  store.dispose();
  const before = calls;
  // Further actions must not notify and must not throw.
  assert.doesNotThrow(() => {
    store.selectToken("tok-raider");
    store.setViewerRole("gm");
    store.setMockScenario("B");
  });
  assert.equal(calls, before, "listeners should not fire after dispose");
});

/* 8. Reserve magazine selector excludes inserted and empty (and incompatible). */
test("8. reserve magazine selector excludes inserted and empty magazines", () => {
  const { store } = freshStore("A");
  const ids = selectVisibleReserveMagazines(store.getState()).map((m) => m.id);
  assert.deepEqual(ids, ["mag-full", "mag-partial"]);
  assert.ok(!ids.includes("mag-loaded"), "must exclude the inserted magazine");
  assert.ok(!ids.includes("mag-empty"), "must exclude empty magazines");
  assert.ok(!ids.includes("mag-wrong"), "must exclude incompatible caliber");
});

/* 9. Compact battle log returns at most five entries (newest last). */
test("9. compact battle log returns at most five entries", () => {
  // Scenario A has exactly five.
  const { store } = freshStore("A");
  assert.equal(selectCompactBattleLog(store.getState()).length, 5);

  // With more than five, the selector truncates to the last five.
  const seven = Array.from({ length: 7 }, (_v, i) => ({ id: `e${i}`, sequence: i }));
  const compact = selectCompactBattleLog({ snapshot: { battleLog: { entries: seven } } });
  assert.equal(compact.length, 5);
  assert.equal(compact[0].id, "e2");
  assert.equal(compact[4].id, "e6");
});

/* 10. resetActionDraft clears draft UI without erasing runtime snapshot. */
test("10. action reset clears draft UI but keeps snapshot", () => {
  const stateWithDraft = {
    status: "ready",
    snapshot: { entity: { summary: { id: "char-vega" } }, battleLog: { entries: [] } },
    ui: {
      isHudCollapsed: true,
      isBattleLogExpanded: true,
      selectedTechniqueId: "sk-precise",
      selectedAbilityId: "sk-mindspike",
      selectedReloadMagazineId: "mag-full",
      selectedModifierIds: ["mod-cover"],
      targeting: { mode: "token", selectedTargetIds: ["t1"], selectedBodyPartId: "head", selectedPoint: { x: 1, y: 1 }, radius: 3 },
    },
  };
  const next = resetActionDraft(stateWithDraft);
  // Draft cleared:
  assert.equal(next.ui.selectedTechniqueId, null);
  assert.equal(next.ui.selectedAbilityId, null);
  assert.equal(next.ui.selectedReloadMagazineId, null);
  assert.deepEqual(next.ui.selectedModifierIds, []);
  assert.equal(next.ui.targeting.mode, "none");
  assert.equal(next.ui.targeting.selectedBodyPartId, "torso");
  // Snapshot + view prefs preserved:
  assert.equal(next.snapshot.entity.summary.id, "char-vega");
  assert.equal(next.ui.isHudCollapsed, true);
  // Source state object not mutated:
  assert.equal(stateWithDraft.ui.selectedTechniqueId, "sk-precise");
});

/* ----------------- summary ----------------- */
console.log(`\n${passed} passed, ${failed} failed\n`);
if (failed > 0) {
  for (const f of failures) {
    console.error(`FAILED: ${f.name}`);
    console.error(f.error);
  }
  process.exit(1);
}
