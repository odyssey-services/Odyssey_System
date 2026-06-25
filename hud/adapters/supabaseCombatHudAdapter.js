// Combat HUD — Supabase adapter (SKELETON, Phase 0).
//
// This module exists so the production data source has the SAME interface as
// the mock adapter from day one. It is NOT implemented in Phase 0: every
// method throws a clear, typed "not implemented" error if invoked. No real
// Supabase calls happen here yet.
//
// Migration plan (documented in docs/combat-hud-phase-0.md):
//   - getViewer:           OBR.player.getId/getName/getRole via runtime.bridges.obr
//   - getSelectedTokenId:  OBR.player.getSelection (single selection)
//   - getSceneTokens:      runtime.api.placement.getSceneTokenLinks
//   - getCharacterForToken:resolve via getSceneTokenLinks result
//   - getCharacterRuntime: runtime.api.placement.getCharacterRuntimeBundle
//   - getWeaponState:      from runtime bundle (armory section) / weaponApi
//   - getAvailableSkills:  from runtime bundle (abilities) + quickbar (Task B7)
//   - getModifiers:        from runtime bundle (modifiers section)
//   - getCombatSession:    combat-session RPCs (Tasks B1/B2 — not yet built)
//   - getBattleLog:        combat_log_entries query (Task B1)
//   - subscribe:           Supabase realtime (Task B8) + OBR selection events
//
// Intentionally avoids importing the OBR SDK / Supabase bridge at module load
// so Phase 0 tooling (the Node verification script) can import this file
// without `node_modules` present. Dependencies arrive via the `runtime`
// argument when the real implementation lands.

import { createCombatHudAdapter } from "./combatHudAdapter.js";

const NOT_IMPLEMENTED = "Supabase Combat HUD adapter is not implemented in Phase 0.";

/**
 * Error type so callers can distinguish "feature pending" from real failures.
 */
export class CombatHudNotImplementedError extends Error {
  /** @param {string} method */
  constructor(method) {
    super(`${NOT_IMPLEMENTED} (called: ${method})`);
    this.name = "CombatHudNotImplementedError";
    this.code = "PHASE0_NOT_IMPLEMENTED";
    this.method = method;
  }
}

/**
 * Create the Supabase adapter skeleton.
 * @param {{ runtime?: object, settings?: object }} [_deps]
 * @returns {ReturnType<typeof createCombatHudAdapter>}
 */
export function createSupabaseCombatHudAdapter(_deps = {}) {
  const pending = (method) => () => {
    throw new CombatHudNotImplementedError(method);
  };

  const impl = {
    getViewer: pending("getViewer"),
    getSelectedTokenId: pending("getSelectedTokenId"),
    getSceneTokens: pending("getSceneTokens"),
    getCharacterForToken: pending("getCharacterForToken"),
    getCharacterRuntime: pending("getCharacterRuntime"),
    getWeaponState: pending("getWeaponState"),
    getAvailableSkills: pending("getAvailableSkills"),
    getModifiers: pending("getModifiers"),
    getCombatSession: pending("getCombatSession"),
    getBattleLog: pending("getBattleLog"),
    selectToken: pending("selectToken"),
    setViewerRole: pending("setViewerRole"),
    setMockScenario: pending("setMockScenario"),
    // subscribe must not throw on wiring; it is a no-op until implemented so
    // the store can attach without crashing during an accidental early swap.
    subscribe() {
      return () => {};
    },
    dispose() {},
  };

  return createCombatHudAdapter(impl, "supabase");
}
