// Combat HUD — Battle Log block (Phase 2, read-only).
//
// A compact, separate card (NOT a full-width strip). Shows the 3–5 most recent
// public log entries. No hidden HP / armour / dice math is ever shown. On
// medium/compact widths it collapses to a single "LOG" button that expands a
// floating panel locally (no second OBR popover, no backend).

import { selectCompactBattleLog } from "../core/combatHudSelectors.js";
import { ICON_LOG, ICON_CARET_UP, ICON_CARET_DOWN } from "./hudIcons.js";
import { esc, cls } from "./hudDom.js";

/** Result delta accent: misses are muted, hits/damage read as attack-coloured. */
function deltaClass(delta) {
  const d = String(delta || "").toLowerCase();
  if (!d) return "neutral";
  if (d.includes("miss")) return "miss";
  return "hit";
}

function entryRow(e) {
  if (e.kind === "system") {
    return `<li class="ohud-log-row ohud-log-row--system">▸ ${esc(e.action || e.summary)}</li>`;
  }
  if (e.kind === "narrative") {
    return `<li class="ohud-log-row ohud-log-row--narr">${esc(e.actor ? `${e.actor}: ` : "")}${esc(e.action || e.summary)}</li>`;
  }
  return `<li class="ohud-log-row">
    <span class="ohud-log-actor">${esc(e.actor)}</span>
    <span class="ohud-log-act">${esc(e.action)}</span>
    ${e.target ? `<span class="ohud-log-arrow">›</span><span class="ohud-log-target">${esc(e.target)}</span>` : ""}
    ${e.delta ? `<span class="ohud-log-delta ohud-log-delta--${deltaClass(e.delta)}">${esc(e.delta)}</span>` : ""}
  </li>`;
}

/**
 * @param {object} state
 * @param {"card"|"expanded"|"button"} logMode
 */
export function renderBattleLogBlock(state, logMode) {
  const entries = selectCompactBattleLog(state);
  const count = entries.length;

  if (logMode === "button") {
    return `<section class="ohud-panel ohud-panel--log ohud-log--button" data-block="log">
      <button type="button" class="ohud-log-toggle" data-action="toggle-log" data-tip-title="Battle log" data-tip-lines="${count} recent entr${count === 1 ? "y" : "ies"}">
        <span class="ohud-log-toggle-icon">${ICON_LOG}</span><span>LOG</span>
        ${count ? `<span class="ohud-log-badge">${count}</span>` : ""}
      </button>
    </section>`;
  }

  const expanded = logMode === "expanded";
  const list = entries.length
    ? `<ul class="ohud-log-list">${entries.map(entryRow).join("")}</ul>`
    : `<div class="ohud-log-empty">No combat log yet.</div>`;

  return `<section class="${cls("ohud-panel", "ohud-panel--log", expanded ? "ohud-log--expanded" : "ohud-log--card")}" data-block="log">
    <div class="ohud-panel-head">
      <span class="ohud-panel-label">BATTLE LOG</span>
      <button type="button" class="ohud-log-collapse" data-action="toggle-log" aria-label="${expanded ? "Collapse log" : "Expand log"}">
        ${expanded ? ICON_CARET_DOWN : ICON_CARET_UP}
      </button>
    </div>
    ${list}
  </section>`;
}
