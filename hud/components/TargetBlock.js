// Combat HUD - Target block (Phase 3B/3C, live targeting).
//
// Shows the current targeting state from the Phase 3B target-selection
// controller. When a target is selected, the humanoid silhouette renders with
// the active zone highlighted and every body zone directly clickable.

import { selectTargetView } from "../core/combatHudSelectors.js";
import { humanoidSvg, ICON_SHIELD } from "./hudIcons.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr } from "./hudDom.js";
import { zoneIdToSvgPart } from "../targeting/targetProfiles.js";

export function renderTargetBlock(state) {
  const tv = selectTargetView(state);

  if (!tv.hasTarget) {
    const picking = tv.isPicking;
    const body = `<div class="ohud-target is-empty">
      <div class="ohud-figure ohud-figure--ghost"><div class="ohud-figure-svg">${humanoidSvg({ neutral: true })}</div></div>
      <div class="ohud-target-hint">${picking ? "PICK A TARGET" : "No target selected"}</div>
      <button type="button" class="ohud-target-pick" data-action="${picking ? "cancel-target" : "pick-target"}">
        ${picking ? "Cancel" : "Pick target"}
      </button>
    </div>`;
    return panel({ key: "target", label: "Target", bodyHtml: body });
  }

  const distLabel = Number.isFinite(tv.distance) ? `${tv.distance} m` : "—";
  const svgPart = zoneIdToSvgPart(tv.bodyPartId);

  const body = `<div class="ohud-target">
    <div class="ohud-figure ohud-figure--targetable">
      <div class="ohud-figure-svg">${humanoidSvg({ neutral: true, highlight: svgPart, targetable: true })}</div>
      <div class="ohud-figure-shield" aria-hidden="true"${tipAttr("Target shield", ["Defence detail hidden for non-owned entities"])}>${ICON_SHIELD}</div>
    </div>
    <div class="ohud-target-meta">
      <div class="ohud-target-name" title="${esc(tv.name)}">${esc(tv.name)}</div>
      <div class="ohud-target-sub">
        <span class="ohud-target-zone"${tipAttr("Aimed zone", ["Click a body zone on the silhouette"])}>${esc(tv.bodyPartLabel)}</span>
        <span class="ohud-target-dist"${tipAttr("Distance to target", [])}>${esc(distLabel)}</span>
      </div>
      <button type="button" class="ohud-target-clear" data-action="clear-target"${tipAttr("Clear target", [])}>Clear</button>
    </div>
  </div>`;

  return panel({ key: "target", label: "Target", bodyHtml: body });
}
