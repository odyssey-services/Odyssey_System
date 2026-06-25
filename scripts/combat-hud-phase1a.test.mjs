// Combat HUD — Phase 1A verification (non-DOM positioning logic only).
//
// Exercises the pure overlay constants/helpers. No DOM, no OBR SDK, no
// framework. Run with:
//   node scripts/combat-hud-phase1a.test.mjs

import assert from "node:assert/strict";

import {
  EXPANDED_MAX_WIDTH,
  EDGE_MARGIN,
  EXPANDED_HEIGHT,
  COLLAPSED_WIDTH,
  COLLAPSED_HEIGHT,
  BOTTOM_INSET,
  DEFAULT_HUD_UI_STATE,
  computeExpandedWidth,
  computeOverlaySize,
  computeAnchorPosition,
  buildOverlayPopoverParams,
  serializeHudUiState,
  parseHudUiState,
  normalizeHudUiState,
} from "../hud/overlay/overlayConstants.js";
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

console.log("\nCombat HUD — Phase 1A verification\n");

test("1. expanded width clamps to MAX on wide viewports", () => {
  assert.equal(computeExpandedWidth(1920), EXPANDED_MAX_WIDTH);
});

test("2. expanded width follows (vw - margin) on narrow viewports", () => {
  assert.equal(computeExpandedWidth(600), 600 - EDGE_MARGIN);
});

test("3. expanded width never goes negative", () => {
  assert.equal(computeExpandedWidth(10), 0);
  assert.equal(computeExpandedWidth(0), 0);
});

test("4. overlay size switches between collapsed pill and expanded shell", () => {
  const collapsed = computeOverlaySize(true, 1920);
  assert.deepEqual(collapsed, { width: COLLAPSED_WIDTH, height: COLLAPSED_HEIGHT });
  const expanded = computeOverlaySize(false, 1920);
  assert.deepEqual(expanded, { width: EXPANDED_MAX_WIDTH, height: EXPANDED_HEIGHT });
});

test("5. anchor pins bottom-center near the viewport bottom", () => {
  const a = computeAnchorPosition(1920, 1080);
  assert.equal(a.left, 960);                 // horizontally centered
  assert.equal(a.top, 1080 - BOTTOM_INSET);  // small inset above the bottom
});

test("6. anchor stays valid for tiny viewports", () => {
  const a = computeAnchorPosition(0, 0);
  assert.equal(a.left, 0);
  assert.equal(a.top, 0);
});

test("7. popover params use POSITION reference + bottom-center origins", () => {
  const p = buildOverlayPopoverParams({ vw: 1280, vh: 800, collapsed: false });
  assert.equal(p.anchorReference, "POSITION");
  assert.equal(p.anchorOrigin.horizontal, "CENTER");
  assert.equal(p.anchorOrigin.vertical, "BOTTOM");
  assert.equal(p.transformOrigin.horizontal, "CENTER");
  assert.equal(p.transformOrigin.vertical, "BOTTOM");
  assert.equal(p.hidePaper, true);
  assert.equal(p.disableClickAway, true);
  assert.equal(p.width, computeExpandedWidth(1280));
  assert.equal(p.height, EXPANDED_HEIGHT);
  assert.deepEqual(p.anchorPosition, computeAnchorPosition(1280, 800));
});

test("8. collapsed popover params carry the pill size", () => {
  const p = buildOverlayPopoverParams({ vw: 1280, vh: 800, collapsed: true });
  assert.equal(p.width, COLLAPSED_WIDTH);
  assert.equal(p.height, COLLAPSED_HEIGHT);
});

/* ---- follow-up: UI-state serialize / parse / normalize (no DOM, no OBR) ---- */

test("9. serialize → parse round-trips a full UI snapshot", () => {
  const ui = {
    isHudCollapsed: true,
    mockScenarioId: "E",
    viewerRole: "gm",
    selectedTokenId: "tok-mech",
  };
  const round = parseHudUiState(serializeHudUiState(ui));
  assert.deepEqual(round, ui);
});

test("10. parse reads collapsed flag and drops an invalid role", () => {
  const parsed = parseHudUiState("collapsed=1&scenario=C&role=wizard&token=tok-raider");
  assert.equal(parsed.isHudCollapsed, true);
  assert.equal(parsed.mockScenarioId, "C");
  assert.equal(parsed.selectedTokenId, "tok-raider");
  assert.ok(!("viewerRole" in parsed), "invalid role must be dropped");
});

test("11. token round-trips: explicit value preserved, empty → null", () => {
  // Explicit id preserved (incl. through encoding).
  assert.equal(parseHudUiState(serializeHudUiState({ selectedTokenId: "tok a/b" })).selectedTokenId, "tok a/b");
  // Null selection serializes to an empty token param and parses back to null.
  const nullRound = parseHudUiState(serializeHudUiState({ selectedTokenId: null }));
  assert.equal(nullRound.selectedTokenId, null);
});

test("12. normalize merges a partial snapshot over the defaults", () => {
  const merged = normalizeHudUiState({ mockScenarioId: "B" });
  assert.equal(merged.mockScenarioId, "B");
  assert.equal(merged.isHudCollapsed, DEFAULT_HUD_UI_STATE.isHudCollapsed);
  assert.equal(merged.viewerRole, DEFAULT_HUD_UI_STATE.viewerRole);
  assert.equal(merged.selectedTokenId, DEFAULT_HUD_UI_STATE.selectedTokenId);
  // Empty input yields exactly the defaults.
  assert.deepEqual(normalizeHudUiState(), { ...DEFAULT_HUD_UI_STATE });
  assert.deepEqual(normalizeHudUiState(null), { ...DEFAULT_HUD_UI_STATE });
});

test("13. parse of empty string yields no keys (safe for merge)", () => {
  assert.deepEqual(parseHudUiState(""), {});
  assert.deepEqual(parseHudUiState(undefined), {});
});

test("14. restore sequence rebuilds store state without DOM/OBR", () => {
  // Mirrors mountCombatHudOverlay's pre-render restore using only the pure
  // Phase 0 adapter + store (no DOM, no OBR). Round-trip a snapshot through
  // the URL helpers first, exactly as the iframe would.
  const seeded = serializeHudUiState({
    isHudCollapsed: true,
    mockScenarioId: "E",
    viewerRole: "gm",
    selectedTokenId: "tok-mech",
  });
  const restored = normalizeHudUiState(parseHudUiState(seeded));

  const adapter = createMockCombatHudAdapter({ scenarioId: restored.mockScenarioId });
  adapter.setViewerRole(restored.viewerRole);
  adapter.selectToken(restored.selectedTokenId);
  const store = createCombatHudStore({ adapter });
  store.initialize();
  store.setHudCollapsed(restored.isHudCollapsed);

  const s = store.getState();
  assert.equal(s.status, "ready");
  assert.equal(s.viewer.role, "gm");
  assert.equal(s.selectedTokenId, "tok-mech");
  assert.equal(s.selectedCharacterId, "char-vega");
  assert.equal(s.snapshot.entity.summary.characterType, "mech");
  assert.equal(s.ui.isHudCollapsed, true);
  store.dispose();
});

console.log(`\n${passed} passed, ${failed} failed\n`);
if (failed > 0) {
  for (const f of failures) {
    console.error(`FAILED: ${f.name}`);
    console.error(f.error);
  }
  process.exit(1);
}
