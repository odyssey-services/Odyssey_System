// Combat HUD overlay — view renderer (Phase 1A).
//
// Pure DOM rendering for the placeholder shell. NO OBR SDK import here: all
// OBR coupling (popover resize, broadcast, availability) is injected by the
// caller (mountCombatHudOverlay) via callbacks. This keeps the view portable
// for standalone preview and avoids OBR-coupling the renderer.
//
// It reads from the Phase 0 store (pure) and a few Phase 0 selectors. It does
// NOT mutate Phase 0 contracts.

import { listScenarios } from "../models/combatHudMockScenarios.js";
import {
  selectHudMode,
  selectCurrentEntity,
  selectEmptyReason,
  selectIsViewerTurn,
} from "../core/combatHudSelectors.js";
import { describeEmptyReason } from "../core/combatHudActions.js";
import { escapeHtml } from "../../utils/json.js";

/** Map store state → a coarse status badge shown in the shell. */
function statusBadge(state) {
  const mode = selectHudMode(state);
  if (state.status === "error") return { label: "ERROR", cls: "error" };
  if (state.status === "ready") {
    return selectIsViewerTurn(state)
      ? { label: "READY", cls: "ready" }
      : { label: "WAITING", cls: "waiting" };
  }
  if (state.status === "empty") return { label: "EMPTY", cls: "empty" };
  if (mode === "loading") return { label: "…", cls: "muted" };
  return { label: "IDLE", cls: "muted" };
}

/**
 * Create the overlay view.
 * @param {{
 *   root: HTMLElement,
 *   store: object,
 *   scenarioId?: string,
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
    onCollapse, onScenario, onRole,
  } = cfg;

  const host = document.createElement("div");
  host.className = "odyssey-hud ohud-overlay";
  root.appendChild(host);

  let currentScenarioId = cfg.scenarioId ?? "A";

  function renderShell(state) {
    const entity = selectCurrentEntity(state);
    const badge = statusBadge(state);
    const emptyReason = selectEmptyReason(state);
    const charName = entity ? entity.summary.name : null;
    // Highlight the role chip from the authoritative store value so it stays
    // correct after restore and after a scenario change resets the role.
    const role = state?.viewer?.role === "gm" ? "gm" : "player";

    const scenarioOptions = listScenarios()
      .map((s) => `<option value="${escapeHtml(s.id)}" ${s.id === currentScenarioId ? "selected" : ""}>${escapeHtml(s.label)}</option>`)
      .join("");

    const fallbackBanner = obrAvailable
      ? ""
      : `<div class="ohud-fallback">OBR unavailable — local HUD preview</div>`;

    const charLine = charName
      ? `<span class="ohud-char">${escapeHtml(charName)}</span>`
      : `<span class="ohud-char ohud-char--none">${escapeHtml(describeEmptyReason(emptyReason) || "No controlled character selected")}</span>`;

    const devBar = devControls
      ? `<div class="ohud-dev-bar">
           <label class="ohud-dev-label">Scenario</label>
           <select class="ohud-select" data-ohud="scenario">${scenarioOptions}</select>
           <span class="ohud-dev-sep"></span>
           <button class="ohud-chip ${role === "player" ? "is-on" : ""}" data-ohud="role" data-value="player">Player</button>
           <button class="ohud-chip ${role === "gm" ? "is-on" : ""}" data-ohud="role" data-value="gm">GM</button>
         </div>`
      : "";

    host.innerHTML = `
      <section class="ohud-shell" role="region" aria-label="Odyssey Combat HUD">
        ${fallbackBanner}
        <div class="ohud-shell-row">
          <div class="ohud-brand">
            <span class="ohud-mark" aria-hidden="true">◆</span>
            <span class="ohud-titles">
              <span class="ohud-title">ODYSSEY COMBAT HUD</span>
              <span class="ohud-subtitle">${escapeHtml(scenarioLabel(currentScenarioId))}</span>
            </span>
          </div>

          <div class="ohud-center">
            <span class="ohud-badge ohud-badge--${badge.cls}">${escapeHtml(badge.label)}</span>
            ${charLine}
          </div>

          <div class="ohud-actions">
            ${devBar}
            <button class="ohud-collapse" data-ohud="collapse" title="Collapse HUD" aria-label="Collapse HUD">
              <span aria-hidden="true">▾</span>
            </button>
          </div>
        </div>
        <div class="ohud-placeholder-note">Placeholder shell — Player / Gun / Skill / Target blocks arrive in Phase 2.</div>
      </section>
    `;
  }

  function renderPill() {
    host.innerHTML = `
      <button class="ohud-pill" data-ohud="reopen" title="Open Odyssey Combat HUD" aria-label="Open Odyssey Combat HUD">
        <span class="ohud-mark" aria-hidden="true">◆</span>
        <span class="ohud-pill-label">ODYSSEY</span>
      </button>
    `;
  }

  function render(state) {
    const collapsed = state?.ui?.isHudCollapsed;
    host.classList.toggle("is-collapsed", Boolean(collapsed));
    if (collapsed) {
      renderPill();
    } else {
      renderShell(state);
    }
  }

  function scenarioLabel(id) {
    const found = listScenarios().find((s) => s.id === id);
    return found ? found.label : `Scenario ${id}`;
  }

  function onClick(e) {
    const el = e.target.closest("[data-ohud]");
    if (!el) return;
    const kind = el.getAttribute("data-ohud");
    if (kind === "collapse") {
      onCollapse(true);
    } else if (kind === "reopen") {
      onCollapse(false);
    } else if (kind === "role") {
      onRole(el.getAttribute("data-value"));
    }
  }

  function onChange(e) {
    const el = e.target.closest("[data-ohud]");
    if (!el) return;
    if (el.getAttribute("data-ohud") === "scenario") {
      currentScenarioId = el.value;
      // Role is not reset here: a scenario change updates the store to the
      // scenario's default role, and the chip highlight reads from state.
      onScenario(currentScenarioId);
    }
  }

  host.addEventListener("click", onClick);
  host.addEventListener("change", onChange);

  const unsubscribe = store.subscribe(render);
  render(store.getState());

  return {
    render,
    setScenarioId(id) { currentScenarioId = id; render(store.getState()); },
    destroy() {
      unsubscribe();
      host.removeEventListener("click", onClick);
      host.removeEventListener("change", onChange);
      host.remove();
    },
  };
}
