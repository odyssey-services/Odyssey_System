import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { buildBasicAttackCtx, resolveAttack } from "../hud/combat/basicAttackPayload.js";
import { buildAttackPayload } from "../screens/resolveAttack/resolveAttackService.js";
import { normalizeRpcError, toRpcException } from "../utils/rpcErrorNormalizer.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const readText = (...segments) =>
  fs.readFileSync(path.join(repoRoot, ...segments), "utf8").replace(/\r\n/g, "\n");

const sceneControllerSrc = readText("hud", "scene", "sceneSelectionController.js");

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

async function asyncTest(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`  PASS ${name}`);
  } catch (error) {
    failed += 1;
    failures.push({ name, error });
    console.error(`  FAIL ${name}\n      ${error.message}`);
  }
}

console.log("\nAttack Compact Mode\n");

test("perform_attack payload includes include_runtime_refresh=false", () => {
  const ctx = buildBasicAttackCtx({
    sourceCharacterId: "char-a",
    weaponId: "weapon-1",
    targetCharacterId: "char-b",
    bodyPartId: "body-1",
    includeRuntimeRefresh: false,
  });
  const payload = buildAttackPayload(ctx);
  assert.equal(payload.include_runtime_refresh, false);
});

test("perform_attack payload includes result_mode=compact", () => {
  const ctx = buildBasicAttackCtx({
    sourceCharacterId: "char-a",
    weaponId: "weapon-1",
    targetCharacterId: "char-b",
    bodyPartId: "body-1",
    resultMode: "compact",
  });
  const payload = buildAttackPayload(ctx);
  assert.equal(payload.result_mode, "compact");
});

test("successful compact attack triggers post-mutation combat and light runtime refresh", () => {
  assert.ok(sceneControllerSrc.includes("includeRuntimeRefresh: false"));
  assert.ok(sceneControllerSrc.includes("resultMode: \"compact\""));
  assert.ok(sceneControllerSrc.includes("await refreshCombatSessionSafe(sessionController, \"attack-success\")"));
  assert.ok(sceneControllerSrc.includes("await refreshSelectedCharacterRuntime(\"attack-success\", { refreshQuickbar: true })"));
});

test("compact attack path does not request full runtime in the same RPC", () => {
  assert.ok(!sceneControllerSrc.includes("include_runtime_refresh: true"));
  assert.ok(sceneControllerSrc.includes("compact: true"));
});

await asyncTest("timeout is normalized to STATEMENT_TIMEOUT", async () => {
  const result = await resolveAttack(
    buildBasicAttackCtx({
      sourceCharacterId: "char-a",
      weaponId: "weapon-1",
      targetCharacterId: "char-b",
      bodyPartId: "body-1",
    }),
    {
      performAttack: async () => {
        throw toRpcException(normalizeRpcError(new Error("canceling statement due to statement timeout")));
      },
    },
  );

  assert.equal(result.ok, false);
  assert.equal(result.code, "STATEMENT_TIMEOUT");
});

test("attack path is not blindly retried without idempotency support", () => {
  const ctx = buildBasicAttackCtx({
    sourceCharacterId: "char-a",
    weaponId: "weapon-1",
    targetCharacterId: "char-b",
    bodyPartId: "body-1",
    includeRuntimeRefresh: false,
    resultMode: "compact",
  });
  const payload = buildAttackPayload(ctx);
  assert.ok(!("action_request_id" in payload));
  assert.ok(!sceneControllerSrc.includes("perform_attack-retry"));
});

if (failed > 0) {
  console.error(`\nAttack Compact Mode: ${failed} failed, ${passed} passed.`);
  process.exitCode = 1;
} else {
  console.log(`\nAttack Compact Mode: all ${passed} passed.`);
}
