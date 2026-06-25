// Combat HUD overlay — view renderer (Phase 1A shell → Phase 2 layout).
//
// Top-level overlay view. It switches between:
//   - collapsed  → a small reopen pill, and
//   - expanded   → the full Phase 2 Combat HUD layout (CombatHudLayout).
//
// NO OBR SDK import: all OBR coupling (popover resize, broadcast, availability)
// is injected by the caller (mountCombatHudOverlay) via callbacks. The same
// constructor signature and return surface as Phase 1A are preserved, so the
// mounter, collapse/reopen and URL-restore flow are unchanged.

import { createCombatHudLayout } from "../components/CombatHudLayout.js";
import { ICON_MARK } from "../components/hudIcons.js";

/**
 * Create the overlay view.
 * @param {{
 *   root: HTMLElement,
 *   store: object,
 *   scenarioId?: string,
 *   role?: string,
 *   obrAvailable?: boolean,
 *   devControls?: boolean,
 *   onCollapse: (collapsed:boolean)=>void,
 *   onScenario: (scenarioId:string)=>void,
 *   onRole: (role:string)=>void,
 * }} cfg
 */
export function createCombatHudOverlayView(cfg) {
  const {
    root, store, obrAvailable = true, devControls = true,
    onCollapse, onScenario, onRole, onPlacementCommit, onResetPlacement,
    renderContext, placement,
  } = cfg;

  const host = document.createElement("div");
  host.className = "odyssey-hud ohud-overlay";
  root.appendChild(host);

  let scenarioId = cfg.scenarioId ?? "A";
  /** @type {ReturnType<typeof createCombatHudLayout>|null} */
  let layout = null;
  let mode = null; // "expanded" | "collapsed"

  function mountLayout() {
    if (layout) return;
    layout = createCombatHudLayout({
      store,
      obrAvailable,
      devControls,
      scenarioId,
      renderContext,
      placement,
      onScenario(id) { scenarioId = id; onScenario(id); },
      onRole,
      onCollapse,
      onPlacementCommit,
      onResetPlacement,
    });
    host.appendChild(layout.el);
  }

  function unmountLayout() {
    if (!layout) return;
    layout.destroy();
    layout = null;
  }

  function showPill() {
    host.innerHTML = `
      <button class="ohud-pill" data-ohud="reopen" title="Open Odyssey Combat HUD" aria-label="Open Odyssey Combat HUD">
        <span class="ohud-mark" aria-hidden="true">${ICON_MARK}</span>
        <span class="ohud-pill-label">ODYSSEY</span>
      </button>`;
  }

  function render(state) {
    const collapsed = Boolean(state?.ui?.isHudCollapsed);
    host.classList.toggle("is-collapsed", collapsed);
    if (collapsed) {
      if (mode !== "collapsed") {
        unmountLayout();
        showPill();
        mode = "collapsed";
      }
    } else if (mode !== "expanded") {
      host.innerHTML = "";
      mountLayout();
      mode = "expanded";
    }
    // While expanded, CombatHudLayout subscribes to the store itself and
    // re-renders its own content, so no per-state push is needed here.
  }

  function onClick(e) {
    const el = e.target.closest("[data-ohud='reopen']");
    if (el) onCollapse(false);
  }
  host.addEventListener("click", onClick);

  const unsubscribe = store.subscribe(render);
  render(store.getState());

  return {
    render,
    setScenarioId(id) {
      scenarioId = id;
      if (layout) layout.setScenarioId(id);
    },
    destroy() {
      unsubscribe();
      host.removeEventListener("click", onClick);
      unmountLayout();
      host.remove();
    },
  };
}
