// Combat HUD - Weapon Selector companion popover (Phase 3).
//
// Ephemeral popover that opens above the Gun module when the player clicks
// the weapon-selector caret. Shows the list of available weapons; each weapon
// is clickable and broadcasts a select-weapon command back through the
// integration layer. The popover closes after selection or on Escape.

import { esc, cls } from "./hudDom.js";
import { panel } from "./HudPanel.js";

function weaponOption(option) {
  const ammoLabel = option.ammoLabel || "-";
  const selected = option.selected === true;
  const disabled = option.switchAllowed === false;
  const costLabel = selected
    ? "Active"
    : (option.switchCost === "free" ? "Free swap" : "Full MOVE");
  const title = disabled && option.switchBlockedReason
    ? `${option.name} - ${option.switchBlockedReason}`
    : option.name;

  return `<button type="button" class="${cls("ohud-weapon-option", selected ? "is-selected" : "", disabled ? "is-disabled" : "")}"
    data-action="select-weapon" data-weapon-id="${esc(option.id)}" title="${esc(title)}" ${disabled ? "disabled" : ""}>
    <span class="ohud-weapon-option-name">${esc(option.name)}</span>
    ${option.type ? `<span class="ohud-weapon-option-type">${esc(option.type)}</span>` : ""}
    <span class="ohud-weapon-option-ammo">${esc(ammoLabel)}</span>
    <span class="ohud-weapon-option-ammo">${esc(costLabel)}</span>
  </button>`;
}

export function renderWeaponSelectorPanel(state) {
  if (!state || !state.snapshot || !state.snapshot.weapon) {
    return panel({
      key: "gun-weapon-selector",
      label: "Weapons",
      bodyHtml: `<div class="ohud-weapon-list is-loading">Loading weapons...</div>`,
    });
  }

  const availableWeapons = Array.isArray(state.snapshot.weapon.available)
    ? state.snapshot.weapon.available
    : [];

  if (!availableWeapons.length) {
    return panel({
      key: "gun-weapon-selector",
      label: "Weapons",
      bodyHtml: `<div class="ohud-weapon-list is-empty">No weapons available</div>`,
    });
  }

  const body = `<div class="ohud-weapon-list">${availableWeapons.map(weaponOption).join("")}</div>`;
  return panel({ key: "gun-weapon-selector", label: "Weapons", bodyHtml: body });
}
