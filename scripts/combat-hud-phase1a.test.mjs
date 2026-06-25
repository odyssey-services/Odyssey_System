// Combat HUD — Phase 1A/2.1 verification (overlay geometry + UI-state).
//
// Pure: no DOM, no OBR SDK, no framework. Run with:
//   node scripts/combat-hud-phase1a.test.mjs

import assert from "node:assert/strict";

import {
  EXPANDED_HEIGHT,
  COMPACT_EXPANDED_HEIGHT,
  COLLAPSED_WIDTH,
  COLLAPSED_HEIGHT,
  SAFE_MARGIN,
  DEFAULT_HUD_UI_STATE,
  computeExpandedWidth,
  computeContentWidth,
  computeExpandedHeight,
  computeOverlaySize,
  computeAnchorPosition,
  buildOverlayPopoverParams,
  serializeHudUiState,
  parseHudUiState,
  normalizeHudUiState,
} from "../hud/overlay/overlayConstants.js";
import { DEFAULT_PLACEMENT } from "../hud/overlay/hudPlacement.js";
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

console.log("\nCombat HUD — Phase 1A/2.1 verification\n");

/* ---- geometry (Phase 2.1 bottom-left, content-fit) ---- */

test("1. single-row width fits the content on a wide viewport", () => {
  // 1920 is wide; content (Player+gap+rail+pad) is well under the viewport.
  assert.equal(computeExpandedWidth(1920), computeContentWidth(1920));
});

test("2. width caps to the viewport (single row) / fills it (two rows)", () => {
  // 960 is single-row medium but content > available → capped to vw-2*margin.
  assert.equal(computeExpandedWidth(960), 960 - 2 * SAFE_MARGIN);
  // 700 is two-row compact → fills the available width.
  assert.equal(computeExpandedWidth(700), 700 - 2 * SAFE_MARGIN);
});

test("3. height is tight for single row, taller for two rows", () => {
  assert.equal(computeExpandedHeight(1920), EXPANDED_HEIGHT);
  assert.equal(computeExpandedHeight(1100), EXPANDED_HEIGHT);
  assert.equal(computeExpandedHeight(800), COMPACT_EXPANDED_HEIGHT);
  assert.ok(COMPACT_EXPANDED_HEIGHT > EXPANDED_HEIGHT);
});

test("4. overlay size switches between pill and expanded HUD", () => {
  assert.deepEqual(computeOverlaySize(true, 1920), { width: COLLAPSED_WIDTH, height: COLLAPSED_HEIGHT });
  assert.deepEqual(computeOverlaySize(false, 1920), {
    width: computeExpandedWidth(1920), height: computeExpandedHeight(1920),
  });
});

test("5. default placement anchors the bottom-LEFT corner near the corner", () => {
  const width = computeExpandedWidth(1920);
  const a = computeAnchorPosition({ vw: 1920, vh: 1080, width, height: EXPANDED_HEIGHT, placement: DEFAULT_PLACEMENT });
  assert.equal(a.left, SAFE_MARGIN);            // pinned to the left margin
  assert.equal(a.top, 1080 - SAFE_MARGIN);      // bottom edge near the viewport bottom
});

test("6. a custom placement maps + clamps inside the viewport", () => {
  const width = computeExpandedWidth(1920);
  const availW = 1920 - width - 2 * SAFE_MARGIN;
  const a = computeAnchorPosition({ vw: 1920, vh: 1080, width, height: EXPANDED_HEIGHT, placement: { mode: "custom", x: 1, y: 0 } });
  assert.equal(a.left, SAFE_MARGIN + availW);   // pushed to the right edge
  assert.equal(a.top, SAFE_MARGIN + EXPANDED_HEIGHT); // pulled to the top edge (bottom of the top-anchored HUD)
});

test("7. popover params use POSITION + bottom-LEFT origins + margin 0", () => {
  const p = buildOverlayPopoverParams({ vw: 1920, vh: 1080, collapsed: false, placement: DEFAULT_PLACEMENT });
  assert.equal(p.anchorReference, "POSITION");
  assert.equal(p.anchorOrigin.horizontal, "LEFT");
  assert.equal(p.anchorOrigin.vertical, "BOTTOM");
  assert.equal(p.transformOrigin.horizontal, "LEFT");
  assert.equal(p.transformOrigin.vertical, "BOTTOM");
  assert.equal(p.hidePaper, true);
  assert.equal(p.disableClickAway, true);
  assert.equal(p.marginThreshold, 0);
  assert.equal(p.width, computeExpandedWidth(1920));
  assert.equal(p.height, EXPANDED_HEIGHT);
});

test("8. collapsed popover params carry the pill size", () => {
  const p = buildOverlayPopoverParams({ vw: 1280, vh: 800, collapsed: true, placement: DEFAULT_PLACEMENT });
  assert.equal(p.width, COLLAPSED_WIDTH);
  assert.equal(p.height, COLLAPSED_HEIGHT);
});

/* ---- UI-state serialize / parse / normalize (no DOM, no OBR) ---- */

test("9. serialize → parse round-trips a full UI snapshot (incl. placement)", () => {
  const ui = {
    isHudCollapsed: true,
    mockScenarioId: "E",
    viewerRole: "gm",
    selectedTokenId: "tok-mech",
    hudPlacement: { ...DEFAULT_PLACEMENT },
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
  assert.equal(parseHudUiState(serializeHudUiState({ selectedTokenId: "tok a/b" })).selectedTokenId, "tok a/b");
  const nullRound = parseHudUiState(serializeHudUiState({ selectedTokenId: null }));
  assert.equal(nullRound.selectedTokenId, null);
});

test("12. normalize merges a partial snapshot over the defaults", () => {
  const merged = normalizeHudUiState({ mockScenarioId: "B" });
  assert.equal(merged.mockScenarioId, "B");
  assert.equal(merged.isHudCollapsed, DEFAULT_HUD_UI_STATE.isHudCollapsed);
  assert.equal(merged.viewerRole, DEFAULT_HUD_UI_STATE.viewerRole);
  assert.equal(merged.selectedTokenId, DEFAULT_HUD_UI_STATE.selectedTokenId);
  assert.deepEqual(merged.hudPlacement, { ...DEFAULT_PLACEMENT });
});

test("13. parse of empty string yields no keys (safe for merge)", () => {
  assert.deepEqual(parseHudUiState(""), {});
  assert.deepEqual(parseHudUiState(undefined), {});
});

test("14. restore sequence rebuilds store state without DOM/OBR", () => {
  const seeded = serializeHudUiState({
    isHudCollapsed: true, mockScenarioId: "E", viewerRole: "gm", selectedTokenId: "tok-mech",
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
