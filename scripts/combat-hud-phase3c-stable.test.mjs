import assert from "node:assert/strict";

import { deriveSelectionState, buildBroadcastPayload } from "../hud/scene/selectionState.js";
import { renderTargetBlock } from "../hud/components/TargetBlock.js";
import { zoneIdToSvgPart } from "../hud/targeting/targetProfiles.js";
import {
  createInitialTargetState,
  applySource,
  startPicking,
  cancelPicking,
  applyResolvedTarget,
  clearTarget,
  selectZone,
  buildTargetingBroadcast,
} from "../hud/targeting/targetSelectionState.js";

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  Promise.resolve()
    .then(fn)
    .then(() => { passed += 1; console.log(`  PASS ${name}`); })
    .catch((err) => { failed += 1; failures.push({ name, err }); console.error(`  FAIL ${name}\n      ${err.message}`); });
}

const PLAYER = { playerId: "p1", role: "PLAYER" };

function minimalBundle() {
  return {
    ok: true,
    character: {
      id: "char-1",
      display_name: "Test Character",
      character_key: "TEST_CHARACTER",
      owner_player_id: "p1",
      owner_player_name: "Alice",
    },
    state: {
      is_alive: true,
      is_conscious: true,
      status_summary: "Alive",
    },
  };
}

function targetBlockState(targeting = {}) {
  return {
    snapshot: { combatSession: { status: "inactive" } },
    ui: { targeting },
  };
}

console.log("\nCombat HUD - Phase 3C stabilization verification\n");

test("zoneIdToSvgPart maps humanoid wire ids to SVG parts", () => {
  assert.equal(zoneIdToSvgPart("HEAD"), "head");
  assert.equal(zoneIdToSvgPart("TORSO"), "torso");
  assert.equal(zoneIdToSvgPart("LEFT_ARM"), "l_arm");
  assert.equal(zoneIdToSvgPart("RIGHT_ARM"), "r_arm");
  assert.equal(zoneIdToSvgPart("LEFT_LEG"), "l_leg");
  assert.equal(zoneIdToSvgPart("RIGHT_LEG"), "r_leg");
  assert.equal(zoneIdToSvgPart("UNKNOWN"), null);
});

test("TargetBlock shows Pick target when no target is selected", () => {
  const html = renderTargetBlock(targetBlockState({ mode: "idle", selectedTargetIds: [], selectedBodyPartId: "TORSO" }));
  assert.ok(html.includes("Pick target"));
  assert.ok(html.includes('data-action="pick-target"'));
});

test("TargetBlock shows Cancel while picking", () => {
  const html = renderTargetBlock(targetBlockState({ mode: "picking", selectedTargetIds: [], selectedBodyPartId: "TORSO" }));
  assert.ok(html.includes("PICK A TARGET"));
  assert.ok(html.includes('data-action="cancel-target"'));
});

test("TargetBlock shows 6 zone chips and clear button for selected target", () => {
  const html = renderTargetBlock(targetBlockState({
    mode: "idle",
    selectedTargetIds: ["tok-target"],
    selectedTargetName: "Target NPC",
    selectedBodyPartId: "TORSO",
    distance: 6,
  }));
  const zoneButtonCount = (html.match(/data-action="select-target-zone"/g) ?? []).length;
  assert.equal(zoneButtonCount, 6);
  assert.ok(html.includes('data-action="clear-target"'));
  assert.ok(html.includes("Target NPC"));
  assert.ok(html.includes("is-selected"));
});

test("activeIntent: no prepared action defaults to weapon-attack", () => {
  const state = deriveSelectionState({
    viewer: PLAYER,
    selectionIds: ["tok-1"],
    link: { characterId: "char-1" },
    bundle: minimalBundle(),
  });
  const payload = buildBroadcastPayload(state);
  assert.equal(payload.ui.activeIntent.kind, "weapon-attack");
  assert.equal(payload.ui.activeIntent.weaponId, null);
});

