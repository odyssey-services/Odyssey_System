// Combat HUD — mock adapter (Phase 0).
//
// Holds the currently active mock scenario plus two ephemeral overrides
// (viewer role and selected token) so a developer can flip role / selection
// without rebuilding the scenario. Emits change notifications so the store
// re-reads via the standard adapter getters.
//
// NEVER calls Supabase or the OBR SDK. Pure, deterministic, local.

import { createCombatHudAdapter } from "./combatHudAdapter.js";
import {
  createScenario,
  DEFAULT_SCENARIO_ID,
} from "../models/combatHudMockScenarios.js";

/**
 * Create a mock adapter.
 * @param {{ scenarioId?: string }} [options]
 * @returns {ReturnType<typeof createCombatHudAdapter>}
 */
export function createMockCombatHudAdapter(options = {}) {
  /** @type {Set<() => void>} */
  const listeners = new Set();

  let scenario = createScenario(options.scenarioId ?? DEFAULT_SCENARIO_ID);
  /** Override of the scenario's selected token (null = use scenario default). */
  let selectedTokenOverride = undefined;
  /** Override of the scenario's viewer role (null = use scenario default). */
  let roleOverride = undefined;
  let disposed = false;

  function notify() {
    if (disposed) return;
    for (const listener of Array.from(listeners)) {
      try {
        listener();
      } catch (error) {
        // A misbehaving listener must not break the others.
        // eslint-disable-next-line no-console
        console.error("[combatHud/mock] listener threw", error);
      }
    }
  }

  function currentSelectedTokenId() {
    return selectedTokenOverride !== undefined
      ? selectedTokenOverride
      : scenario.selectedTokenId;
  }

  function currentRole() {
    return roleOverride !== undefined ? roleOverride : scenario.viewer.role;
  }

  const impl = {
    /* ----------------- data getters ----------------- */

    getViewer() {
      return { ...scenario.viewer, role: currentRole() };
    },

    getSelectedTokenId() {
      return currentSelectedTokenId() ?? null;
    },

    getSceneTokens() {
      return scenario.tokens;
    },

    getCharacterForToken(tokenId) {
      if (!tokenId) return null;
      const characterId = scenario.links[tokenId] ?? null;
      const token = scenario.tokens.find((t) => t.tokenId === tokenId) ?? null;
      if (!characterId || !token) return null;
      return { characterId, token };
    },

    getCharacterRuntime(characterId) {
      if (!characterId) return null;
      return scenario.characters[characterId] ?? null;
    },

    getWeaponState(characterId) {
      if (!characterId) return null;
      return scenario.weapons[characterId] ?? null;
    },

    getAvailableSkills(characterId) {
      if (!characterId) return { library: [], quickSlots: [] };
      return scenario.skills[characterId] ?? { library: [], quickSlots: [] };
    },

    getModifiers(characterId) {
      if (!characterId) return [];
      return scenario.modifiers[characterId] ?? [];
    },

    getCombatSession() {
      return scenario.combatSession ?? null;
    },

    getBattleLog(_sessionId) {
      // Mock log is scenario-scoped; sessionId is accepted for interface parity.
      return scenario.battleLog ?? { entries: [] };
    },

    /* ----------------- mutators ----------------- */

    selectToken(tokenId) {
      selectedTokenOverride = tokenId ?? null;
      notify();
    },

    setViewerRole(role) {
      roleOverride = role;
      notify();
    },

    setMockScenario(scenarioId) {
      scenario = createScenario(scenarioId);
      // Reset overrides so the new scenario's own defaults take effect.
      selectedTokenOverride = undefined;
      roleOverride = undefined;
      notify();
    },

    /* ----------------- lifecycle ----------------- */

    subscribe(listener) {
      if (typeof listener !== "function") return () => {};
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },

    dispose() {
      disposed = true;
      listeners.clear();
    },
  };

  return createCombatHudAdapter(impl, "mock");
}
