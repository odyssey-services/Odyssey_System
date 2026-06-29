import { esc, cls } from "./hudDom.js";
import { panel } from "./HudPanel.js";

function weaponOption(option) {
  const ammoLabel = option.ammoLabel || "—";
  return `<button type="button" class="${cls("ohud-weapon-option", option.selected ? "is-selected" : "")}"
    data-action="select-weapon" data-weapon-id="${esc(option.id)}" title="${esc(option.name)}">
    <span class="ohud-weapon-option-name">${esc(option.name)}</span>
    ${option.type ? `<span class="ohud-weapon-option-type">${esc(option.type)}</span>` : ""}
    <span class="ohud-weapon-option-ammo">${esc(ammoLabel)}</span>
  </button>`;
}

export function renderWeaponSelectorPanel(state) {
  const availableWeapons = Array.isArray(state?.snapshot?.weapon?.available)
    ? state.snapshot.weapon.available
    : [];

  if (!availableWeapons.length) {
    return panel({
      key: "gun-weapon-selector",
      label: "Weapons",
      bodyHtml: `<div class="ohud-weapon-list is-empty">No weapons available</div>`,
    });
  }

  return panel({
    key: "gun-weapon-selector",
    label: "Weapons",
    bodyHtml: `<div class="ohud-weapon-list">${availableWeapons.map(weaponOption).join("")}</div>`,
  });
}
