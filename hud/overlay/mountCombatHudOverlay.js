// Combat HUD overlay — mounter (Phase 1A · 2 · 2.1).
//
// Wires the Phase 0 mock store to the overlay view and exposes a clean
// unmount. Reusable in the popover iframe page and in a standalone DOM preview.
//
// Restores the minimal UI snapshot (collapse / scenario / role / token) BEFORE
// the first render, and additionally restores the personal HUD placement from
// localStorage (durable, per-browser) taking precedence over the URL-seeded
// placement on a cold start. Emits the snapshot via integration.onUiStateChange
// so the background controller can persist + reposition the popover.
//
// No OBR SDK import here; OBR coupling is injected via `integration`.

import { createMockCombatHudAdapter } from "../adapters/mockCombatHudAdapter.js";
import { createCombatHudStore } from "../core/combatHudStore.js";
import { createCombatHudOverlayView } from "./combatHudOverlayView.js";
import { normalizeHudUiState } from "./overlayConstants.js";
import {
  DEFAULT_PLACEMENT,
  clampPlacement,
  readStoredPlacement,
  writeStoredPlacement,
} from "./hudPlacement.js";

/**
 * @param {{
 *   root?: HTMLElement,
 *   uiState?: object,                 // partial HudUiState to restore (from URL)
 *   renderContext?: {vw?:number, vh?:number, gap?:number},
 *   devControls?: boolean,
 *   storage?: Storage,                // injectable for tests; defaults to localStorage
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
  const storage = options.storage ?? (typeof localStorage !== "undefined" ? localStorage : null);

  const restored = normalizeHudUiState(options.uiState);
  let scenarioId = restored.mockScenarioId;

  // Placement: localStorage (durable) wins over the URL-seeded value on a cold
  // start; otherwise the URL value (controller session memory) is used.
  const stored = readStoredPlacement(storage);
  let currentPlacement = stored.mode === "custom" ? stored : clampPlacement(restored.hudPlacement);

  // Render context (true viewport + gap) for drag math + the responsive gap.
  const renderContext = {
    vw: options.renderContext?.vw ?? (typeof window !== "undefined" ? window.innerWidth : 0),
    vh: options.renderContext?.vh ?? (typeof window !== "undefined" ? window.innerHeight : 0),
    gap: options.renderContext?.gap ?? null,
  };

  const adapter = createMockCombatHudAdapter({ scenarioId });
  adapter.setViewerRole(restored.viewerRole);
  // Only override the scenario's default token when a concrete token was
  // restored (a null/empty value means "no explicit selection yet").
  if (restored.selectedTokenId) {
    adapter.selectToken(restored.selectedTokenId);
  }

  const store = createCombatHudStore({ adapter });
  store.initialize();
  store.setHudCollapsed(restored.isHudCollapsed);

  function currentUiState() {
    const s = store.getState();
    return {
      isHudCollapsed: s.ui.isHudCollapsed,
      mockScenarioId: scenarioId,
      viewerRole: s.viewer.role,
      selectedTokenId: s.selectedTokenId,
      hudPlacement: currentPlacement,
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
    obrAvailable,
    devControls: options.devControls !== false,
    renderContext,
    placement: currentPlacement,
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
    onPlacementCommit(placement) {
      currentPlacement = clampPlacement(placement);
      writeStoredPlacement(storage, currentPlacement);
      emitUiState();
    },
    onResetPlacement() {
      currentPlacement = { ...DEFAULT_PLACEMENT };
      writeStoredPlacement(storage, currentPlacement);
      emitUiState();
    },
  });

  // Publish the restored/initial snapshot once so the controller's in-memory
  // copy (and the real popover position) agree with what the iframe shows.
  emitUiState();

  return {
    store,
    unmount() {
      view.destroy();
      store.dispose();
    },
  };
}
