// Combat HUD — single-module mount (Phase 2.2).
//
// Each HUD module is its OWN OBR popover (own iframe), sized to the module rect.
// This file renders exactly ONE module's block, filling the iframe, wired to a
// Phase 0 mock store (deterministic — every module iframe derives the same
// snapshot from the shared scenario/role/token seeded by the controller via the
// URL). No OBR SDK import; no Supabase; read-only.
//
// The Player module additionally hosts the global HUD controls (Arrange HUD +
// collapse) so normal-mode blocks don't all show grips/buttons.

import { createMockCombatHudAdapter } from "../adapters/mockCombatHudAdapter.js";
import { createCombatHudStore } from "../core/combatHudStore.js";
import { normalizeHudUiState } from "../overlay/overlayConstants.js";
import { resolveBodyMode } from "./hudLayoutModel.js";

import { renderPlayerBlock } from "./PlayerBlock.js";
import { renderGunBlock } from "./GunBlock.js";
import { renderSkillBlock } from "./SkillBlock.js";
import { renderTargetBlock } from "./TargetBlock.js";
import { renderModifierModule } from "./ModifierBlock.js";
import { renderActionModule } from "./ActionBlock.js";
import { renderBattleLogPanel } from "./BattleLogBlock.js";
import { renderEmptyState, renderErrorState, renderLoadingState } from "./EmptyHudState.js";
import { createTooltip } from "./Tooltip.js";
import { ICON_GRID, ICON_CARET_DOWN } from "./hudIcons.js";
import { cls } from "./hudDom.js";

const BLOCK_RENDERERS = {
  player: renderPlayerBlock,
  gun: renderGunBlock,
  skills: renderSkillBlock,
  target: renderTargetBlock,
  modifiers: renderModifierModule,
  action: renderActionModule,
  log: renderBattleLogPanel,
};

/**
 * @param {{
 *   root: HTMLElement,
 *   moduleId: string,
 *   uiState?: object,
 *   integration?: { onArrange?:()=>void, onCollapse?:(c:boolean)=>void },
 * }} options
 */
export function mountCombatHudModule(options) {
  const { root, moduleId } = options;
  const integration = options.integration ?? {};
  const restored = normalizeHudUiState(options.uiState);

  const adapter = createMockCombatHudAdapter({ scenarioId: restored.mockScenarioId });
  adapter.setViewerRole(restored.viewerRole);
  if (restored.selectedTokenId) adapter.selectToken(restored.selectedTokenId);

  const store = createCombatHudStore({ adapter });
  store.initialize();

  const el = document.createElement("div");
  el.className = cls("ohud-hud", "ohud-module");
  el.setAttribute("data-module", moduleId);
  root.appendChild(el);

  const tooltip = createTooltip(el);
  let toastTimer = null;

  function controlsHtml() {
    // Only the Player module carries the global HUD controls.
    if (moduleId !== "player") return "";
    return `<div class="ohud-module-controls">
      <button type="button" class="ohud-icon-btn" data-action="arrange" data-tip-title="Arrange HUD" data-tip-lines="Drag modules to reposition the HUD">${ICON_GRID}</button>
      <button type="button" class="ohud-icon-btn" data-action="collapse" aria-label="Collapse HUD" data-tip-title="Collapse HUD">${ICON_CARET_DOWN}</button>
    </div>`;
  }

  function bodyHtml(state) {
    const mode = resolveBodyMode(state);
    if (mode === "ready") {
      const fn = BLOCK_RENDERERS[moduleId];
      return fn ? fn(state) : "";
    }
    // Non-ready: the Player module shows the calm state; others stay muted/empty
    // (the map still reads through the gaps between modules).
    if (moduleId === "player") {
      const inner = mode === "error" ? renderErrorState(state)
        : mode === "loading" ? renderLoadingState()
        : renderEmptyState(state);
      return `<div class="ohud-state-wrap">${inner}</div>`;
    }
    return `<section class="ohud-panel ohud-panel--muted" data-block="${moduleId}"><div class="ohud-muted-fill">—</div></section>`;
  }

  function render() {
    const state = store.getState();
    el.setAttribute("data-body", resolveBodyMode(state));
    el.innerHTML = `${bodyHtml(state)}${controlsHtml()}<div class="ohud-toast" hidden></div>`;
  }

  function showToast(text) {
    const toast = el.querySelector(".ohud-toast");
    if (!toast) return;
    toast.textContent = text;
    toast.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { if (toast) toast.hidden = true; }, 1800);
  }

  function onClick(e) {
    const t = e.target.closest("[data-action]");
    if (!t) return;
    switch (t.getAttribute("data-action")) {
      case "arrange": integration.onArrange && integration.onArrange(); break;
      case "collapse": integration.onCollapse && integration.onCollapse(true); break;
      case "primary":
        if (!t.classList.contains("is-disabled")) showToast("Action resolution arrives in a later phase");
        break;
      default: break;
    }
  }
  el.addEventListener("click", onClick);

  const unsubscribe = store.subscribe(render);
  render();

  return {
    store,
    unmount() {
      unsubscribe();
      tooltip.destroy();
      el.removeEventListener("click", onClick);
      if (toastTimer) clearTimeout(toastTimer);
      store.dispose();
      el.remove();
    },
  };
}
