// Combat HUD — Target block (Phase 2 · 2.1, read-only).
//
// Compact target module (~100×95). Shows the prospective target derived from
// the mock combat queue (silhouette + selected body zone). With no target it
// shows a small calm placeholder — never a big banner, never toggles real OBR
// targeting.

import { selectTargetView } from "../core/combatHudSelectors.js";
import { humanoidSvg, ICON_SHIELD } from "./hudIcons.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr } from "./hudDom.js";

export function renderTargetBlock(state) {
  const tv = selectTargetView(state);

  if (!tv.hasTarget) {
    const body = `<div class="ohud-target is-empty">
      <div class="ohud-figure ohud-figure--ghost"><div class="ohud-figure-svg">${humanoidSvg({ neutral: true })}</div></div>
      <div class="ohud-target-hint">No target</div>
    </div>`;
    return panel({ key: "target", label: "Target", bodyHtml: body });
  }

  const body = `<div class="ohud-target">
    <div class="ohud-figure">
      <div class="ohud-figure-svg">${humanoidSvg({ neutral: true, highlight: tv.bodyPartId })}</div>
      <div class="ohud-figure-shield" aria-hidden="true"${tipAttr("Target shield", ["Detail hidden for non-owned entity"])}>${ICON_SHIELD}</div>
    </div>
    <div class="ohud-target-meta">
      <div class="ohud-target-name" title="${esc(tv.name)}">${esc(tv.name)}</div>
      <div class="ohud-target-zone"${tipAttr("Aimed zone", ["Body-part targeting arrives in a later phase"])}>${esc(tv.bodyPartLabel)}</div>
    </div>
  </div>`;

  return panel({ key: "target", label: "Target", bodyHtml: body });
}
