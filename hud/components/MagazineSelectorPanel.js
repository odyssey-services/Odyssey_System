import { selectVisibleReserveMagazines } from "../core/combatHudSelectors.js";
import { esc, cls } from "./hudDom.js";
import { panel } from "./HudPanel.js";

function reserveOption(mag, selected) {
  const desc = mag.description || mag.ammoType || "Magazine";
  const rounds = `${Number(mag.current ?? 0)}/${Number(mag.max ?? 0)}`;
  return `<button type="button" class="${cls("ohud-reserve-mag", selected ? "is-selected" : "")}"
    data-action="select-reload-mag" data-magazine-id="${esc(mag.id)}" title="${esc(desc)}">
    <span class="ohud-reserve-mag-desc">${esc(desc)}</span>
    <span class="ohud-reserve-mag-rounds">${esc(rounds)}</span>
  </button>`;
}

export function renderMagazineSelectorPanel(state) {
  const reserve = selectVisibleReserveMagazines(state);

  if (!reserve.length) {
    return panel({
      key: "gun-magazine-selector",
      label: "Spare Magazines",
      bodyHtml: `<div class="ohud-reserve-list is-empty">No compatible spare magazines</div>`,
    });
  }

  return panel({
    key: "gun-magazine-selector",
    label: "Spare Magazines",
    bodyHtml: `<div class="ohud-reserve-list">${reserve.map((mag) => reserveOption(mag, false)).join("")}</div>`,
  });
}
