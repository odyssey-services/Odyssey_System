const REQUIRED_METHODS = [
  "getViewer",
  "getSelectedTokenId",
  "getSceneTokens",
  "getCharacterForToken",
  "getCharacterRuntime",
  "getWeaponState",
  "getAvailableSkills",
  "getModifiers",
  "getCombatSession",
  "getBattleLog",
  "selectToken",
  "setViewerRole",
  "setMockScenario",
  "subscribe",
  "dispose",
];

export function createCombatHudAdapter(impl, source = "mock") {
  if (!impl || typeof impl !== "object") {
    throw new Error("createCombatHudAdapter: impl object is required.");
  }

  for (const method of REQUIRED_METHODS) {
    if (typeof impl[method] !== "function") {
      throw new Error(`createCombatHudAdapter: missing method "${method}".`);
    }
  }

  return Object.freeze({
    source,
    ...impl,
  });
}
