// Combat HUD — development diagnostics panel (Phase 0).
//
// This is NOT the HUD. It is a throwaway developer tool to exercise the store,
// adapter, scenarios and selectors without any backend. It must never be wired
// into the player-facing production flow.
//
// Manual mounting (no build/main.js changes required):
//   import { mountCombatHudDevPanel } from "./hud/dev/mountCombatHudDevPanel.js";
//   mountCombatHudDevPanel({ root: document.body });
// See docs/combat-hud-phase-0.md for the documented dev path.
//
// Browser-only (uses DOM). Styles are injected inline so the module can be
// imported standalone without a CSS bundling step. The pure core/adapters/
// models it depends on remain DOM-free.

import { createMockCombatHudAdapter } from "../adapters/mockCombatHudAdapter.js";
import { createCombatHudStore } from "../core/combatHudStore.js";
import { listScenarios, DEFAULT_SCENARIO_ID } from "../models/combatHudMockScenarios.js";
import { VIEWER_ROLES } from "../models/combatHudContracts.js";
import {
  selectHudMode,
  selectCurrentEntity,
  selectCanAct,
  selectDisabledReason,
  selectCurrentActionCost,
  selectVisibleReserveMagazines,
  selectCompactBattleLog,
  selectQuickSlots,
  selectEmptyReason,
} from "../core/combatHudSelectors.js";
import { describeEmptyReason } from "../core/combatHudActions.js";
import { prettyJson, escapeHtml } from "../../utils/json.js";

const PANEL_STYLE = `
.ohud-dev { position: fixed; top: 12px; right: 12px; width: 420px; max-height: 92vh;
  display: flex; flex-direction: column; gap: 8px; z-index: 99999;
  font-family: -apple-system, "Segoe UI", Roboto, sans-serif; font-size: 12px;
  color: #e8ecf4; background: rgba(10,12,20,0.96); border: 1px solid rgba(255,255,255,0.16);
  border-radius: 8px; padding: 12px; box-shadow: 0 6px 24px rgba(0,0,0,0.5); }
.ohud-dev h3 { margin: 0 0 4px; font-size: 13px; letter-spacing: 0.3px; }
.ohud-dev .row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.ohud-dev label { color: #9aa3b8; min-width: 64px; }
.ohud-dev select, .ohud-dev button { font: inherit; background: rgba(32,38,56,0.96);
  color: #e8ecf4; border: 1px solid rgba(255,255,255,0.18); border-radius: 5px; padding: 4px 8px; cursor: pointer; }
.ohud-dev button.active { background: #e94560; border-color: #e94560; }
.ohud-dev .stat { display: flex; justify-content: space-between; gap: 8px; padding: 2px 0;
  border-bottom: 1px dashed rgba(255,255,255,0.08); }
.ohud-dev .stat b { color: #9aa3b8; font-weight: 600; }
.ohud-dev .ready { color: #2ecc71; } .ohud-dev .empty { color: #f5a623; } .ohud-dev .error { color: #e74c3c; }
.ohud-dev pre { margin: 0; max-height: 40vh; overflow: auto; background: rgba(0,0,0,0.4);
  padding: 8px; border-radius: 5px; font-size: 11px; line-height: 1.35; white-space: pre-wrap; word-break: break-word; }
`;

function injectStyleOnce() {
  if (document.getElementById("ohud-dev-style")) return;
  const el = document.createElement("style");
  el.id = "ohud-dev-style";
  el.textContent = PANEL_STYLE;
  document.head.appendChild(el);
}

/**
 * Mount the dev panel.
 * @param {{ root?: HTMLElement, store?: object, adapter?: object }} [options]
 * @returns {{ unmount: () => void, store: object }}
 */
