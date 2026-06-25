// Combat HUD — reactive store (Phase 0).
//
// One normalized state object, a subscribe/getState/dispose surface, and a
// small set of EXPLICIT actions. The store depends only on an adapter (see
// adapters/combatHudAdapter.js); it never imports mock data or Supabase
// directly, so future HUD components read from the store identically
// regardless of data source.
//
// Pure of DOM/SDK/CSS. Safe to load under plain Node.

import { HUD_STATUS } from "../models/combatHudContracts.js";
import {
  createInitialState,
  applyViewer,
  applyLoading,
  applySelectionResult,
  applyError,
  setCollapsed,
  resetActionDraft as resetActionDraftTransition,
  assembleSnapshot,
} from "./combatHudActions.js";

/**
 * Create a Combat HUD store bound to an adapter.
 * @param {{ adapter: ReturnType<import("../adapters/combatHudAdapter.js").createCombatHudAdapter> }} deps
 */
export function createCombatHudStore({ adapter }) {
  if (!adapter || typeof adapter.subscribe !== "function") {
    throw new Error("createCombatHudStore: a valid adapter is required.");
  }

  let state = createInitialState(adapter.source);
  /** @type {Set<(state:any)=>void>} */
  const listeners = new Set();
  let disposed = false;
  let unsubscribeAdapter = null;

  /* ----------------- internal helpers ----------------- */

  function setState(next) {
    state = next;
    emit();
  }

  function emit() {
    if (disposed) return;
    for (const listener of Array.from(listeners)) {
      try {
        listener(state);
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error("[combatHud/store] listener threw", error);
      }
    }
  }

  /**
   * Read everything needed from the adapter and recompute the state. This is
   * the single refresh path used after mutation / external update / error
   * reconciliation (spec §3).
   */
  function refreshRuntime() {
    if (disposed) return;
    try {
      const viewer = adapter.getViewer();
      const selectedTokenId = adapter.getSelectedTokenId();

      // No token → empty (handled fully by applySelectionResult).
      if (!selectedTokenId) {
        setState(applySelectionResult(state, {
          viewer, selectedTokenId: null, characterId: null, entity: null,
          snapshot: state.snapshot,
        }));
        return;
      }

      const link = adapter.getCharacterForToken(selectedTokenId);
      const characterId = link?.characterId ?? null;
      const entity = characterId ? adapter.getCharacterRuntime(characterId) : null;

      // Not linked / no runtime → empty.
      if (!characterId || !entity) {
        setState(applySelectionResult(state, {
          viewer, selectedTokenId, characterId, entity: null,
          snapshot: state.snapshot,
        }));
        return;
      }

      // Build a full snapshot only when there is a linked character. Access is
      // re-checked inside applySelectionResult; if the viewer can't see it the
      // snapshot is discarded for an empty state, so we keep assembly cheap by
      // doing it only after a quick access pre-check is unnecessary here.
      const weapon = adapter.getWeaponState(characterId);
      const skills = adapter.getAvailableSkills(characterId);
      const modifiers = adapter.getModifiers(characterId);
      const combatSession = adapter.getCombatSession();
      const battleLog = adapter.getBattleLog(combatSession?.id ?? null);

      const snapshot = assembleSnapshot({
        entity,
        weapon,
        skills,
        combatSession,
        modifiers,
        battleLog,
        selectedCharacterId: characterId,
      });

      setState(applySelectionResult(state, {
        viewer, selectedTokenId, characterId, entity, snapshot,
      }));
    } catch (error) {
      setState(applyError(state, "Failed to refresh Combat HUD state.", error?.message ?? error));
    }
  }

  /* ----------------- public actions ----------------- */

  function initialize() {
    if (disposed) return;
    setState(applyLoading(state));
    // Subscribe once; adapter notifications drive every subsequent refresh.
    if (!unsubscribeAdapter) {
      unsubscribeAdapter = adapter.subscribe(() => refreshRuntime());
    }
    refreshRuntime();
  }

  function selectToken(tokenId) {
    if (disposed) return;
    // Delegate to the adapter; its notification triggers refreshRuntime.
    adapter.selectToken(tokenId ?? null);
  }

  function setViewerRole(role) {
    if (disposed) return;
    adapter.setViewerRole(role);
  }

  function setViewer(viewer) {
    if (disposed) return;
    // Local-only viewer override (identity), then refresh derived access.
    setState(applyViewer(state, viewer));
    refreshRuntime();
  }

  function setHudCollapsed(isCollapsed) {
    if (disposed) return;
    setState(setCollapsed(state, isCollapsed));
  }

  function setMockScenario(scenarioId) {
    if (disposed) return;
    // Only meaningful for the mock adapter; supabase skeleton throws, which we
    // surface as an error state rather than letting it crash the caller.
    try {
      adapter.setMockScenario(scenarioId);
    } catch (error) {
      setState(applyError(state, "setMockScenario is not supported by this adapter.", error?.message ?? error));
    }
  }

  function resetActionDraft() {
    if (disposed) return;
    setState(resetActionDraftTransition(state));
  }

  function getState() {
    return state;
  }

  function subscribe(listener) {
    if (typeof listener !== "function") return () => {};
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }

  function dispose() {
    if (disposed) return;
    disposed = true;
    if (typeof unsubscribeAdapter === "function") {
      try { unsubscribeAdapter(); } catch (_e) { /* ignore */ }
      unsubscribeAdapter = null;
    }
    listeners.clear();
  }

  return {
    // lifecycle
    initialize,
    dispose,
    // reads
    getState,
    subscribe,
    // actions
    selectToken,
    setViewer,
    setViewerRole,
    setHudCollapsed,
    setMockScenario,
    resetActionDraft,
    // exposed for diagnostics/tests
    get status() { return state.status; },
    isReady() { return state.status === HUD_STATUS.ready; },
  };
}
