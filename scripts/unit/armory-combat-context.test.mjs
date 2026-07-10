import assert from "node:assert/strict";

import { createTestSuite } from "./_tinyTestRunner.mjs";
import { fixtureSet } from "./_fixtures.mjs";
import { buildArmoryCombatContextMock } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit - Armory Combat Context");
const fx = fixtureSet();

function weapons() {
  return [
    { id: fx.characterWeapons.katanaEquipped.id, name: "Unarmed", equipped_slot: "primary" },
    { id: fx.characterWeapons.pistolLoaded.id, name: "Standard Rifle", equipped_slot: null },
  ];
}

function activeEncounter(overrides = {}) {
  return {
    id: "enc-1",
    status: "active",
    participant: {
      character_id: fx.characters.testAttacker.id,
      is_current_turn: true,
      move_current: 10,
      move_max: 10,
    },
    ...overrides,
  };
}

test("no active encounter produces out-of-combat context", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [],
  });
  assert.equal(result.combat_context.mode, "out_of_combat");
  assert.equal(result.combat_context.encounter_id, null);
  assert.equal(result.combat_context.move_current, null);
  assert.equal(result.combat_context.move_max, null);
});

test("single active encounter produces single_active context", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [activeEncounter()],
  });
  assert.equal(result.combat_context.mode, "single_active");
  assert.equal(result.combat_context.encounter_id, "enc-1");
});

test("valid explicit encounter produces explicit mode", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [activeEncounter()],
    explicitEncounterId: "enc-1",
  });
  assert.equal(result.combat_context.mode, "explicit");
  assert.equal(result.combat_context.encounter_id, "enc-1");
});

test("missing explicit encounter produces explicit_missing warning", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [activeEncounter()],
    explicitEncounterId: "enc-x",
  });
  assert.equal(result.combat_context.mode, "explicit_missing");
  assert.match(result.combat_context.warning ?? "", /Explicit encounter/i);
  assert.equal(result.combat_context.move_current, null);
});

test("multiple active encounters without explicit id produce ambiguous context", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [
      activeEncounter({ id: "enc-1" }),
      activeEncounter({ id: "enc-2" }),
    ],
  });
  assert.equal(result.combat_context.mode, "ambiguous");
  assert.equal(result.combat_context.active_encounter_count, 2);
  assert.match(result.combat_context.warning ?? "", /Multiple active encounters/i);
});

test("out-of-combat weapon switch stays enabled", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    weapons: weapons(),
  });
  const rifle = result.weapons.find((weapon) => weapon.id === fx.characterWeapons.pistolLoaded.id);
  assert.equal(rifle?.can_switch_to, true);
  assert.equal(rifle?.switch_block_reason, null);
});

test("in combat and not current turn blocks weapon switch", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [activeEncounter({ participant: { character_id: fx.characters.testAttacker.id, is_current_turn: false, move_current: 10, move_max: 10 } })],
    weapons: weapons(),
  });
  const rifle = result.weapons.find((weapon) => weapon.id === fx.characterWeapons.pistolLoaded.id);
  assert.equal(rifle?.can_switch_to, false);
  assert.equal(rifle?.switch_block_reason, "Waiting for your turn");
});

test("in combat with move spent blocks weapon switch", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [activeEncounter({ participant: { character_id: fx.characters.testAttacker.id, is_current_turn: true, move_current: 4, move_max: 10 } })],
    weapons: weapons(),
  });
  const rifle = result.weapons.find((weapon) => weapon.id === fx.characterWeapons.pistolLoaded.id);
  assert.equal(rifle?.can_switch_to, false);
  assert.match(rifle?.switch_block_reason ?? "", /FULL MOVE/i);
});

test("in combat with full move available allows weapon switch", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [activeEncounter()],
    weapons: weapons(),
  });
  const rifle = result.weapons.find((weapon) => weapon.id === fx.characterWeapons.pistolLoaded.id);
  assert.equal(rifle?.can_switch_to, true);
});

await run();
