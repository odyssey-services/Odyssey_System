// Combat HUD — layout orchestrator (Phase 2).
//
// Composes the module blocks into the responsive bottom HUD, wires read-only
// interactions (hover tooltips, dev scenario/role, collapse, local battle-log
// expand) and re-renders on store changes + viewport resize. It owns NO
// business logic — every value comes from the pure Phase 0 selectors / block
// components. It does NOT import the OBR SDK; OBR coupling stays in the
// controller/page and is injected via callbacks.

import { listScenarios } from "../models/combatHudMockScenarios.js";
import { resolveLayoutMode } from "../overlay/overlayConstants.js";
import {
  resolveBodyMode,
  resolveBattleLogMode,
  battleLogIsColumn,
} from "./hudLayoutModel.js";

import { renderPlayerBlock } from "./PlayerBlock.js";
import { renderGunBlock } from "./GunBlock.js";
import { renderSkillBlock } from "./SkillBlock.js";
import { renderTargetBlock } from "./TargetBlock.js";
import { renderModifierBlock } from "./ModifierBlock.js";
import { renderActionBlock } from "./ActionBlock.js";
import { renderBattleLogBlock } from "./BattleLogBlock.js";
import { renderEmptyState, renderErrorState, renderLoadingState } from "./EmptyHudState.js";
import { createTooltip } from "./Tooltip.js";
import { ICON_MARK, ICON_PENCIL, ICON_CARET_DOWN } from "./hudIcons.js";
import { esc, cls } from "./hudDom.js";

/**
 * @param {{
 *   store: object,
 *   obrAvailable?: boolean,
 *   devControls?: boolean,
 *   scenarioId?: string,
 *   onScenario?: (id:string)=>void,
 *   onRole?: (role:string)=>void,
 *   onCollapse?: (collapsed:boolean)=>void,
 * }} cfg
 */
