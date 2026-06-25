// Combat HUD — Phase 2.1 verification (personal placement math + persistence).
//
// Pure: no DOM, no OBR, no framework. Run with:
//   node scripts/combat-hud-phase21.test.mjs

import assert from "node:assert/strict";

import {
  SAFE_MARGIN,
  DEFAULT_PLACEMENT,
  clampPlacement,
  placementToPixels,
  pixelsToPlacement,
  validatePlacement,
  parsePlacement,
  serializePlacement,
  readStoredPlacement,
  writeStoredPlacement,
  PLACEMENT_STORAGE_KEY,
} from "../hud/overlay/hudPlacement.js";
import {
  serializeHudUiState,
  parseHudUiState,
  normalizeHudUiState,
} from "../hud/overlay/overlayConstants.js";

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

/** Minimal Storage-like double. */
function fakeStorage(initial) {
  const map = new Map(Object.entries(initial || {}));
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => { map.set(k, String(v)); },
    _map: map,
  };
}

const DIMS = { vw: 1920, vh: 1080, hudW: 1316, hudH: 166 };

console.log("\nCombat HUD — Phase 2.1 verification\n");

test("1. default placement is bottom-left (x=0, y=1)", () => {
  assert.deepEqual(DEFAULT_PLACEMENT, { mode: "default", x: 0, y: 1 });
  const px = placementToPixels(DEFAULT_PLACEMENT, DIMS);
  assert.equal(px.left, SAFE_MARGIN);                       // left margin
  assert.equal(px.top, DIMS.vh - DIMS.hudH - SAFE_MARGIN);  // bottom-anchored top
});

test("2. clampPlacement clamps ranges + collapses junk to default", () => {
  assert.deepEqual(clampPlacement({ mode: "custom", x: 2, y: -3 }), { mode: "custom", x: 1, y: 0 });
  assert.deepEqual(clampPlacement(null), { ...DEFAULT_PLACEMENT });
  assert.deepEqual(clampPlacement({ mode: "bogus" }), { ...DEFAULT_PLACEMENT });
  assert.deepEqual(clampPlacement("nope"), { ...DEFAULT_PLACEMENT });
});

test("3. normalized → pixels respects fractions + clamps on-screen", () => {
  const mid = placementToPixels({ mode: "custom", x: 0.5, y: 0.5 }, DIMS);
  const availW = DIMS.vw - DIMS.hudW - 2 * SAFE_MARGIN;
  const availH = DIMS.vh - DIMS.hudH - 2 * SAFE_MARGIN;
  assert.equal(mid.left, Math.round(SAFE_MARGIN + 0.5 * availW));
  assert.equal(mid.top, Math.round(SAFE_MARGIN + 0.5 * availH));
  // out-of-range placement is clamped by clampPlacement before mapping
  const tr = placementToPixels({ mode: "custom", x: 5, y: -5 }, DIMS);
  assert.equal(tr.left, SAFE_MARGIN + availW);
  assert.equal(tr.top, SAFE_MARGIN);
});

test("4. pixels → normalized round-trips a placement", () => {
  const start = { mode: "custom", x: 0.42, y: 0.18 };
  const px = placementToPixels(start, DIMS);
  const back = pixelsToPlacement(px.left, px.top, DIMS);
  assert.equal(back.mode, "custom");
  assert.ok(Math.abs(back.x - start.x) < 0.01, `x ${back.x} ~ ${start.x}`);
  assert.ok(Math.abs(back.y - start.y) < 0.01, `y ${back.y} ~ ${start.y}`);
});

test("5. pixels → normalized clamps to [0,1] for off-screen input", () => {
  const p = pixelsToPlacement(99999, -500, DIMS);
  assert.equal(p.x, 1);
  assert.equal(p.y, 0);
});

test("6. invalid localStorage payloads fall back to default", () => {
  assert.equal(parsePlacement("{not json"), null);
  assert.equal(validatePlacement({ mode: "custom", x: "a", y: 1 }), null);
  assert.deepEqual(readStoredPlacement(fakeStorage({ [PLACEMENT_STORAGE_KEY]: "{bad" })), { ...DEFAULT_PLACEMENT });
  assert.deepEqual(readStoredPlacement(fakeStorage({})), { ...DEFAULT_PLACEMENT });
  assert.deepEqual(readStoredPlacement(null), { ...DEFAULT_PLACEMENT });
});

test("7. write → read round-trips a custom placement through storage", () => {
  const store = fakeStorage();
  const custom = { mode: "custom", x: 0.3, y: 0.7 };
  writeStoredPlacement(store, custom);
  assert.equal(store.getItem(PLACEMENT_STORAGE_KEY), serializePlacement(custom));
  assert.deepEqual(readStoredPlacement(store), custom);
});

test("8. collapse/reopen preserves placement via UI-state round-trip", () => {
  const ui = {
    isHudCollapsed: true,
    mockScenarioId: "A",
    viewerRole: "player",
    selectedTokenId: null,
    hudPlacement: { mode: "custom", x: 0.8, y: 0.2 },
  };
  const restored = normalizeHudUiState(parseHudUiState(serializeHudUiState(ui)));
  assert.equal(restored.isHudCollapsed, true);
  assert.deepEqual(restored.hudPlacement, { mode: "custom", x: 0.8, y: 0.2 });
});

console.log(`\n${passed} passed, ${failed} failed\n`);
if (failed > 0) {
  for (const f of failures) {
    console.error(`FAILED: ${f.name}`);
    console.error(f.error);
  }
  process.exit(1);
}
