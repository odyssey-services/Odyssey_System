// Combat HUD — Phase 2.2 verification (modular layout math + persistence).
//
// Pure: no DOM, no OBR, no framework. Run with:
//   node scripts/combat-hud-phase22.test.mjs

import assert from "node:assert/strict";

import {
  HUD_LAYOUT_REFERENCE_VIEWPORT,
  DEFAULT_HUD_LAYOUT_V2,
  HUD_MODULE_IDS,
  LAYOUT_STORAGE_KEY,
  LAYOUT_MARGIN,
  computeLayoutScale,
  defaultModuleRect,
  moduleSize,
  normalizedToPixels,
  pixelsToNormalized,
  clampRect,
  resolveModuleRect,
  rectsOverlap,
  snapToGrid,
  splitSkillRows,
  defaultLayoutState,
  resetLayoutState,
  validateLayoutState,
  normalizeLayoutState,
  readStoredLayout,
  writeStoredLayout,
  commitDraft,
  cancelDraft,
  setModulePlacement,
} from "../hud/overlay/hudLayout.js";

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

function fakeStorage(initial) {
  const map = new Map(Object.entries(initial || {}));
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => { map.set(k, String(v)); },
    _map: map,
  };
}

const { width: RW, height: RH } = HUD_LAYOUT_REFERENCE_VIEWPORT; // 1920×1080

console.log("\nCombat HUD — Phase 2.2 verification\n");

test("1. exact default rects at 1920×1080", () => {
  assert.equal(computeLayoutScale(RW, RH), 1);
  for (const id of HUD_MODULE_IDS) {
    const def = DEFAULT_HUD_LAYOUT_V2[id];
    const rect = defaultModuleRect(id, RW, RH);
    assert.equal(rect.left, def.left, `${id}.left`);
    assert.equal(rect.width, def.width, `${id}.width`);
    assert.equal(rect.height, def.height, `${id}.height`);
    assert.equal(rect.top, RH - def.bottom - def.height, `${id}.top (bottom ${def.bottom})`);
    assert.equal(rect.zIndex, def.zIndex, `${id}.z`);
  }
  // spot-check player exactly
  assert.deepEqual(defaultModuleRect("player", RW, RH), { left: 16, top: 814, width: 250, height: 250, zIndex: 30 });
});

test("2. default layout scales proportionally below reference", () => {
  // 1600×900 → scale 0.8333…
  const scale = computeLayoutScale(1600, 900);
  assert.ok(Math.abs(scale - (900 / 1080)) < 1e-9);
  const player = defaultModuleRect("player", 1600, 900);
  assert.equal(player.width, Math.round(250 * scale));
  assert.equal(player.height, Math.round(250 * scale));
  // never upscales above the reference
  assert.equal(computeLayoutScale(2560, 1440), 1);
});

test("3. custom normalized placement → pixels", () => {
  const px = normalizedToPixels("gun", { mode: "custom", x: 0.5, y: 0.5 }, RW, RH);
  const { width, height } = moduleSize("gun", RW, RH);
  const availW = RW - width - 2 * LAYOUT_MARGIN;
  const availH = RH - height - 2 * LAYOUT_MARGIN;
  assert.equal(px.left, Math.round(LAYOUT_MARGIN + 0.5 * availW));
  assert.equal(px.top, Math.round(LAYOUT_MARGIN + 0.5 * availH));
});

test("4. pixels → normalized round-trips", () => {
  const start = { mode: "custom", x: 0.37, y: 0.62 };
  const px = normalizedToPixels("skills", start, RW, RH);
  const back = pixelsToNormalized("skills", px.left, px.top, RW, RH);
  assert.ok(Math.abs(back.x - start.x) < 0.01, `x ${back.x}~${start.x}`);
  assert.ok(Math.abs(back.y - start.y) < 0.01, `y ${back.y}~${start.y}`);
});

test("5. clamp keeps every module fully inside the viewport", () => {
  for (const id of HUD_MODULE_IDS) {
    const far = normalizedToPixels(id, { mode: "custom", x: 5, y: 5 }, RW, RH); // off-screen request
    const clamped = clampRect(far, RW, RH);
    assert.ok(clamped.left >= 0 && clamped.left + clamped.width <= RW, `${id} x`);
    assert.ok(clamped.top >= 0 && clamped.top + clamped.height <= RH, `${id} y`);
  }
});

