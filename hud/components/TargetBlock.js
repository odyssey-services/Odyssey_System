// Combat HUD — Target block (Phase 3B, live targeting).
//
// Shows the current targeting state from the Phase 3B target-selection
// controller. When a target is selected, renders the humanoid silhouette with
// the active zone highlighted and six clickable zone chips for zone selection.
// Zone state is owned by the targeting controller — not DOM-local.

import { selectTargetView } from "../core/combatHudSelectors.js";
import { humanoidSvg, ICON_SHIELD } from "./hudIcons.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr, cls } from "./hudDom.js";
import { HUMANOID_PROFILE, zoneIdToSvgPart } from "../targeting/targetProfiles.js";

function zoneChip(zone, selectedZoneId) {
  const isSelected = zone.id === selectedZoneId;
  return `<button type="button" class="${cls("ohud-zone-chip", isSelected ? "is-selected" : "")}"
    data-action="select-target-zone" data-zone-id="${esc(zone.id)}"
    aria-pressed="${isSelected ? "true" : "false"}"
    ${tipAttr(zone.label, [])}>${esc(zone.label)}</button>`;
}

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
  const zones = HUMANOID_PROFILE.zones;
  const chips = zones.map((z) => zoneChip(z, tv.bodyPartId)).join("");

  const body = `<div class="ohud-target">
    <div class="ohud-figure">
      <div class="ohud-figure-svg">${humanoidSvg({ neutral: true, highlight: svgPart })}</div>
      <div class="ohud-figure-shield" aria-hidden="true"${tipAttr("Target shield", ["Defence detail unavailable for non-owned entities"])}>${ICON_SHIELD}</div>
    </div>
    <div class="ohud-target-meta">
      <div class="ohud-target-name" title="${esc(tv.name)}">${esc(tv.name)}</div>
      <div class="ohud-target-dist"${tipAttr("Distance to target", [])}>${esc(distLabel)}</div>
      <div class="ohud-zone-chips" role="group" aria-label="Target zone">${chips}</div>
      <button type="button" class="ohud-target-clear" data-action="clear-target"${tipAttr("Clear target", [])}>Clear</button>
    </div>
  </div>`;

  return panel({ key: "target", label: "Target", bodyHtml: body });
}
