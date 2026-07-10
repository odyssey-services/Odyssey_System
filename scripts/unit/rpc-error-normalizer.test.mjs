import assert from "node:assert/strict";

import { normalizeRpcError } from "../../utils/rpcErrorNormalizer.js";

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

console.log("\nUnit - RPC Error Normalizer\n");

test("statement timeout becomes STATEMENT_TIMEOUT", () => {
  const normalized = normalizeRpcError(new Error("canceling statement due to statement timeout"));
  assert.equal(normalized.ok, false);
  assert.equal(normalized.error, "STATEMENT_TIMEOUT");
  assert.equal(normalized.retryable, true);
});

test("generic RPC throw becomes RPC_EXCEPTION", () => {
  const normalized = normalizeRpcError(new Error("network down"));
  assert.equal(normalized.ok, false);
  assert.equal(normalized.error, "RPC_EXCEPTION");
  assert.equal(normalized.retryable, false);
});

test("normal backend error JSON stays unchanged semantically", () => {
  const normalized = normalizeRpcError({
    ok: false,
    error: "ABILITY_NOT_FOUND",
    message: "Ability is unavailable.",
    rpcException: false,
    retryable: false,
  });
  assert.equal(normalized.error, "ABILITY_NOT_FOUND");
  assert.equal(normalized.message, "Ability is unavailable.");
  assert.equal(normalized.rpcException, false);
});

test("normalized error never has error=null", () => {
  const normalized = normalizeRpcError({ ok: false, message: "Unknown problem", error: null });
  assert.notEqual(normalized.error, null);
  assert.notEqual(normalized.error, "");
});

if (failed > 0) {
  console.error(`\nUnit - RPC Error Normalizer: ${failed} failed, ${passed} passed.`);
  process.exitCode = 1;
} else {
  console.log(`\nUnit - RPC Error Normalizer: all ${passed} passed.`);
}
