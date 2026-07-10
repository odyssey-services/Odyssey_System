import assert from "node:assert/strict";

import {
  clearRuntimeRefreshCoordinator,
  createDebouncedRefreshScheduler,
  getRuntimeRefreshInFlightCount,
  singleFlightRuntimeRefresh,
} from "../hud/runtime/runtimeRefreshCoordinator.js";

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

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

console.log("\nRuntime Refresh Coordinator\n");

await asyncTest("two identical refresh requests share one Promise", async () => {
  clearRuntimeRefreshCoordinator();
  let callCount = 0;
  const factory = async () => {
    callCount += 1;
    await wait(15);
    return { ok: true, callCount };
  };

  const first = singleFlightRuntimeRefresh("char-a:light", factory);
  const second = singleFlightRuntimeRefresh("char-a:light", factory);

  const [a, b] = await Promise.all([first, second]);
  assert.equal(callCount, 1);
  assert.deepEqual(a, b);
  assert.equal(getRuntimeRefreshInFlightCount(), 0);
});

await asyncTest("different character keys create different refreshes", async () => {
  clearRuntimeRefreshCoordinator();
  let callCount = 0;
  const factory = async () => {
    callCount += 1;
    const runNumber = callCount;
    await wait(10);
    return runNumber;
  };

  const [a, b] = await Promise.all([
    singleFlightRuntimeRefresh("char-a:light", factory),
    singleFlightRuntimeRefresh("char-b:light", factory),
  ]);

  assert.equal(callCount, 2);
  assert.deepEqual([a, b].sort((x, y) => x - y), [1, 2]);
});

await asyncTest("failed refresh is removed from the in-flight map", async () => {
  clearRuntimeRefreshCoordinator();
  let callCount = 0;
  await assert.rejects(
    () => singleFlightRuntimeRefresh("char-a:light", async () => {
      callCount += 1;
      throw new Error("boom");
    }),
    /boom/,
  );
  assert.equal(callCount, 1);
  assert.equal(getRuntimeRefreshInFlightCount(), 0);
});

await asyncTest("next request after failure runs again", async () => {
  clearRuntimeRefreshCoordinator();
  let callCount = 0;
  await assert.rejects(
    () => singleFlightRuntimeRefresh("char-a:light", async () => {
      callCount += 1;
      throw new Error("first fail");
    }),
    /first fail/,
  );

  const result = await singleFlightRuntimeRefresh("char-a:light", async () => {
    callCount += 1;
    return "ok";
  });

  assert.equal(callCount, 2);
  assert.equal(result, "ok");
});

await asyncTest("five deduped callers share one owner refresh and notify only deduped followers", async () => {
  clearRuntimeRefreshCoordinator();
  let callCount = 0;
  let dedupedCount = 0;
  const factory = async () => {
    callCount += 1;
    await wait(15);
    return { ok: true };
  };

  const requests = [
    singleFlightRuntimeRefresh("char-a:light", factory, { onDeduped: () => { dedupedCount += 1; } }),
    singleFlightRuntimeRefresh("char-a:light", factory, { onDeduped: () => { dedupedCount += 1; } }),
    singleFlightRuntimeRefresh("char-a:light", factory, { onDeduped: () => { dedupedCount += 1; } }),
    singleFlightRuntimeRefresh("char-a:light", factory, { onDeduped: () => { dedupedCount += 1; } }),
    singleFlightRuntimeRefresh("char-a:light", factory, { onDeduped: () => { dedupedCount += 1; } }),
  ];

  await Promise.all(requests);

  assert.equal(callCount, 1);
  assert.equal(dedupedCount, 4);
});

await asyncTest("debounce collapses multiple refresh triggers into one", async () => {
  const invocations = [];
  const scheduler = createDebouncedRefreshScheduler((...args) => {
    invocations.push(args);
  }, 25);

  scheduler.schedule("char-a", "selection-changed");
  scheduler.schedule("char-a", "realtime");
  scheduler.schedule("char-a", "selection-changed-final");

  await wait(60);

  assert.equal(invocations.length, 1);
  assert.deepEqual(invocations[0], ["char-a", "selection-changed-final"]);
  assert.equal(scheduler.isScheduled(), false);
});

await asyncTest("flush executes the latest scheduled refresh immediately", async () => {
  const invocations = [];
  const scheduler = createDebouncedRefreshScheduler((...args) => {
    invocations.push(args);
    return args.join(":");
  }, 500);

  scheduler.schedule("char-a", "selection-changed");
  const result = await scheduler.flush();

  assert.equal(result, "char-a:selection-changed");
  assert.deepEqual(invocations, [["char-a", "selection-changed"]]);
  assert.equal(scheduler.isScheduled(), false);
});

if (failed > 0) {
  console.error(`\nRuntime Refresh Coordinator: ${failed} failed, ${passed} passed.`);
  process.exitCode = 1;
} else {
  console.log(`\nRuntime Refresh Coordinator: all ${passed} passed.`);
}
