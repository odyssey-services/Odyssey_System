import assert from "node:assert/strict";
import { createTestSuite } from "./_tinyTestRunner.mjs";
import { fixtureSet } from "./_fixtures.mjs";
import { findByCode } from "./_assertions.mjs";
import { reconcileCharacterAbilities } from "./_mockAdapters.mjs";

const { test, run } = createTestSuite("Unit — Items / Equipment → Abilities");
const fx = fixtureSet();

test("item grants ability", () => {
  const result = reconcileCharacterAbilities({
    character: fx.characters.testAttacker,
    items: [fx.items.medkit],
    abilityDefs: Object.values(fx.abilities),
    abilityGrants: [fx.abilityGrants.firstAidItem],
  });
  assert.equal(findByCode(result.abilities, "first_aid").source_character_item_id, fx.items.medkit.id);
});

test("spent or removed item hides ability", () => {
  const first = reconcileCharacterAbilities({
    character: fx.characters.testAttacker,
    items: [fx.items.medkit],
    abilityDefs: Object.values(fx.abilities),
    abilityGrants: [fx.abilityGrants.firstAidItem],
  });
  const second = reconcileCharacterAbilities({
    character: fx.characters.testAttacker,
    items: [],
    abilityDefs: Object.values(fx.abilities),
    abilityGrants: [fx.abilityGrants.firstAidItem],
    existingCharacterAbilities: first.abilities,
  });
  assert.equal(findByCode(second.abilities, "first_aid").data.source_removed_reason, "missing_item");
});

test("equipment ability works only when equipped", () => {
  const hidden = reconcileCharacterAbilities({
    character: fx.characters.testAttacker,
    items: [{ ...fx.items.shieldEmitter, is_equipped: false }],
    abilityDefs: Object.values(fx.abilities),
    abilityGrants: [fx.abilityGrants.shieldPulseEquipment],
  });
  assert.equal(hidden.abilities.length, 0);

  const visible = reconcileCharacterAbilities({
    character: fx.characters.testAttacker,
    items: [{ ...fx.items.shieldEmitter, is_equipped: true }],
    abilityDefs: Object.values(fx.abilities),
    abilityGrants: [fx.abilityGrants.shieldPulseEquipment],
  });
  assert.ok(findByCode(visible.abilities, "shield_pulse"));
});

await run();

