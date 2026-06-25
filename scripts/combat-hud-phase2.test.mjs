// Combat HUD — Phase 2 verification (pure layout helpers + view-model
// selectors). No DOM, no OBR, no framework. Run with:
//   node scripts/combat-hud-phase2.test.mjs

import assert from "node:assert/strict";

import {
  resolveLayoutMode,
  isTwoRowMode,
  computeExpandedHeight,
  EXPANDED_HEIGHT,
  COMPACT_EXPANDED_HEIGHT,
} from "../hud/overlay/overlayConstants.js";
import {
  resolveBattleLogMode,
  battleLogIsColumn,
  devStripFitsInline,
  buildEmptyStateModel,
  resolveBodyMode,
  zoneStateClass,
  accentClass,
} from "../hud/components/hudLayoutModel.js";
import {
  selectActionLabel,
  selectTargetView,
  selectPlayerStatusLabel,
  selectVisibleStatuses,
  selectModifierChips,
  selectBodyPartLabel,
} from "../hud/core/combatHudSelectors.js";
import { createMockCombatHudAdapter } from "../hud/adapters/mockCombatHudAdapter.js";
import { createCombatHudStore } from "../hud/core/combatHudStore.js";

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

function storeFor(scenarioId) {
  const adapter = createMockCombatHudAdapter({ scenarioId });
  const store = createCombatHudStore({ adapter });
  store.initialize();
  return store;
}

console.log("\nCombat HUD — Phase 2 verification\n");

/* ---- responsive layout mode resolver ---- */

test("1. resolveLayoutMode maps widths to the four modes", () => {
  assert.equal(resolveLayoutMode(1440), "wide");
  assert.equal(resolveLayoutMode(1280), "wide");
  assert.equal(resolveLayoutMode(1100), "medium");
  assert.equal(resolveLayoutMode(960), "medium");
  assert.equal(resolveLayoutMode(800), "compact");
  assert.equal(resolveLayoutMode(620), "compact");
  assert.equal(resolveLayoutMode(480), "mini");
});

test("2. isTwoRowMode only for compact / mini", () => {
  assert.equal(isTwoRowMode("wide"), false);
  assert.equal(isTwoRowMode("medium"), false);
  assert.equal(isTwoRowMode("compact"), true);
  assert.equal(isTwoRowMode("mini"), true);
});

test("3. computeExpandedHeight is taller for two-row layouts", () => {
  assert.equal(computeExpandedHeight(1920), EXPANDED_HEIGHT);   // wide
  assert.equal(computeExpandedHeight(1100), EXPANDED_HEIGHT);   // medium (single row)
  assert.equal(computeExpandedHeight(800), COMPACT_EXPANDED_HEIGHT);  // compact
  assert.equal(computeExpandedHeight(480), COMPACT_EXPANDED_HEIGHT);  // mini
  assert.ok(COMPACT_EXPANDED_HEIGHT > EXPANDED_HEIGHT);
});

/* ---- battle-log presentation ---- */

test("4. resolveBattleLogMode follows mode + expand flag", () => {
  assert.equal(resolveBattleLogMode("wide", false), "card");
  assert.equal(resolveBattleLogMode("wide", true), "expanded");
  assert.equal(resolveBattleLogMode("medium", false), "button");
  assert.equal(resolveBattleLogMode("compact", false), "button");
  assert.equal(resolveBattleLogMode("mini", true), "expanded");
  assert.equal(battleLogIsColumn("wide"), true);
  assert.equal(battleLogIsColumn("medium"), false);
  assert.equal(devStripFitsInline("wide"), true);
  assert.equal(devStripFitsInline("compact"), false);
});

/* ---- empty-state copy ---- */

test("5. buildEmptyStateModel returns calm guidance per reason", () => {
  const notOwner = buildEmptyStateModel({ access: { reason: "CHARACTER_NOT_CONTROLLED_BY_VIEWER" } });
  assert.equal(notOwner.title, "SELECT YOUR CHARACTER");
  assert.match(notOwner.hint, /do not control/i);
  const noToken = buildEmptyStateModel({ access: { reason: "NO_TOKEN_SELECTED" } });
  assert.equal(noToken.title, "SELECT YOUR CHARACTER");
  const noLink = buildEmptyStateModel({ access: { reason: "TOKEN_HAS_NO_CHARACTER" } });
  assert.equal(noLink.title, "NO CHARACTER LINKED");
});

/* ---- pure mappers ---- */

test("6. zoneStateClass / accentClass map semantic names to css suffixes", () => {
  assert.equal(zoneStateClass("critical"), "critical");
  assert.equal(zoneStateClass("healthy"), "healthy");
  assert.equal(zoneStateClass("unknown"), "healthy");
  assert.equal(accentClass("attack"), "attack");
  assert.equal(accentClass("psionic"), "psionic");
  assert.equal(accentClass("bogus"), "neutral");
});

test("7. selectBodyPartLabel formats known + unknown ids", () => {
  assert.equal(selectBodyPartLabel("torso"), "TORSO");
  assert.equal(selectBodyPartLabel("l_arm"), "L.ARM");
  assert.equal(selectBodyPartLabel("tail"), "TAIL");
});

/* ---- view-model selectors against real scenarios ---- */

test("8. resolveBodyMode reflects store status", () => {
  assert.equal(resolveBodyMode(storeFor("A").getState()), "ready");
  assert.equal(resolveBodyMode(storeFor("F").getState()), "empty"); // unauthorised
});

test("9. selectPlayerStatusLabel: own turn / waiting / GM view", () => {
  assert.equal(selectPlayerStatusLabel(storeFor("A").getState()), "YOUR TURN");
  assert.equal(selectPlayerStatusLabel(storeFor("B").getState()), "WAITING");
  assert.equal(selectPlayerStatusLabel(storeFor("G").getState()), "GM VIEW");
});

test("10. selectActionLabel defaults to ATTACK with no drafted skill", () => {
  assert.equal(selectActionLabel(storeFor("A").getState()), "ATTACK");
});

test("11. selectTargetView derives an enemy in active combat, empty otherwise", () => {
  const a = selectTargetView(storeFor("A").getState());
  assert.equal(a.hasTarget, true);
  assert.equal(a.name, "Scrap Raider");
  assert.equal(a.bodyPartLabel, "TORSO");
  const g = selectTargetView(storeFor("G").getState()); // no combat session
  assert.equal(g.hasTarget, false);
});

test("12. selectVisibleStatuses caps to five with overflow", () => {
  const { shown, overflow } = selectVisibleStatuses(storeFor("A").getState(), 2);
  assert.equal(shown.length, 2);
  assert.ok(overflow >= 1); // Vega has >2 statuses+effects
});

test("13. selectModifierChips flattens passive→active→narrative", () => {
  const chips = selectModifierChips(storeFor("A").getState());
  assert.ok(chips.length >= 5);
  // First chips are the passive ones (alwaysActive).
  assert.equal(chips[0].alwaysActive, true);
  // The narrative GM modifier sorts last.
  assert.equal(chips[chips.length - 1].kind, "narrative");
});

console.log(`\n${passed} passed, ${failed} failed\n`);
if (failed > 0) {
  for (const f of failures) {
    console.error(`FAILED: ${f.name}`);
    console.error(f.error);
  }
  process.exit(1);
}