test("activeIntent: selected weapon is reflected in payload", () => {
  const state = deriveSelectionState({
    viewer: PLAYER,
    selectionIds: ["tok-1"],
    link: { characterId: "char-1" },
    bundle: minimalBundle(),
  });
  const payload = buildBroadcastPayload(state, { selectedWeaponId: "weapon-42" });
  assert.equal(payload.ui.activeIntent.kind, "weapon-attack");
  assert.equal(payload.ui.activeIntent.weaponId, "weapon-42");
});

test("activeIntent: prepared skill overrides weapon attack", () => {
  const state = deriveSelectionState({
    viewer: PLAYER,
    selectionIds: ["tok-1"],
    link: { characterId: "char-1" },
    bundle: minimalBundle(),
  });
  const payload = buildBroadcastPayload(state, {
    selectedWeaponId: "weapon-42",
    preparedAction: { kind: "skill", id: "ability-1" },
    activeIntent: { kind: "skill", id: "ability-1" },
  });
  assert.equal(payload.ui.activeIntent.kind, "skill");
  assert.equal(payload.ui.activeIntent.id, "ability-1");
});

test("selectZone updates selectedZoneId when a target exists", () => {
  const source = applySource(createInitialTargetState(), {
    tokenId: "tok-source",
    characterId: "char-source",
    characterName: "Source",
  });
  const resolved = applyResolvedTarget(source, {
    tokenId: "tok-target",
    characterId: "char-target",
    displayName: "Target",
    profileId: "humanoid",
  });
  const updated = selectZone(resolved, "HEAD");
  assert.equal(updated.target.selectedZoneId, "HEAD");
});

test("selectZone is ignored when no target exists", () => {
  const state = createInitialTargetState();
  const updated = selectZone(state, "HEAD");
  assert.equal(updated, state);
});

test("clearTarget removes the target and returns idle", () => {
  const source = applySource(createInitialTargetState(), {
    tokenId: "tok-source",
    characterId: "char-source",
    characterName: "Source",
  });
  const resolved = applyResolvedTarget(source, {
    tokenId: "tok-target",
    characterId: "char-target",
    displayName: "Target",
    profileId: "humanoid",
  });
  const cleared = clearTarget(resolved);
  assert.equal(cleared.mode, "idle");
  assert.equal(cleared.target, null);
});

test("cancelPicking preserves the previously selected target", () => {
  const source = applySource(createInitialTargetState(), {
    tokenId: "tok-source",
    characterId: "char-source",
    characterName: "Source",
  });
  const resolved = applyResolvedTarget(source, {
    tokenId: "tok-target",
    characterId: "char-target",
    displayName: "Target",
    profileId: "humanoid",
  });
  const picking = startPicking(resolved);
  const canceled = cancelPicking(picking);
  assert.equal(canceled.mode, "idle");
  assert.equal(canceled.target.tokenId, "tok-target");
});

test("buildTargetingBroadcast keeps source and target after resolve", () => {
  const source = applySource(createInitialTargetState(), {
    tokenId: "tok-source",
    characterId: "char-source",
    characterName: "Source",
  });
  const resolved = applyResolvedTarget(source, {
    tokenId: "tok-target",
    characterId: "char-target",
    displayName: "Target NPC",
    profileId: "humanoid",
    distance: { value: 6, unit: "m" },
  });
  const wire = buildTargetingBroadcast(resolved);
  assert.equal(wire.source.tokenId, "tok-source");
  assert.equal(wire.target.tokenId, "tok-target");
  assert.equal(wire.target.selectedZoneId, "TORSO");
});

setTimeout(() => {
  console.log(`\n${passed} passed, ${failed} failed\n`);
  if (failed > 0) {
    for (const f of failures) {
      console.error(`FAILED: ${f.name}`);
      console.error(f.err);
    }
    process.exit(1);
  }
}, 400);
