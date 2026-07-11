import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { buildSwitchActiveWeaponPayload, resolveWeaponSwitchErrorMessage } from "../hud/session/weaponSwitchPayload.js";
import { buildArmoryCombatContextMock } from "./unit/_mockAdapters.mjs";
import { fixtureSet } from "./unit/_fixtures.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const sceneControllerSrc = fs.readFileSync(path.join(repoRoot, "hud", "scene", "sceneSelectionController.js"), "utf8");
const overlayPageSrc = fs.readFileSync(path.join(repoRoot, "hud", "overlay", "combatHudOverlayPage.js"), "utf8");
const sqlSrc = fs.readFileSync(path.join(repoRoot, "supabase", "odyssey_supabase.sql"), "utf8");
const fx = fixtureSet();

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  PASS ${name}`);
  } catch (error) {
    failed += 1;
    failures.push({ name, error });
    console.error(`  FAIL ${name}\n      ${error.message}`);
  }
}

console.log("\nWeapon Switch Command\n");

test("payload includes encounter_id in combat", () => {
  const payload = buildSwitchActiveWeaponPayload({
    characterId: "char-1",
    weaponId: "weapon-1",
    session: { exists: true, id: "enc-1" },
  });
  assert.equal(payload.encounter_id, "enc-1");
});

test("payload includes expected encounter version in combat", () => {
  const payload = buildSwitchActiveWeaponPayload({
    characterId: "char-1",
    weaponId: "weapon-1",
    session: { exists: true, id: "enc-1", version: 12 },
  });
  assert.equal(payload.expected_encounter_version, 12);
});

test("out-of-combat payload omits encounter fields", () => {
  const payload = buildSwitchActiveWeaponPayload({
    characterId: "char-1",
    weaponId: "weapon-1",
    session: null,
  });
  assert.ok(!("encounter_id" in payload));
  assert.ok(!("expected_encounter_version" in payload));
});

test("successful switch flow refreshes combat session and runtime quickbar", () => {
  assert.ok(sceneControllerSrc.includes('await refreshCombatSessionSafe(sessionController, "weapon-switched");'));
  assert.ok(sceneControllerSrc.includes('await refreshSelectedCharacterRuntime("weapon-switched", { refreshQuickbar: true });'));
});

test("successful switch flow does not regress to publishState ReferenceError", () => {
  assert.ok(!sceneControllerSrc.includes("publishState is not defined"));
  assert.ok(sceneControllerSrc.includes('logDebugEvent("weapon", "switch_active_weapon:success"'));
  assert.ok(sceneControllerSrc.includes('await refreshHeavyCharacterData(characterIdAtRequest, {'));
  assert.ok(sceneControllerSrc.includes("function publishCurrentState("));
  assert.ok(sceneControllerSrc.includes("function replayLastVisibleState("));
  assert.ok(sceneControllerSrc.includes('publishCurrentState("weapon-switched");'));
});

test("weapon switch and reload keep HUD interaction sticky while commands are in flight", () => {
  assert.ok(sceneControllerSrc.includes("ephemeral.weaponSwitchInFlight = true;"));
  assert.ok(sceneControllerSrc.includes("ephemeral.weaponSwitchInFlight = false;"));
  assert.ok(sceneControllerSrc.includes("ephemeral.magazineSelectorOpen = false;"));
  assert.ok(sceneControllerSrc.includes('if (type === "toggle-magazine-selector") {'));
  assert.ok(sceneControllerSrc.includes("ephemeral.reloadInFlight = true;"));
  assert.ok(sceneControllerSrc.includes("ephemeral.reloadInFlight = false;"));
  assert.ok(sceneControllerSrc.includes("ephemeral.fireModeInFlight = true;"));
  assert.ok(sceneControllerSrc.includes("ephemeral.fireModeInFlight = false;"));
});

test("weapon switch separates RPC failures from UI update failures and ignores stale reselection results", () => {
  assert.ok(sceneControllerSrc.includes('logDebugEvent("weapon", "switch_active_weapon:ui-update-error"'));
  assert.ok(sceneControllerSrc.includes('publishCurrentState("weapon-switch-rpc-failed");'));
  assert.ok(sceneControllerSrc.includes('publishCurrentState("weapon-switch-server-failed");'));
  assert.ok(sceneControllerSrc.includes('publishCurrentState("weapon-switch-ui-update-error");'));
  assert.ok(sceneControllerSrc.includes('logDebugEvent("weapon", "switch_active_weapon:stale-result-ignored"'));
  assert.ok(sceneControllerSrc.includes("function isCurrentSource(characterId, selectedItemId)"));
});

test("popover modules log payload receipt instead of relying on remounts", () => {
  assert.ok(overlayPageSrc.includes("function logPayloadReceived(moduleId, payload, reason = \"broadcast\")"));
  assert.ok(overlayPageSrc.includes('console.info("[combatHud/popover] payload-received"'));
  assert.ok(overlayPageSrc.includes('logPayloadReceived(moduleParam, lastSelectionPayload, "broadcast");'));
  assert.ok(overlayPageSrc.includes('logPayloadReceived(moduleParam, rawPayload, "broadcast");'));
  assert.ok(overlayPageSrc.includes("status: payload?.status ?? null"));
});

test("combat runtime pending is safely published, auto-cleared, and never blocks forever", () => {
  assert.ok(sceneControllerSrc.includes("const COMBAT_RUNTIME_PENDING_MAX_MS = 5000;"));
  assert.ok(sceneControllerSrc.includes("let combatRuntimePendingTimer = null;"));
  assert.ok(sceneControllerSrc.includes("let publishCurrentStateSafe = () => null;"));
  assert.ok(sceneControllerSrc.includes('logDebugEvent("session", "runtime-sync-force-cleared"'));
  assert.ok(sceneControllerSrc.includes('logDebugEvent("session", "runtime-sync-publish-error"'));
  assert.ok(sceneControllerSrc.includes('publishCurrentStateSafe(normalized ? "runtime-sync-pending" : "runtime-sync-ready")'));
  assert.ok(sceneControllerSrc.includes('publishCurrentStateSafe("runtime-sync-force-cleared")'));
  assert.ok(sceneControllerSrc.includes("publishCurrentStateSafe = publishCurrentState;"));
  assert.ok(sceneControllerSrc.includes('publishCurrentState("command-blocked:combat-sync")'));
  assert.ok(sceneControllerSrc.includes('logDebugEvent("selection", "runtime-refresh-exception"'));
});

test("weapon switch is no longer tied to move spending", () => {
  const result = buildArmoryCombatContextMock({
    characterId: fx.characters.testAttacker.id,
    activeEncounters: [{
      id: "enc-1",
      status: "active",
      participant: {
        character_id: fx.characters.testAttacker.id,
        is_current_turn: true,
        move_current: 0,
        move_max: 10,
      },
    }],
    weapons: [
      { id: fx.characterWeapons.katanaEquipped.id, name: "Unarmed", equipped_slot: "primary" },
      { id: fx.characterWeapons.pistolLoaded.id, name: "Standard Rifle", equipped_slot: null },
    ],
  });
  const rifle = result.weapons.find((weapon) => weapon.id === fx.characterWeapons.pistolLoaded.id);
  assert.equal(rifle?.can_switch_to, true);
  assert.equal(rifle?.switch_block_reason, null);
  assert.ok(sqlSrc.includes("'cost_mode', 'free'"));
});

test("weapon switch is blocked during combat runtime sync gate", () => {
  assert.ok(sceneControllerSrc.includes("return type === \"select-weapon\" || type === \"reload\";"));
});

test("ambiguous combat context resolves to a user-facing error message", () => {
  const message = resolveWeaponSwitchErrorMessage({ ok: false, error: "COMBAT_CONTEXT_AMBIGUOUS" });
  assert.match(message, /multiple active encounters/i);
});

setTimeout(() => {
  console.log(`\nWeapon Switch Command: ${passed} passed, ${failed} failed`);
  if (failures.length) {
    for (const { name, error } of failures) {
      console.error(`FAILED: ${name}`);
      console.error(error?.stack ?? error);
    }
  }
  process.exit(failed > 0 ? 1 : 0);
}, 50);
