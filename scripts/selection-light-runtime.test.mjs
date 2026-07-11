import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { createSceneSelectionAdapter } from "../hud/scene/sceneSelectionAdapter.js";
import { SELECTION_STATUS } from "../hud/scene/selectionState.js";
import { normalizeRpcError } from "../utils/rpcErrorNormalizer.js";

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

console.log("\nSelection Light Runtime\n");

function createAdapter(fetchCharacterBundle) {
  return createSceneSelectionAdapter({
    backendConfigured: true,
    getViewer: () => ({ playerId: "player-1", role: "GM" }),
    fetchSceneTokenLink: async () => ({
      ok: true,
      links: [{
        token_id: "token-1",
        is_active: true,
        character: { id: "char-1", display_name: "Hero" },
      }],
    }),
    fetchCharacterBundle,
  });
}

await asyncTest("selection ready uses light runtime success", async () => {
  const adapter = createAdapter(async () => ({
    ok: true,
    character: { owner_player_id: "player-1", character_key: "hero" },
    state: { is_alive: true, is_conscious: true, status_summary: "Ready" },
    sections: { summary: {}, combat: {} },
  }));

  const state = await adapter.resolve(["token-1"]);
  assert.equal(state.status, SELECTION_STATUS.ready);
  assert.equal(state.access.canView, true);
  assert.equal(state.characterId, "char-1");
});

test("inventory failure does not make selection unavailable in staged runtime flow", () => {
  assert.ok(sceneControllerSrc.includes("const bundle = await fetchLightRuntimeBundle(characterId, selectedRuntimeReason);"));
  assert.ok(!sceneControllerSrc.includes("Promise.all([\n          getCharacterRuntimeBundle("));
  assert.ok(sceneControllerSrc.includes("panel: \"inventory\""));
  assert.ok(sceneControllerSrc.includes("heavy-fetch-failed"));
  assert.ok(sceneControllerSrc.includes("heavy-fetch-result"));
});

test("armory failure does not make selection unavailable in staged runtime flow", () => {
  assert.ok(sceneControllerSrc.includes("panel: \"armory\""));
  assert.ok(sceneControllerSrc.includes("return hydrateBundleWithHeavyCache(bundle, characterId);"));
  assert.ok(sceneControllerSrc.includes("refreshHeavyCharacterData("));
});

test("light runtime timeout is normalized to STATEMENT_TIMEOUT", () => {
  const normalized = normalizeRpcError(new Error("canceling statement due to statement timeout"));
  assert.equal(normalized.error, "STATEMENT_TIMEOUT");
  assert.equal(normalized.retryable, true);
});

test("light runtime timeout retries once", () => {
  assert.ok(sceneControllerSrc.includes("if (normalized.error === \"STATEMENT_TIMEOUT\" && normalized.retryable && attempt < 2)"));
  assert.ok(sceneControllerSrc.includes("await waitMs(LIGHT_RUNTIME_RETRY_DELAY_MS);"));
});

test("startup resolve prefers live OBR selection over the initial player snapshot", () => {
  assert.ok(sceneControllerSrc.includes("await resolveAndPublish(await readLiveSelectionIds(player.selection), \"startup\");"));
  assert.ok(sceneControllerSrc.includes("const liveSelection = await getSelectedTokenIds();"));
});

test("selection request with existing payload replays only lastPayload", () => {
  assert.ok(sceneControllerSrc.includes("logDebugEvent(\"selection\", \"selection-replayed\""));
  assert.ok(sceneControllerSrc.includes("scheduleLiveSelectionResolve(\"selection-request-initial\", { forceResolve: true })"));
  assert.ok(sceneControllerSrc.includes("selection-request-hydrate"));
  assert.ok(sceneControllerSrc.includes("event?.data?.hydrateIfStale === true"));
  assert.ok(sceneControllerSrc.includes("selection-hydrate-requested"));
  assert.ok(sceneControllerSrc.includes("selection-hydrate-failed"));
  assert.ok(sceneControllerSrc.includes("void readLiveSelectionIds(currentSelectionIds)"));
  assert.ok(sceneControllerSrc.includes("if (liveSignature !== requestedSignature)"));
  assert.ok(sceneControllerSrc.includes("selection-hydrate-skipped"));
  assert.ok(sceneControllerSrc.includes("reason: \"requested-selection-not-live\""));
  assert.ok(sceneControllerSrc.includes("void resolveAndPublish(liveSelectionIds, \"selection-request-hydrate\", { allowWhileDeferred: true })"));
});

test("selection request hydrate remains a startup fallback only", () => {
  assert.ok(sceneControllerSrc.includes("&& (!lastPayload || lastPayload.status === \"no-selection\" || lastPayload.status === \"loading\")"));
  assert.ok(sceneControllerSrc.includes("&& requestedSignature !== pendingSignature"));
  assert.ok(sceneControllerSrc.includes("previousCharacterId: lastPayload?.characterId ?? null"));
});

test("stale payload replay is blocked while another selection is pending", () => {
  assert.ok(sceneControllerSrc.includes("selection-replay-skipped"));
  assert.ok(sceneControllerSrc.includes("reason: \"pending-selection-mismatch\""));
  assert.ok(sceneControllerSrc.includes("lastPayload.selectedItemId !== pendingSelectionIds[0]"));
});

