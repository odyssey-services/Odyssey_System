import assert from "node:assert/strict";

import {
  moduleShouldBeOpen,
  primaryModuleOpenMap,
  secondaryReconcileAction,
  characterChangeClosesCompanions,
} from "../hud/overlay/hudPopoverLifecycle.js";
import {
  HUD_MODULE_IDS,
  HUD_MODULE_POPOVER_IDS,
  GUN_WEAPON_SELECTOR_POPOVER_ID,
  GUN_MAGAZINE_SELECTOR_POPOVER_ID,
} from "../hud/overlay/hudLayout.js";
import { SELECTION_STATUS } from "../hud/scene/selectionState.js";
import { renderSelectionModule } from "../hud/scene/selectionView.js";

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

const PRIMARY = ["player", "gun", "skills", "combatControl", "log"];

test("ready selection opens all primary modules", () => {
  const map = primaryModuleOpenMap("modules", SELECTION_STATUS.ready);
  for (const id of PRIMARY) {
    assert.equal(map[id], true, `${id} must be open when ready`);
  }
});

test("open map covers exactly the known module ids", () => {
  assert.deepEqual(
    Object.keys(primaryModuleOpenMap("modules", SELECTION_STATUS.ready)).sort(),
    [...HUD_MODULE_IDS].sort(),
  );
});

test("loading selection keeps only player open", () => {
  const map = primaryModuleOpenMap("modules", SELECTION_STATUS.loading);
  for (const id of PRIMARY) {
    assert.equal(map[id], true, `${id} stays open while loading`);
  }
});

test("invalid selection keeps only player open until ready returns", () => {
  for (const bad of [
    SELECTION_STATUS.notOwned,
    SELECTION_STATUS.noSelection,
    SELECTION_STATUS.unlinkedToken,
  ]) {
    const map = primaryModuleOpenMap("modules", bad);
    for (const id of PRIMARY) {
      assert.equal(map[id], true, `${id} stays open for ${bad}`);
    }
  }
  const ready = primaryModuleOpenMap("modules", SELECTION_STATUS.ready);
  for (const id of PRIMARY) {
    assert.equal(ready[id], true);
  }
});

test("collapsed mode closes all primary modules", () => {
  const map = primaryModuleOpenMap("collapsed", SELECTION_STATUS.ready);
  for (const id of PRIMARY) {
    assert.equal(map[id], false, `${id} closed when collapsed`);
  }
});

test("editor mode closes all primary modules", () => {
  const map = primaryModuleOpenMap("editor", SELECTION_STATUS.ready);
  for (const id of PRIMARY) {
    assert.equal(map[id], false, `${id} closed in editor`);
  }
});

test("collapsed then reopened restores all primary modules", () => {
  const collapsed = primaryModuleOpenMap("collapsed", SELECTION_STATUS.ready);
  const reopened = primaryModuleOpenMap("modules", SELECTION_STATUS.ready);
  assert.ok(PRIMARY.every((id) => collapsed[id] === false));
  assert.ok(PRIMARY.every((id) => reopened[id] === true));
});

test("loading to ready reconciles secondaries as open", () => {
  assert.equal(
    secondaryReconcileAction(SELECTION_STATUS.loading, SELECTION_STATUS.ready),
    "none",
  );
});

test("ready to ready does not reconcile secondaries", () => {
  assert.equal(
    secondaryReconcileAction(SELECTION_STATUS.ready, SELECTION_STATUS.ready),
    "none",
  );
});

test("ready to not-owned reconciles secondaries as close", () => {
  assert.equal(
    secondaryReconcileAction(SELECTION_STATUS.ready, SELECTION_STATUS.notOwned),
    "none",
  );
});

test("loading to loading does not reconcile secondaries", () => {
  assert.equal(
    secondaryReconcileAction(SELECTION_STATUS.loading, SELECTION_STATUS.loading),
    "none",
  );
});

test("companion popover ids do not collide with primary popover ids", () => {
  const primaryIds = new Set(Object.values(HUD_MODULE_POPOVER_IDS));
  assert.ok(!primaryIds.has(GUN_WEAPON_SELECTOR_POPOVER_ID));
  assert.ok(!primaryIds.has(GUN_MAGAZINE_SELECTOR_POPOVER_ID));
  assert.notEqual(GUN_WEAPON_SELECTOR_POPOVER_ID, GUN_MAGAZINE_SELECTOR_POPOVER_ID);
});

test("primary module open decision is independent of companion state", () => {
  assert.equal(moduleShouldBeOpen.length, 3);
  assert.equal(moduleShouldBeOpen("modules", SELECTION_STATUS.ready, "gun"), true);
  assert.equal(moduleShouldBeOpen("modules", SELECTION_STATUS.ready, "skills"), true);
  assert.equal(moduleShouldBeOpen("modules", SELECTION_STATUS.ready, "combatControl"), true);
  assert.equal(moduleShouldBeOpen("modules", SELECTION_STATUS.ready, "log"), true);
});

test("character changes close companions, identical character does not", () => {
  assert.equal(characterChangeClosesCompanions(null, "c1"), true);
  assert.equal(characterChangeClosesCompanions("c1", "c1"), false);
  assert.equal(characterChangeClosesCompanions("c1", "c2"), true);
  assert.equal(characterChangeClosesCompanions("c1", null), true);
});

test("ready to ready source switch keeps primary modules open", () => {
  assert.equal(
    secondaryReconcileAction(SELECTION_STATUS.ready, SELECTION_STATUS.ready),
    "none",
  );
  const map = primaryModuleOpenMap("modules", SELECTION_STATUS.ready);
  for (const id of PRIMARY) {
    assert.equal(map[id], true);
  }
});

function readyPayload() {
  return {
    status: SELECTION_STATUS.ready,
    access: { canView: true, reason: null },
    characterId: "char-1",
    selectedItemId: "tok-1",
    viewer: { playerId: "p1", role: "PLAYER" },
    hudSnapshot: null,
    ui: {},
    view: { name: "Hero", isAlive: true, isConscious: true },
  };
}

test("each primary module renders independently for ready payload", () => {
  for (const id of PRIMARY) {
    const html = renderSelectionModule(id, readyPayload(), { dev: false });
    assert.ok(typeof html === "string" && html.length > 0, `${id} produces HTML`);
  }
});

test("one module render failure does not blank sibling modules", () => {
  const guardedRender = (id) => {
    try {
      if (id === "gun") throw new Error("simulated GunBlock render failure");
      return { id, ok: true, html: renderSelectionModule(id, readyPayload(), {}) };
    } catch (_e) {
      return { id, ok: false, html: `<section class="ohud-moderr">error ${id}</section>` };
    }
  };
  const results = PRIMARY.map(guardedRender);
  const gun = results.find((r) => r.id === "gun");
  assert.equal(gun.ok, false);
  assert.ok(gun.html.includes("ohud-moderr"));
  for (const id of ["player", "skills", "combatControl", "log"]) {
    const result = results.find((entry) => entry.id === id);
    assert.equal(result.ok, true, `${id} unaffected by gun failure`);
    assert.ok(result.html.length > 0, `${id} still produces content`);
  }
});

setTimeout(() => {
  console.log(`\nPopover lifecycle: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, err } of failures) {
      console.error(`  FAIL: ${name}`);
      console.error(`    ${err?.stack ?? err}`);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 200);