export function createCombatHudLayout(cfg) {
  const {
    store, obrAvailable = true, devControls = true,
    onScenario, onRole, onCollapse,
  } = cfg;

  const el = document.createElement("div");
  el.className = "ohud-hud";

  // Local, overlay-only UI state (never written to the Phase 0 store / backend).
  let currentScenarioId = cfg.scenarioId ?? "A";
  let devOpen = false;
  let battleLogExpanded = false;
  let toastTimer = null;

  const tooltip = createTooltip(el);

  function currentWidth() {
    return (typeof window !== "undefined" && window.innerWidth) || el.clientWidth || 1280;
  }

  function devStrip(state) {
    if (!devControls) return "";
    const role = state?.viewer?.role === "gm" ? "gm" : "player";
    const options = listScenarios()
      .map((s) => `<option value="${esc(s.id)}" ${s.id === currentScenarioId ? "selected" : ""}>${esc(s.label)}</option>`)
      .join("");
    return `<div class="${cls("ohud-dev", devOpen ? "is-open" : "")}">
      <button type="button" class="ohud-dev-btn" data-action="dev-toggle" aria-expanded="${devOpen}" data-tip-title="Developer tools" data-tip-lines="Scenario + role (dev only)">
        ${ICON_PENCIL}<span class="ohud-dev-btn-label">DEV</span>
      </button>
      ${devOpen ? `<div class="ohud-dev-strip">
        <label class="ohud-dev-field"><span>Scenario</span>
          <select class="ohud-select" data-action="scenario">${options}</select>
        </label>
        <span class="ohud-dev-roles">
          <button type="button" class="${cls("ohud-chip", role === "player" ? "is-on" : "")}" data-action="role" data-value="player">Player</button>
          <button type="button" class="${cls("ohud-chip", role === "gm" ? "is-on" : "")}" data-action="role" data-value="gm">GM</button>
        </span>
      </div>` : ""}
    </div>`;
  }

  function controls(state) {
    const fallback = obrAvailable ? "" : `<span class="ohud-fallback">OBR unavailable — local HUD preview</span>`;
    const scenarioLabel = (listScenarios().find((s) => s.id === currentScenarioId) || {}).label || "";
    return `<div class="ohud-controls">
      <span class="ohud-brand">
        <span class="ohud-brand-mark" aria-hidden="true">${ICON_MARK}</span>
        <span class="ohud-brand-text">ODYSSEY</span>
        <span class="ohud-brand-sub">${esc(scenarioLabel)}</span>
      </span>
      ${fallback}
      <span class="ohud-controls-right">
        ${devStrip(state)}
        <button type="button" class="ohud-collapse" data-action="collapse" aria-label="Collapse HUD" data-tip-title="Collapse HUD">${ICON_CARET_DOWN}</button>
      </span>
    </div>`;
  }

  function readyGrid(state, mode) {
    const logMode = resolveBattleLogMode(mode, battleLogExpanded);
    const logInColumn = battleLogIsColumn(mode);
    const logHtml = renderBattleLogBlock(state, logMode);

    // Modifier + Action are direct grid children; CSS grid-template-areas
    // stack them into the right column (wide/medium) or split them across the
    // second row (compact/mini). In wide mode the log is its own column;
    // otherwise it floats as a button/panel layered over the grid so it never
    // breaks the row math or creates an empty clickable area.
    return `<div class="${cls("ohud-grid", `ohud-grid--${mode}`)}">
      ${renderPlayerBlock(state)}
      ${renderGunBlock(state)}
      ${renderSkillBlock(state)}
      ${renderTargetBlock(state)}
      ${renderModifierBlock(state)}
      ${renderActionBlock(state)}
      ${logInColumn ? logHtml : ""}
    </div>
    ${logInColumn ? "" : `<div class="ohud-log-float">${logHtml}</div>`}`;
  }

  function bodyHtml(state, mode) {
    const bodyMode = resolveBodyMode(state);
    if (bodyMode === "ready") return readyGrid(state, mode);
    if (bodyMode === "empty") return `<div class="ohud-state-wrap">${renderEmptyState(state)}</div>`;
    if (bodyMode === "error") return `<div class="ohud-state-wrap">${renderErrorState(state)}</div>`;
    return `<div class="ohud-state-wrap">${renderLoadingState()}</div>`;
  }

  function render() {
    const state = store.getState();
    const mode = resolveLayoutMode(currentWidth());
    el.setAttribute("data-mode", mode);
    el.setAttribute("data-body", resolveBodyMode(state));
    el.innerHTML = `${controls(state)}${bodyHtml(state, mode)}<div class="ohud-toast" hidden></div>`;
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
    const action = t.getAttribute("data-action");
    switch (action) {
      case "collapse": onCollapse && onCollapse(true); break;
      case "dev-toggle": devOpen = !devOpen; render(); break;
      case "role": onRole && onRole(t.getAttribute("data-value")); break;
      case "toggle-log": battleLogExpanded = !battleLogExpanded; render(); break;
      case "primary":
        if (t.classList.contains("is-disabled")) return;
        showToast("Action resolution arrives in a later phase");
        break;
      default: break;
    }
  }

  function onChange(e) {
    const t = e.target.closest("[data-action='scenario']");
    if (!t) return;
    currentScenarioId = t.value;
    battleLogExpanded = false;
    onScenario && onScenario(currentScenarioId);
  }

  let resizeRaf = null;
  function onResize() {
    if (resizeRaf) return;
    resizeRaf = requestAnimationFrame(() => { resizeRaf = null; render(); });
  }

  el.addEventListener("click", onClick);
  el.addEventListener("change", onChange);
  if (typeof window !== "undefined") window.addEventListener("resize", onResize);

  // Re-render whenever the store changes (scenario/role/selection/etc.).
  const unsubscribe = store.subscribe(render);
  render();

  return {
    el,
    setScenarioId(id) { currentScenarioId = id; render(); },
    destroy() {
      unsubscribe();
      tooltip.destroy();
      el.removeEventListener("click", onClick);
      el.removeEventListener("change", onChange);
      if (typeof window !== "undefined") window.removeEventListener("resize", onResize);
      if (toastTimer) clearTimeout(toastTimer);
      el.remove();
    },
  };
}