test("native selection-changed path remains primary and is logged", () => {
  assert.ok(sceneControllerSrc.includes("selection-change-observed"));
  assert.ok(sceneControllerSrc.includes("previousSelectionIds: currentSelectionIds"));
  assert.ok(sceneControllerSrc.includes("void handleObservedNonEmptySelection(observed, reason).catch(() => {});"));
  assert.ok(sceneControllerSrc.includes("selection-resolve-start"));
  assert.ok(sceneControllerSrc.includes("source-token-selected"));
});

test("transient empty selection events use grace delay and live-read execution", () => {
  assert.ok(sceneControllerSrc.includes("const TRANSIENT_EMPTY_SELECTION_GRACE_MS = 500;"));
  assert.ok(sceneControllerSrc.includes("if (currentSelectionIds.length > 0 || pendingSelectionIds.length > 0)"));
  assert.ok(sceneControllerSrc.includes("empty-selection-deferred"));
  assert.ok(sceneControllerSrc.includes("empty-selection-ignored"));
  assert.ok(sceneControllerSrc.includes("if (liveSelectionIds.length === 0 && pendingSelectionIds.length === 0)"));
  assert.ok(sceneControllerSrc.includes("reason: \"hud-interaction-active\""));
  assert.ok(sceneControllerSrc.includes("reason: \"sticky-last-selection\""));
  assert.ok(sceneControllerSrc.includes("publishState(lastState, `${reason}:sticky-last-selection`)"));
  assert.ok(sceneControllerSrc.includes("selection-empty-recovered-live"));
  assert.ok(sceneControllerSrc.includes("reason: \"pending-non-empty-selection\""));
  assert.ok(sceneControllerSrc.includes("reason: \"cancelled-by-live-selection\""));
});

test("selection noise from unlinked and non-character items is classified and ignored during HUD interaction", () => {
  assert.ok(sceneControllerSrc.includes("async function classifySelectionIds(selectionIds)"));
  assert.ok(sceneControllerSrc.includes("linked-character-token"));
  assert.ok(sceneControllerSrc.includes("unlinked-token"));
  assert.ok(sceneControllerSrc.includes("drawing-item"));
  assert.ok(sceneControllerSrc.includes("hud-preview-item"));
  assert.ok(sceneControllerSrc.includes("unknown-non-token"));
  assert.ok(sceneControllerSrc.includes("selection-noise-ignored"));
  assert.ok(sceneControllerSrc.includes("function shouldIgnoreUnlinkedSelectionNoise(selectionIds, classification, reason = \"selection-changed\")"));
  assert.ok(sceneControllerSrc.includes("function shouldIgnoreNonCharacterSelection(classification)"));
  assert.ok(sceneControllerSrc.includes("currentCharacterId: lastPayload?.characterId ?? null"));
  assert.ok(sceneControllerSrc.includes("currentSelectedItemId: lastPayload?.selectedItemId ?? null"));
});

test("selected character change and payload broadcast are explicitly logged", () => {
  assert.ok(sceneControllerSrc.includes("selected-character-changed"));
  assert.ok(sceneControllerSrc.includes("selection-payload-broadcast"));
  assert.ok(sceneControllerSrc.includes("const previousCharacterId = lastResolvedCharacterId"));
  assert.ok(sceneControllerSrc.includes("nextCharacterId"));
});

test("non-empty observed selection schedules resolve when it differs from current or pending", () => {
  assert.ok(sceneControllerSrc.includes("if (observedSignature !== currentSignature || observedSignature !== pendingSignature)"));
  assert.ok(sceneControllerSrc.includes("pendingSelectionIds = normalizedSelectionIds.slice();"));
  assert.ok(sceneControllerSrc.includes("empty-selection-cancelled"));
});

test("selection resolve has timeout protection and latest-wins generation gating", () => {
  assert.ok(sceneControllerSrc.includes("const SELECTION_RESOLVE_TIMEOUT_MS = 5000;"));
  assert.ok(sceneControllerSrc.includes("const generation = ++selectionResolveGeneration;"));
  assert.ok(sceneControllerSrc.includes("selection-resolve-timeout"));
  assert.ok(sceneControllerSrc.includes("selection-resolve-result"));
  assert.ok(sceneControllerSrc.includes("selection-resolve-finished"));
  assert.ok(sceneControllerSrc.includes("generation !== null && generation !== selectionResolveGeneration"));
  assert.ok(sceneControllerSrc.includes("SELECTION_RESOLVE_TIMEOUT"));
});

await asyncTest("after repeated light runtime failure selection shows runtime fetch failed", async () => {
  const adapter = createAdapter(async () => {
    throw new Error("canceling statement due to statement timeout");
  });

  const state = await adapter.resolve(["token-1"]);
  assert.equal(state.status, SELECTION_STATUS.error);
  assert.equal(state.error.code, "RUNTIME_FETCH_FAILED");
  assert.match(String(state.error.message), /statement timeout/i);
});

if (failed > 0) {
  console.error(`\nSelection Light Runtime: ${failed} failed, ${passed} passed.`);
  process.exitCode = 1;
} else {
  console.log(`\nSelection Light Runtime: all ${passed} passed.`);
}
