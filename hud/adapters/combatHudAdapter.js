// Combat HUD — adapter boundary (Phase 0).
//
// The store depends ONLY on this narrow interface, never on mock data or
// Supabase directly. Both `mockCombatHudAdapter` and the future
// `supabaseCombatHudAdapter` produce an object that passes through
// `createCombatHudAdapter`, so the store can treat any data source
// identically.
//
// Pure module: no SDK, no Supabase, no CSS.

/**
 * Required adapter methods. The data getters return RAW (source-shaped but
 * already-normalized-to-contract) payloads; the store deep-clones them before
 * storing, so adapters may return their own internal objects safely.
 *
 * Data getters:
 *  - getViewer(): Viewer
 *  - getSelectedTokenId(): string|null
 *  - getSceneTokens(): HudToken[]
 *  - getCharacterForToken(tokenId): { characterId, token } | null
 *  - getCharacterRuntime(characterId): EntityRuntime | null
 *  - getWeaponState(characterId): { primary, secondary } | null
 *  - getAvailableSkills(characterId): { library, quickSlots }
 *  - getModifiers(characterId): HudModifier[]
 *  - getCombatSession(): CombatSession | null
 *  - getBattleLog(sessionId): { entries: BattleLogEntry[] }
 *
 * Mutators (Phase 0 — enough to drive store transitions):
 *  - selectToken(tokenId): void
 *  - setViewerRole(role): void
 *  - setMockScenario(scenarioId): void   (mock only; supabase skeleton throws)
 *
 * Lifecycle:
 *  - subscribe(listener): () => void
 *  - dispose(): void
 */
const REQUIRED_METHODS = Object.freeze([
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
]);

/**
 * Validate and freeze an adapter implementation.
 * @param {Object} impl
 * @param {"mock"|"supabase"} source
 * @returns {Object} the validated adapter (with a `source` tag)
 */
export function createCombatHudAdapter(impl, source) {
  if (!impl || typeof impl !== "object") {
    throw new Error("createCombatHudAdapter: implementation object is required.");
  }
  if (source !== "mock" && source !== "supabase") {
    throw new Error(`createCombatHudAdapter: invalid source "${source}".`);
  }
  const missing = REQUIRED_METHODS.filter((name) => typeof impl[name] !== "function");
  if (missing.length > 0) {
    throw new Error(
      `createCombatHudAdapter: missing required method(s): ${missing.join(", ")}.`,
    );
  }
  // Expose only the contract surface plus the source tag, so the store can't
  // accidentally depend on adapter-private fields.
  const adapter = { source };
  for (const name of REQUIRED_METHODS) {
    adapter[name] = impl[name].bind(impl);
  }
  return Object.freeze(adapter);
}

export { REQUIRED_METHODS };
