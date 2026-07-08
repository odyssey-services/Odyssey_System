import assert from "node:assert/strict";
import { createTestSuite } from "./_tinyTestRunner.mjs";
import { fixtureSet } from "./_fixtures.mjs";
import { buildRuntimeBundleMock, reconcileCharacterAbilities } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit — Runtime Bundle Contract");
const fx = fixtureSet();

function readyBundle() {
  const abilities = reconcileCharacterAbilities({
    character: fx.characters.testAttacker,
    skills: [{ id: "skill-row", skill_def_id: fx.skillDefs.ethericCoating.id, level: 1 }],
    weapons: [fx.characterWeapons.katanaEquipped],
    abilityDefs: Object.values(fx.abilities),
    abilityGrants: [fx.abilityGrants.plasmaEdgeWeapon],
  }).abilities;

  return buildRuntimeBundleMock({
    character: fx.characters.testAttacker,
    skills: [{ id: "skill-row", code: "etheric_coating", level: 1 }],
    abilities,
    weapons: [fx.characterWeapons.katanaEquipped],
    combat: { id: "enc-1", round: 1, is_current_turn: true, move_current: 10, move_max: 10 },
    bodyParts: fx.bodyParts.healthy,
  });
}

test("bundle contains character summary", () => {
  const bundle = readyBundle();
  assert.equal(bundle.snapshot.entity.summary.id, fx.characters.testAttacker.id);
  assert.equal(bundle.snapshot.entity.summary.name, fx.characters.testAttacker.name);
});

test("bundle contains skills", () => {
  const bundle = readyBundle();
  assert.equal(bundle.snapshot.skills.length, 1);
});

test("bundle contains abilities", () => {
  const bundle = readyBundle();
  assert.ok(bundle.snapshot.abilities.length >= 1);
});

test("bundle contains weapons", () => {
  const bundle = readyBundle();
  assert.equal(bundle.snapshot.weapons.length, 1);
});

test("bundle contains combat state", () => {
  const bundle = readyBundle();
  assert.equal(bundle.snapshot.combat.encounter_id, "enc-1");
  assert.equal(bundle.snapshot.combat.round, 1);
  assert.equal(bundle.snapshot.combat.move_current, 10);
});

test("hidden abilities are not present in quick actions", () => {
  const bundle = buildRuntimeBundleMock({
    character: fx.characters.testAttacker,
    abilities: [
      { id: "a1", code: "visible", name: "Visible", is_hidden: false, is_enabled: true, activation_type: "manual", ability_kind: "support", target_type: "self", effect_mode: "buff" },
      { id: "a2", code: "hidden", name: "Hidden", is_hidden: true, is_enabled: true, activation_type: "manual", ability_kind: "support", target_type: "self", effect_mode: "buff" },
    ],
  });
  assert.deepEqual(bundle.snapshot.quickActions.map((entry) => entry.code), ["visible"]);
});

await run();

