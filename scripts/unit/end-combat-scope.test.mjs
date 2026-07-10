import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { createTestSuite } from "./_tinyTestRunner.mjs";
import { endCombatScopeMock } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit - End Combat Scope");

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");
const sql117 = fs.readFileSync(path.join(repoRoot, "supabase", "117_end_combat_scene_scope.sql"), "utf8");

function baseEncounters() {
  return [
    { id: "enc-a", status: "active", campaign_id: "camp-1", room_id: "room-1", scene_id: "scene-1", active_entry_id: "ia", active_character_id: "char-a" },
    { id: "enc-b", status: "active", campaign_id: "camp-1", room_id: "room-1", scene_id: "scene-1", active_entry_id: "ib", active_character_id: "char-b" },
    { id: "enc-c", status: "active", campaign_id: "camp-1", room_id: "room-1", scene_id: "scene-2", active_entry_id: "ic", active_character_id: "char-c" },
    { id: "enc-d", status: "finished", campaign_id: "camp-1", room_id: "room-1", scene_id: "scene-1", active_entry_id: null, active_character_id: null, ended_at: "2026-07-09T00:00:00.000Z" },
  ];
}

function baseEntries() {
  return [
    { id: "ia", encounter_id: "enc-a", is_active: true },
    { id: "ib", encounter_id: "enc-b", is_active: true },
    { id: "ic", encounter_id: "enc-c", is_active: true },
    { id: "id", encounter_id: "enc-d", is_active: false },
  ];
}

test("scope=encounter closes only target encounter", () => {
  const result = endCombatScopeMock({
    encounters: baseEncounters(),
    initiativeEntries: baseEntries(),
    targetEncounterId: "enc-a",
    scope: "encounter",
  });
  assert.deepEqual(result.ended_encounter_ids, ["enc-a"]);
  assert.equal(result.ended_count, 1);
});

test("scope=scene closes all active encounters in the same scene", () => {
  const result = endCombatScopeMock({
    encounters: baseEncounters(),
    initiativeEntries: baseEntries(),
    targetEncounterId: "enc-a",
    scope: "scene",
  });
  assert.deepEqual(result.ended_encounter_ids.sort(), ["enc-a", "enc-b"]);
  assert.equal(result.ended_count, 2);
});

test("scope=room closes all active encounters in the same room", () => {
  const result = endCombatScopeMock({
    encounters: baseEncounters(),
    initiativeEntries: baseEntries(),
    targetEncounterId: "enc-a",
    scope: "room",
  });
  assert.deepEqual(result.ended_encounter_ids.sort(), ["enc-a", "enc-b", "enc-c"]);
  assert.equal(result.ended_count, 3);
});

test("non-GM actor is denied", () => {
  const result = endCombatScopeMock({
    encounters: baseEncounters(),
    initiativeEntries: baseEntries(),
    targetEncounterId: "enc-a",
    scope: "scene",
    actorIsGm: false,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "CONTROL_DENIED");
});

test("initiative entries are deactivated for ended encounters", () => {
  const result = endCombatScopeMock({
    encounters: baseEncounters(),
    initiativeEntries: baseEntries(),
    targetEncounterId: "enc-a",
    scope: "scene",
  });
  assert.equal(result.deactivated_entries_count, 2);
  assert.ok(result.initiativeEntries.filter((entry) => ["enc-a", "enc-b"].includes(entry.encounter_id)).every((entry) => entry.is_active === false));
});

test("ended encounters are preserved as history rows", () => {
  const result = endCombatScopeMock({
    encounters: baseEncounters(),
    initiativeEntries: baseEntries(),
    targetEncounterId: "enc-a",
    scope: "scene",
  });
  assert.equal(result.encounters.length, 4);
  assert.ok(result.encounters.find((entry) => entry.id === "enc-a")?.ended_at);
});

test("return contract includes ended ids, counts, and deactivated entry count", () => {
  const result = endCombatScopeMock({
    encounters: baseEncounters(),
    initiativeEntries: baseEntries(),
    targetEncounterId: "enc-a",
    scope: "scene",
  });
  assert.ok(Array.isArray(result.ended_encounter_ids));
  assert.equal(typeof result.ended_count, "number");
  assert.equal(typeof result.deactivated_entries_count, "number");
});

test("migration 117 contains scene and room scope logic", () => {
  assert.ok(sql117.includes("'scene'"), "scene scope exists in migration");
  assert.ok(sql117.includes("'room'"), "room scope exists in migration");
  assert.ok(sql117.includes("ended_encounter_ids"), "return contract includes ended ids");
});

await run();
