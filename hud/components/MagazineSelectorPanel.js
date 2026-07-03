// Combat HUD — Magazine Selector companion popover (Phase 3).
//
// Ephemeral popover that opens above the magazine card in the Gun module when
// the player clicks the magazine-selector caret. Shows the list of available
// (compatible, non-empty, non-inserted) spare magazines — full-round OR
// partially-loaded, fullness is NEVER a selection requirement — each is
// clickable to select it for reload without triggering the reload immediately.

import { selectVisibleReserveMagazines } from "../core/combatHudSelectors.js";
import { esc, cls } from "./hudDom.js";
import { panel } from "./HudPanel.js";

/** Short ammo/caliber label for the left side of a row (e.g. ".45exp", "9x19 hj"). */
function reserveLabel(mag) {
  return mag.ammoType || mag.caliberLabel || mag.description || "Magazine";
}

function reserveOption(mag, selected) {
  const label = reserveLabel(mag);
  const rounds = `${Number(mag.current ?? 0)}/${Number(mag.max ?? 0)}`;
  return `<button type="button" class="${cls("ohud-reserve-mag", selected ? "is-selected" : "")}"
    data-action="select-reload-mag" data-magazine-id="${esc(mag.id)}" title="${esc(label)} — ${esc(rounds)}">
    <span class="ohud-reserve-mag-label">${esc(label)}</span>
    <span class="ohud-reserve-mag-rounds">${esc(rounds)}</span>
  </button>`;
}

export function renderMagazineSelectorPanel(state) {
  // No live snapshot yet → controlled loading state, not a false "no spares".
  if (!state || !state.snapshot || !state.snapshot.weapon) {
    return panel({
      key: "gun-magazine-selector",
      label: "Spare Magazines",
      bodyHtml: `<div class="ohud-reserve-list is-loading">Loading magazines…</div>`,
    });
  }

  const reserve = selectVisibleReserveMagazines(state);

  if (!reserve.length) {
    return panel({
      key: "gun-magazine-selector",
      label: "Spare Magazines",
      bodyHtml: `<div class="ohud-reserve-list is-empty">No compatible spare magazines</div>`,
    });
  }

  const selectedId = state?.ui?.selectedReloadMagazineId ?? null;
  const body = `<div class="ohud-reserve-list">${reserve.map((mag) => reserveOption(mag, mag.id === selectedId)).join("")}</div>`;
  return panel({ key: "gun-magazine-selector", label: "Spare Magazines", bodyHtml: body });
}
