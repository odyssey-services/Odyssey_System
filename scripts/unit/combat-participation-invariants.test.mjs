import assert from "node:assert/strict";

import { createTestSuite } from "./_tinyTestRunner.mjs";
import { fixtureSet } from "./_fixtures.mjs";
import { enforceSingleActiveParticipationMock } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit - Combat Participation Invariants");
const fx = fixtureSet();

function baseData() {
  return {
    encounters: [
      { id: "enc-old", status: "active", active_entry_id: "entry-old-attacker", active_character_id: fx.characters.testAttacker.id },
      { id: "enc-new", status: "active", active_entry_id: "entry-new-attacker", active_character_id: fx.characters.testAttacker.id },
    ],
    initiativeEntries: [
      { id: "entry-old-attacker", encounter_id: "enc-old", character_id: fx.characters.testAttacker.id, is_active: true },
      { id: "entry-new-attacker", encounter_id: "enc-new", character_id: fx.characters.testAttacker.id, is_active: true },
      { id: "entry-old-target", encounter_id: "enc-old", character_id: fx.characters.testTarget.id, is_active: true },
    ],
  };
}

function activeEncounterIdsByCharacter(entries, characterId) {
  return entries
    .filter((entry) => entry.character_id === characterId && entry.is_active === true)
    .map((entry) => entry.encounter_id);
}

test("duplicate character is deactivated in old encounter when added to new one", () => {
  const data = baseData();
  const result = enforceSingleActiveParticipationMock({
    encounters: data.encounters,
    initiativeEntries: data.initiativeEntries,
    characterIds: [fx.characters.testAttacker.id],
    newEncounterId: "enc-new",
  });
  const oldEntry = result.initiativeEntries.find((entry) => entry.id === "entry-old-attacker");
  const newEntry = result.initiativeEntries.find((entry) => entry.id === "entry-new-attacker");
  assert.equal(oldEntry?.is_active, false);
  assert.equal(newEntry?.is_active, true);
});

test("empty old encounter is finished and timestamped", () => {
  const result = enforceSingleActiveParticipationMock({
    encounters: [{ id: "enc-old", status: "active", active_entry_id: "entry-old-attacker", active_character_id: fx.characters.testAttacker.id }],
    initiativeEntries: [
      { id: "entry-old-attacker", encounter_id: "enc-old", character_id: fx.characters.testAttacker.id, is_active: true },
      { id: "entry-new-attacker", encounter_id: "enc-new", character_id: fx.characters.testAttacker.id, is_active: true },
    ],
    characterIds: [fx.characters.testAttacker.id],
    newEncounterId: "enc-new",
  });
  const oldEncounter = result.encounters.find((entry) => entry.id === "enc-old");
  assert.equal(oldEncounter?.status, "finished");
  assert.ok(oldEncounter?.ended_at);
});

test("old encounter with other active participants remains active", () => {
  const data = baseData();
  const result = enforceSingleActiveParticipationMock({
    encounters: data.encounters,
    initiativeEntries: data.initiativeEntries,
    characterIds: [fx.characters.testAttacker.id],
    newEncounterId: "enc-new",
  });
  const oldEncounter = result.encounters.find((entry) => entry.id === "enc-old");
  const targetEntry = result.initiativeEntries.find((entry) => entry.id === "entry-old-target");
  assert.equal(oldEncounter?.status, "active");
  assert.equal(targetEntry?.is_active, true);
});

test("old active pointers are cleared when they point to removed character", () => {
  const result = enforceSingleActiveParticipationMock({
    encounters: [{ id: "enc-old", status: "active", active_entry_id: "entry-old-attacker", active_character_id: fx.characters.testAttacker.id }],
    initiativeEntries: [
      { id: "entry-old-attacker", encounter_id: "enc-old", character_id: fx.characters.testAttacker.id, is_active: true },
      { id: "entry-new-attacker", encounter_id: "enc-new", character_id: fx.characters.testAttacker.id, is_active: true },
    ],
    characterIds: [fx.characters.testAttacker.id],
    newEncounterId: "enc-new",
  });
  const oldEncounter = result.encounters.find((entry) => entry.id === "enc-old");
  assert.equal(oldEncounter?.active_entry_id, null);
  assert.equal(oldEncounter?.active_character_id, null);
});

test("after enforcement no character stays active in more than one active encounter", () => {
  const data = baseData();
  const result = enforceSingleActiveParticipationMock({
    encounters: data.encounters,
    initiativeEntries: data.initiativeEntries,
    characterIds: [fx.characters.testAttacker.id],
    newEncounterId: "enc-new",
  });
  const activeEncounterIds = activeEncounterIdsByCharacter(result.initiativeEntries, fx.characters.testAttacker.id);
  assert.deepEqual(activeEncounterIds, ["enc-new"]);
});

await run();
