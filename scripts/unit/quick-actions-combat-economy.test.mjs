import assert from "node:assert/strict";

import { createTestSuite } from "./_tinyTestRunner.mjs";
import { buildQuickActionsRuntime } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit - Quick Actions Combat Economy");

function ability(overrides = {}) {
  return {
    id: overrides.id ?? "ability-1",
    code: overrides.code ?? "test_action",
    name: overrides.name ?? "Test Action",
    activation_type: "manual",
    ability_kind: "support",
    target_type: "self",
    effect_mode: "buff",
    ...overrides,
  };
}

test("not current turn blocks execution even when source checks pass", () => {
  const runtime = buildQuickActionsRuntime({
    abilities: [ability({ actionCost: "MAIN" })],
    encounter: { id: "enc-1", status: "active" },
    characterState: { is_current_turn: false, action_current: 1, move_current: 10, move_max: 10 },
  });
  assert.equal(runtime.quickActions[0].state.executionAvailable, false);
  assert.match(runtime.quickActions[0].state.executionReason ?? "", /turn/i);
});

test("main-cost ability is blocked when action_current is zero", () => {
  const runtime = buildQuickActionsRuntime({
    abilities: [ability({ actionCost: "MAIN" })],
    encounter: { id: "enc-1", status: "active" },
    characterState: { is_current_turn: true, action_current: 0, move_current: 10, move_max: 10 },
  });
  assert.equal(runtime.quickActions[0].state.executionAvailable, false);
  assert.match(runtime.quickActions[0].state.executionReason ?? "", /ACTION/i);
});

test("full-move ability is blocked when move is partially spent", () => {
  const runtime = buildQuickActionsRuntime({
    abilities: [ability({ actionCost: "FULL_MOVE" })],
    encounter: { id: "enc-1", status: "active" },
    characterState: { is_current_turn: true, action_current: 1, move_current: 4, move_max: 10 },
  });
  assert.equal(runtime.quickActions[0].state.executionAvailable, false);
  assert.match(runtime.quickActions[0].state.executionReason ?? "", /MOVE/i);
});

test("free utility ability stays executable even with action spent", () => {
  const runtime = buildQuickActionsRuntime({
    abilities: [ability({ actionCost: "FREE" })],
    encounter: { id: "enc-1", status: "active" },
    characterState: { is_current_turn: true, action_current: 0, move_current: 0, move_max: 10 },
  });
  assert.equal(runtime.quickActions[0].state.executionAvailable, true);
  assert.equal(runtime.quickActions[0].state.executionReason, null);
});

test("out of combat execution stays available when source checks pass", () => {
  const runtime = buildQuickActionsRuntime({
    abilities: [ability({ actionCost: "MAIN" })],
    encounter: null,
    characterState: { is_current_turn: false, action_current: 0, move_current: 0, move_max: 10 },
  });
  assert.equal(runtime.quickActions[0].state.executionAvailable, true);
});

await run();
