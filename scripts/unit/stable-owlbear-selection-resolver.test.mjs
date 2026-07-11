import assert from "node:assert/strict";

import { createTestSuite } from "./_tinyTestRunner.mjs";
import { createStableOwlbearSelectionResolver } from "../../selection/stableOwlbearSelectionResolver.js";

const { test, run } = createTestSuite("Unit - Stable Owlbear Selection Resolver");

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

async function flushMicrotasks() {
  await Promise.resolve();
  await Promise.resolve();
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function createResolverHarness(overrides = {}) {
  const states = [];
  const selectedTokens = overrides.selectedTokens ?? [];
  const roomContext = overrides.roomContext ?? {
    campaignId: "camp-1",
    roomId: "room-1",
    sceneId: "scene-1",
  };
  const playerInfo = overrides.playerInfo ?? {
    id: "player-1",
    role: "PLAYER",
  };
  const settings = overrides.settings ?? { url: "https://example.supabase.co", anonKey: "anon" };

  const resolver = createStableOwlbearSelectionResolver({
    getSelectedOwlbearTokens: overrides.getSelectedOwlbearTokens ?? (async () => selectedTokens),
    getRoomSceneContext: overrides.getRoomSceneContext ?? (async () => roomContext),
    getPlayerInfo: overrides.getPlayerInfo ?? (async () => playerInfo),
    getActiveCombatRuntime: overrides.getActiveCombatRuntime ?? (async () => null),
    getSceneTokenLinks: overrides.getSceneTokenLinks ?? (async () => ({ ok: true, links: [] })),
    hasUsableSettings: overrides.hasUsableSettings ?? (() => true),
    getSettings: overrides.getSettings ?? (() => settings),
    isGm: overrides.isGm ?? ((player) => String(player?.role ?? "").toUpperCase() === "GM"),
    debounceMs: 0,
    onState: async (state) => {
      states.push(state);
      if (typeof overrides.onState === "function") {
        await overrides.onState(state);
      }
    },
  });

  return { resolver, states };
}

test("no selected tokens -> no-selection state", async () => {
  const { resolver, states } = createResolverHarness({
    selectedTokens: [],
  });
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  const finalState = states.at(-1);
  assert.equal(finalState.status, "no-selection");
  assert.equal(finalState.tokenId, null);
  assert.equal(finalState.characterId, null);
});

test("multiple selected tokens -> multiple-selection state", async () => {
  const { resolver, states } = createResolverHarness({
    selectedTokens: [{ id: "tok-a", name: "A" }, { id: "tok-b", name: "B" }],
  });
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  const finalState = states.at(-1);
  assert.equal(finalState.status, "multiple-selection");
  assert.equal(finalState.characterId, null);
});

test("one linked token via combat runtime -> ready source combat_runtime", async () => {
  const { resolver, states } = createResolverHarness({
    selectedTokens: [{ id: "tok-a", name: "A" }],
    playerInfo: { id: "player-1", role: "PLAYER" },
    getActiveCombatRuntime: async () => ({
      visible_participants: [{
        token_id: "tok-a",
        character_id: "char-a",
        display_name: "Hero A",
      }],
      viewer_controlled_character_ids: ["char-a"],
    }),
  });
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  const finalState = states.at(-1);
  assert.equal(finalState.status, "ready");
  assert.equal(finalState.source, "combat_runtime");
  assert.equal(finalState.characterId, "char-a");
});

test("one linked token via scene link -> ready source scene_link", async () => {
  const { resolver, states } = createResolverHarness({
    selectedTokens: [{ id: "tok-b", name: "B" }],
    getSceneTokenLinks: async () => ({
      ok: true,
      links: [{
        token_id: "tok-b",
        is_active: true,
        character: {
          id: "char-b",
          display_name: "Hero B",
          control: { allowed: true },
        },
      }],
    }),
  });
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  const finalState = states.at(-1);
  assert.equal(finalState.status, "ready");
  assert.equal(finalState.source, "scene_link");
  assert.equal(finalState.characterId, "char-b");
});

test("unlinked token -> unlinked-token TOKEN_HAS_NO_CHARACTER", async () => {
  const { resolver, states } = createResolverHarness({
    selectedTokens: [{ id: "tok-u", name: "U" }],
    getSceneTokenLinks: async () => ({ ok: true, links: [] }),
  });
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  const finalState = states.at(-1);
  assert.equal(finalState.status, "unlinked-token");
  assert.equal(finalState.error, "TOKEN_HAS_NO_CHARACTER");
});

test("forbidden token -> not-owned CHARACTER_NOT_CONTROLLED", async () => {
  const { resolver, states } = createResolverHarness({
    selectedTokens: [{ id: "tok-f", name: "F" }],
    playerInfo: { id: "player-1", role: "PLAYER" },
    getSceneTokenLinks: async () => ({
      ok: true,
      links: [{
        token_id: "tok-f",
        is_active: true,
        character: {
          id: "char-f",
          display_name: "Forbidden",
          control: { allowed: false },
          can_control: false,
        },
      }],
    }),
  });
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  const finalState = states.at(-1);
  assert.equal(finalState.status, "not-owned");
  assert.equal(finalState.error, "CHARACTER_NOT_CONTROLLED");
});

test("same signature does not re-resolve unless force=true", async () => {
  let resolveCount = 0;
  const { resolver, states } = createResolverHarness({
    selectedTokens: [{ id: "tok-a", name: "A" }],
    getSceneTokenLinks: async () => {
      resolveCount += 1;
      return {
        ok: true,
        links: [{
          token_id: "tok-a",
          is_active: true,
          character: { id: "char-a", display_name: "Hero A", control: { allowed: true } },
        }],
      };
    },
  });
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  const firstStateCount = states.length;
  await resolver.runSelectionSync({ force: false, reason: "selection-changed" });
  assert.equal(states.length, firstStateCount);
  assert.equal(resolveCount, 1);
  await resolver.runSelectionSync({ force: true, reason: "selection-changed" });
  assert.equal(resolveCount, 2);
});

test("latest request wins; old async result is discarded", async () => {
  let currentTokens = [{ id: "tok-a", name: "A" }];
  const runtimeA = deferred();
  const runtimeB = deferred();
  const seenReadyIds = [];

  const { resolver, states } = createResolverHarness({
    getSelectedOwlbearTokens: async () => currentTokens,
    getActiveCombatRuntime: async ({}) => {
      const tokenId = currentTokens[0]?.id;
      if (tokenId === "tok-a") {
        return runtimeA.promise;
      }
      return runtimeB.promise;
    },
    getSceneTokenLinks: async (payload) => ({
      ok: true,
      links: [{
        token_id: payload?.token_id,
        is_active: true,
        character: {
          id: payload?.token_id === "tok-a" ? "char-a" : "char-b",
          display_name: payload?.token_id === "tok-a" ? "Hero A" : "Hero B",
          control: { allowed: true },
        },
      }],
    }),
    onState: async (state) => {
      if (state.status === "ready") {
        seenReadyIds.push(state.characterId);
      }
    },
  });

  resolver.scheduleSelectionSync({ force: true, reason: "selection-changed" });
  await flushMicrotasks();

  currentTokens = [{ id: "tok-b", name: "B" }];
  resolver.scheduleSelectionSync({ force: true, reason: "selection-changed" });
  await flushMicrotasks();

  runtimeB.resolve(null);
  await flushMicrotasks();
  runtimeA.resolve(null);
  await flushMicrotasks();

  assert.deepEqual(seenReadyIds, ["char-b"]);
  assert.equal(states.at(-1)?.characterId, "char-b");
});

await run();