export function mountCombatHudDevPanel(options = {}) {
  if (typeof document === "undefined") {
    throw new Error("mountCombatHudDevPanel requires a DOM environment.");
  }
  injectStyleOnce();

  const root = options.root ?? document.body;
  const adapter = options.adapter ?? createMockCombatHudAdapter({ scenarioId: DEFAULT_SCENARIO_ID });
  const store = options.store ?? createCombatHudStore({ adapter });

  const container = document.createElement("div");
  container.className = "ohud-dev";
  root.appendChild(container);

  let currentRole = VIEWER_ROLES.player;

  function render(state) {
    const mode = selectHudMode(state);
    const entity = selectCurrentEntity(state);
    const tokens = adapter.getSceneTokens();
    const emptyReason = selectEmptyReason(state);
    const statusClass = state.status === "ready" ? "ready" : state.status === "error" ? "error" : "empty";

    container.innerHTML = `
      <h3>⚔️ Combat HUD · Dev Panel <span style="color:#9aa3b8;font-weight:400">(Phase 0)</span></h3>

      <div class="row">
        <label>Scenario</label>
        <select data-role="scenario">
          ${listScenarios().map((s) => `<option value="${escapeHtml(s.id)}">${escapeHtml(s.label)}</option>`).join("")}
        </select>
      </div>

      <div class="row">
        <label>Viewer</label>
        <button data-role="role" data-value="player" class="${currentRole === "player" ? "active" : ""}">Player</button>
        <button data-role="role" data-value="gm" class="${currentRole === "gm" ? "active" : ""}">GM</button>
      </div>

      <div class="row">
        <label>Token</label>
        <select data-role="token">
          <option value="">— none —</option>
          ${tokens.map((t) => `<option value="${escapeHtml(t.tokenId)}" ${t.tokenId === state.selectedTokenId ? "selected" : ""}>${escapeHtml(t.name)} (${escapeHtml(t.kind)})</option>`).join("")}
        </select>
      </div>

      <div class="row">
        <button data-role="reset-draft">Reset draft</button>
        <button data-role="reset-store">Reset store</button>
      </div>

      <div>
        <div class="stat"><b>status</b><span class="${statusClass}">${escapeHtml(mode)} / ${escapeHtml(state.status)}</span></div>
        <div class="stat"><b>source</b><span>${escapeHtml(state.source)}</span></div>
        <div class="stat"><b>viewer</b><span>${escapeHtml(state.viewer.playerName)} · ${escapeHtml(state.viewer.role)}</span></div>
        <div class="stat"><b>access</b><span>${state.access.canViewSelectedCharacter ? "✓ ready" : "✗ " + escapeHtml(describeEmptyReason(emptyReason) || state.access.reason || "—")}</span></div>
        <div class="stat"><b>entity</b><span>${entity ? escapeHtml(entity.summary.name + " · " + entity.summary.characterType) : "—"}</span></div>
        <div class="stat"><b>canAct</b><span>${selectCanAct(state) ? "yes" : "no"}</span></div>
        <div class="stat"><b>actionCost</b><span>${escapeHtml(selectCurrentActionCost(state))}</span></div>
        <div class="stat"><b>disabledReason</b><span>${escapeHtml(selectDisabledReason(state) || "— (enabled)")}</span></div>
        <div class="stat"><b>reserveMags</b><span>${selectVisibleReserveMagazines(state).map((m) => escapeHtml(m.id)).join(", ") || "—"}</span></div>
        <div class="stat"><b>quickSlots</b><span>${selectQuickSlots(state).filter((q) => q.skillId).length} filled</span></div>
        <div class="stat"><b>log (compact)</b><span>${selectCompactBattleLog(state).length} entries</span></div>
      </div>

      <pre>${escapeHtml(prettyJson(state))}</pre>
    `;

    // Restore scenario select value (re-render resets it).
    const scenarioSel = container.querySelector('[data-role="scenario"]');
    if (scenarioSel) scenarioSel.value = container.dataset.scenarioId ?? DEFAULT_SCENARIO_ID;
  }

  function onClick(e) {
    const btn = e.target.closest("button");
    if (!btn) return;
    const role = btn.dataset.role;
    if (role === "role") {
      currentRole = btn.dataset.value;
      store.setViewerRole(currentRole);
    } else if (role === "reset-draft") {
      store.resetActionDraft();
    } else if (role === "reset-store") {
      store.setMockScenario(container.dataset.scenarioId ?? DEFAULT_SCENARIO_ID);
      currentRole = VIEWER_ROLES.player;
    }
  }

  function onChange(e) {
    const sel = e.target.closest("select");
    if (!sel) return;
    if (sel.dataset.role === "scenario") {
      container.dataset.scenarioId = sel.value;
      currentRole = VIEWER_ROLES.player; // scenarios reset to their default role
      store.setMockScenario(sel.value);
    } else if (sel.dataset.role === "token") {
      store.selectToken(sel.value || null);
    }
  }

  container.addEventListener("click", onClick);
  container.addEventListener("change", onChange);
  const unsubscribe = store.subscribe(render);

  container.dataset.scenarioId = DEFAULT_SCENARIO_ID;
  store.initialize();
  render(store.getState());

  return {
    store,
    unmount() {
      unsubscribe();
      container.removeEventListener("click", onClick);
      container.removeEventListener("change", onChange);
      container.remove();
      store.dispose();
    },
  };
}
