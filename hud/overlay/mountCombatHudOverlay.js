// Combat HUD overlay — mounter (Phase 1A + follow-up).
//
// Wires the Phase 0 mock store to the overlay view and exposes a clean
// unmount. Reusable in two places:
//   1. the popover iframe page (combatHudOverlayPage.js), and
//   2. a manual standalone DOM preview (no OBR).
//
// Follow-up: accepts a restored UI snapshot and applies it to the adapter +
// store BEFORE the first render, so a popover re-open (which OBR may service by
// reloading the iframe) restores collapse / scenario / role / selected token
// instead of resetting to defaults. It also emits the current snapshot via
// `integration.onUiStateChange` on every change so the controller can persist
// it for the next re-open.
//
// All OBR coupling is injected via `integration` so this module never imports
// the OBR SDK. It DOES import Phase 0 pure modules (store + mock adapter) —
// allowed: those modules stay pure; only this DOM-side consumer pulls them in.

import { createMockCombatHudAdapter } from "../adapters/mockCombatHudAdapter.js";
import { createCombatHudStore } from "../core/combatHudStore.js";
import { createCombatHudOverlayView } from "./combatHudOverlayView.js";
import { normalizeHudUiState } from "./overlayConstants.js";

/**
 * Mount the overlay shell into a DOM root.
 * @param {{
 *   root?: HTMLElement,
 *   uiState?: object,            // partial HudUiState to restore
 *   devControls?: boolean,
 *   integration?: {
 *     available?: boolean,
 *     onUiStateChange?: (uiState:object)=>void,
 *   }
 * }} [options]
 * @returns {{ unmount:()=>void, store:object }}
 */
export function mountCombatHudOverlay(options = {}) {
  if (typeof document === "undefined") {
    throw new Error("mountCombatHudOverlay requires a DOM environment.");
  }

  const root = options.root ?? document.body;
  const integration = options.integration ?? {};
  const obrAvailable = integration.available !== false;

  // Restored snapshot merged over defaults → complete, normalized.
  const restored = normalizeHudUiState(options.uiState);
  let scenarioId = restored.mockScenarioId;

  // --- Build the data source pre-seeded with the restored selection ---
  const adapter = createMockCombatHudAdapter({ scenarioId });
  // Apply role + token overrides BEFORE the store subscribes, so the very
  // first refresh already reflects the restored selection. (These notify the
  // adapter's listeners, but the store hasn't subscribed yet — safe no-ops.)
  adapter.setViewerRole(restored.viewerRole);
  if (restored.selectedTokenId !== undefined) {
    adapter.selectToken(restored.selectedTokenId);
  }

  const store = createCombatHudStore({ adapter });

  // Compute the snapshot from the restored adapter, then restore the collapse
  // flag — both BEFORE the view's first render so the first painted frame is
  // already correct (no flash of default state).
  store.initialize();
  store.setHudCollapsed(restored.isHudCollapsed);

  /** Read the current minimal UI snapshot from the store + tracked scenario. */
  function currentUiState() {
    const s = store.getState();
    return {
      isHudCollapsed: s.ui.isHudCollapsed,
      mockScenarioId: scenarioId,
      viewerRole: s.viewer.role,
      selectedTokenId: s.selectedTokenId,
    };
  }

  function emitUiState() {
    if (typeof integration.onUiStateChange === "function") {
      try { integration.onUiStateChange(currentUiState()); } catch (_e) { /* ignore */ }
    }
  }

  const view = createCombatHudOverlayView({
    root,
    store,
    scenarioId,
    role: restored.viewerRole,
    obrAvailable,
    devControls: options.devControls !== false,
    onCollapse(collapsed) {
      store.setHudCollapsed(collapsed);
      emitUiState();
    },
    onScenario(id) {
      scenarioId = id;
      store.setMockScenario(id);
      emitUiState();
    },
    onRole(role) {
      store.setViewerRole(role);
      emitUiState();
    },
  });

  // Publish the restored/initial snapshot once so the controller's in-memory
  // copy agrees with what the iframe is actually showing.
  emitUiState();

  return {
    store,
    unmount() {
      view.destroy();
      store.dispose();
    },
  };
}