test("6. intentional Player/Gun overlap is preserved", () => {
  const player = resolveModuleRect("player", { mode: "default" }, RW, RH);
  const gun = resolveModuleRect("gun", { mode: "default" }, RW, RH);
  assert.ok(rectsOverlap(player, gun), "player and gun must overlap");
  assert.ok(DEFAULT_HUD_LAYOUT_V2.player.zIndex > DEFAULT_HUD_LAYOUT_V2.gun.zIndex, "player above gun");
});

test("7. intentional Action/Modifiers overlap is preserved", () => {
  const action = resolveModuleRect("action", { mode: "default" }, RW, RH);
  const mods = resolveModuleRect("modifiers", { mode: "default" }, RW, RH);
  assert.ok(rectsOverlap(action, mods), "action and modifiers must overlap");
  assert.ok(DEFAULT_HUD_LAYOUT_V2.action.zIndex > DEFAULT_HUD_LAYOUT_V2.modifiers.zIndex, "action above modifiers");
  assert.ok(action.width > mods.width, "action wider than modifiers");
});

test("8. reset returns the exact default layout", () => {
  const reset = resetLayoutState();
  assert.deepEqual(reset, defaultLayoutState());
  assert.equal(reset.version, 2);
  for (const id of HUD_MODULE_IDS) assert.equal(reset.modules[id].mode, "default");
});

test("9. invalid v2 localStorage payload falls back to default", () => {
  assert.equal(validateLayoutState({ version: 1, modules: {} }), null); // wrong version
  assert.equal(validateLayoutState("nope"), null);
  assert.deepEqual(readStoredLayout(fakeStorage({ [LAYOUT_STORAGE_KEY]: "{bad json" })), defaultLayoutState());
  assert.deepEqual(readStoredLayout(fakeStorage({})), defaultLayoutState());
  // legacy v1 key must not corrupt v2 read
  assert.deepEqual(readStoredLayout(fakeStorage({ "odyssey.hud.placement.v1": '{"mode":"custom","x":0.5,"y":0.5}' })), defaultLayoutState());
});

test("10. save/cancel draft logic", () => {
  const base = defaultLayoutState();
  let draft = base;
  draft = setModulePlacement(draft, "gun", { mode: "custom", x: 0.8, y: 0.2 });
  // cancel → base unchanged
  assert.deepEqual(cancelDraft(base).modules.gun, { mode: "default", x: 0, y: 0 });
  // commit → draft applied
  const saved = commitDraft(draft);
  assert.deepEqual(saved.modules.gun, { mode: "custom", x: 0.8, y: 0.2 });
  // other modules untouched
  assert.equal(saved.modules.player.mode, "default");
  // round-trips through storage
  const store = fakeStorage();
  writeStoredLayout(store, saved);
  assert.deepEqual(readStoredLayout(store), saved);
});

test("11. collapse/reopen preserves module layout (storage survives)", () => {
  const store = fakeStorage();
  let layout = setModulePlacement(defaultLayoutState(), "log", { mode: "custom", x: 0.1, y: 0.9 });
  layout = setModulePlacement(layout, "skills", { mode: "custom", x: 0.4, y: 0.3 });
  writeStoredLayout(store, layout);
  // simulate collapse (no write) then reopen (read)
  const restored = readStoredLayout(store);
  assert.deepEqual(restored.modules.log, { mode: "custom", x: 0.1, y: 0.9 });
  assert.deepEqual(restored.modules.skills, { mode: "custom", x: 0.4, y: 0.3 });
});

test("12. skills: ≤10 in row 1, 11+ wrap to a second row; snap helper", () => {
  const ten = Array.from({ length: 10 }, (_, i) => i);
  assert.equal(splitSkillRows(ten).length, 1);
  assert.equal(splitSkillRows(ten)[0].length, 10);
  const eleven = Array.from({ length: 11 }, (_, i) => i);
  const rows = splitSkillRows(eleven);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].length, 10);
  assert.equal(rows[1].length, 1);
  // snap-to-grid sanity
  assert.equal(snapToGrid(13, 8), 16);
  assert.equal(snapToGrid(3, 8), 0);
});

console.log(`\n${passed} passed, ${failed} failed\n`);
if (failed > 0) {
  for (const f of failures) {
    console.error(`FAILED: ${f.name}`);
    console.error(f.error);
  }
  process.exit(1);
}
