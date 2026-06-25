// Combat HUD — Action block (Phase 2, read-only preview).
//
// The finishing element on the right: one large primary button whose verb is
// derived from the drafted action (ATTACK/THROW/CAST/USE/ACTIVATE), a
// MAIN/MOVE economy hint, and a readable disabled reason. In Phase 2 the button
// does NOT resolve combat — clicking only surfaces a transient "later phase"
// note (handled by the layout). When the action can't be taken it renders
// disabled with the reason.

import {
  selectActionLabel,
  selectCanAct,
  selectDisabledReason,
  selectCurrentActionCost,
} from "../core/combatHudSelectors.js";
import { esc, tipAttr, cls } from "./hudDom.js";

export function renderActionBlock(state) {
  const label = selectActionLabel(state);
  const can = selectCanAct(state);
  const reason = selectDisabledReason(state);
  const disabled = !can || Boolean(reason);
  const cost = selectCurrentActionCost(state);

  const costHint = `<span class="ohud-action-econ">
    <span class="${cls("ohud-econ-pip", cost === "MAIN" ? "is-spend" : "")}">MAIN</span>
    <span class="${cls("ohud-econ-pip", cost === "MOVE" ? "is-spend" : "")}">MOVE</span>
  </span>`;

  const tip = disabled
    ? tipAttr("Action unavailable", [esc(reason || "Not available")])
    : tipAttr(`${label}`, [`Costs: ${cost}`, "Resolution arrives in a later phase"]);

  const reasonLine = disabled && reason
    ? `<div class="ohud-action-reason">${esc(reason)}</div>`
    : `<div class="ohud-action-reason ohud-action-reason--ok">Preview only</div>`;

  return `<section class="ohud-panel ohud-panel--action" data-block="action">
    <button type="button" class="${cls("ohud-action-btn", disabled ? "is-disabled" : "is-ready")}"
      data-action="primary" ${disabled ? "aria-disabled=\"true\"" : ""}${tip}>
      <span class="ohud-action-label">${esc(label)}</span>
    </button>
    ${costHint}
    ${reasonLine}
  </section>`;
}
