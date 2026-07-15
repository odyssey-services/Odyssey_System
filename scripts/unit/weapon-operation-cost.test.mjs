import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { createTestSuite } from "./_tinyTestRunner.mjs";
import { applyWeaponOperationCostMock } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit - Weapon Operation Cost");
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const supabaseSql = fs.readFileSync(
  path.resolve(__dirname, "..", "..", "supabase", "odyssey_supabase.sql"),
  "utf8",
);

function activeParticipation(overrides = {}) {
  return {
    encounter_id: "enc-1",
    encounter_state_version: 7,
    is_current_turn: true,
    move_current: 10,
    move_max: 10,
    ...overrides,
  };
}

test("no active participation returns ok with no cost spent", () => {
  const result = applyWeaponOperationCostMock({ participation: null });
  assert.equal(result.ok, true);
  assert.equal(result.spent, false);
  assert.equal(result.combat_session, null);
});

test("current turn with full move available spends move", () => {
  const result = applyWeaponOperationCostMock({
    participation: activeParticipation(),
  });
  assert.equal(result.ok, true);
  assert.equal(result.spent, true);
  assert.equal(result.participation?.move_current, 0);
});

test("partial move blocks full-move weapon operation", () => {
  const result = applyWeaponOperationCostMock({
    participation: activeParticipation({ move_current: 4 }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "FULL_MOVE_NOT_AVAILABLE");
});

test("not current turn blocks weapon operation", () => {
  const result = applyWeaponOperationCostMock({
    participation: activeParticipation({ is_current_turn: false }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "NOT_CURRENT_TURN");
});

test("expected session version mismatch returns state conflict", () => {
  const result = applyWeaponOperationCostMock({
    participation: activeParticipation({ encounter_state_version: 9 }),
    expectedSessionVersion: 7,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "STATE_VERSION_CONFLICT");
  assert.equal(result.spent, false);
});

test("ambiguous combat context blocks operation and spends nothing", () => {
  const result = applyWeaponOperationCostMock({
    participation: [
      activeParticipation({ encounter_id: "enc-a" }),
      activeParticipation({ encounter_id: "enc-b" }),
    ],
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "COMBAT_CONTEXT_AMBIGUOUS");
  assert.equal(result.spent, false);
});

test("sql bundle keeps only the 5-argument weapon-operation cost helper", () => {
  assert.equal(
    (supabaseSql.match(/create or replace function public\.odyssey_apply_weapon_operation_session_cost\(/g) ?? []).length,
    1,
  );
  assert.ok(
    supabaseSql.includes("drop function if exists public.odyssey_apply_weapon_operation_session_cost(\n  uuid,\n  text,\n  text,\n  integer\n);"),
  );
});

await run();
