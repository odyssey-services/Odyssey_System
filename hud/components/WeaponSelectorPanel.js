// Combat HUD — Weapon Selector companion popover (Phase 3).
//
// Ephemeral popover that opens above the Gun module when the player clicks
// the weapon-selector caret. Shows the list of available weapons; each weapon
// is clickable and broadcasts a select-weapon command back through the
// integration layer. The popover closes after selection or on Escape.

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
  // `null`/no-snapshot state means the live weapon snapshot has not arrived yet
  // (companion opened a tick before the replay). Show a controlled loading
  // state — NEVER a false "No weapons available" while data is still in flight.
  if (!state || !state.snapshot || !state.snapshot.weapon) {
    return panel({
      key: "gun-weapon-selector",
      label: "Weapons",
      bodyHtml: `<div class="ohud-weapon-list is-loading">Loading weapons…</div>`,
    });
  }

  // A present snapshot with an empty list is a genuine "no weapons" result.
  // The list is NOT filtered by ammo/caliber/range — melee and magazine-less
  // weapons (e.g. Plasma Katana) are valid, selectable entries.
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
