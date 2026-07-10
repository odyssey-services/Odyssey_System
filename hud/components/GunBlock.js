// Combat HUD - Gun block (Phase 3, live weapon/magazine/ammo).
//
// Stable gun module showing weapon name + silhouette + fire mode (left) and
// magazine + ammo state (right). Weapon/magazine selectors are companion
// popovers, not part of this block.

import { selectVisibleReserveMagazines, selectSelectedReloadMagazine } from "../core/combatHudSelectors.js";
import { weaponSvg, ICON_MAGAZINE, ICON_CARET_DOWN, ICON_RELOAD } from "./hudIcons.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr, cls } from "./hudDom.js";

// Fire Mode v1 — the small fire-mode badge in the weapon-main card:
//   - no modes / not applicable (melee, cold weapons) → render nothing at all;
//   - exactly one mode → plain read-only label (no click, no selector);
//   - 2+ modes → interactive button opening the fire-mode companion popover.
// Never fabricates AUTO/SEMI/BURST — only real data from weapon.fireMode
// (see hud/runtime/runtimeBundleMapper.js readFireMode()).
function renderFireModeControl(weapon, syncPending = false) {
  const fm = weapon.fireMode;
  if (!fm || !fm.isApplicable) return "";
  const label = (fm.selectedCode || fm.selectedName || "").toUpperCase();
  const tip = tipAttr("Fire mode", [esc(syncPending ? "Synchronizing combat..." : (fm.selectedName || fm.selectedCode || ""))]);

  if (!fm.isSelectable) {
    return `<span class="ohud-firemode is-readonly"${tip}>
      <span class="ohud-firemode-knob"></span><span class="ohud-firemode-letter">${esc(label)}</span>
    </span>`;
  }

  return `<button type="button" class="ohud-firemode is-selectable" data-action="toggle-fire-mode-selector" aria-label="Choose fire mode"${tip}>
    <span class="ohud-firemode-knob"></span><span class="ohud-firemode-letter">${esc(label)}</span><span class="ohud-firemode-caret" aria-hidden="true">${ICON_CARET_DOWN}</span>
  </button>`;
}

function emptyGun() {
  return panel({
    key: "gun",
    label: "Weapon",
    bodyHtml: `<div class="ohud-gun is-disabled"><div class="ohud-gun-main"><div class="ohud-muted-fill">No weapon</div></div></div>`,
  });
}

export function renderGunBlock(state) {
  const weapon = state?.snapshot?.weapon?.primary ?? null;
  const secondary = state?.snapshot?.weapon?.secondary ?? null;
  const syncPending = state?.ui?.combatRuntimePending === true;
  if (!weapon) return emptyGun();

  const mag = weapon.loadedMagazine ?? null;
  const ammoCur = mag ? Number(mag.current ?? 0) : Number(weapon.ammo?.current ?? 0);
  const reserve = selectVisibleReserveMagazines(state);
  const selectedReload = selectSelectedReloadMagazine(state);
  const reloadMag = selectedReload ?? reserve[0] ?? null;
  // Phase 3E.0: during an active combat session the reload button also obeys
  // the server MOVE economy — the SAME reason wording the server gate uses,
  // never a fabricated UI reason.
  const hasReserve = reserve.length > 0;
  const canReload = Boolean(weapon.canReload) && hasReserve && !weapon.reloadBlockedReason;
  const reloadBlockReason = weapon.reloadBlockedReason
    ?? (Boolean(weapon.canReload) && hasReserve ? null : "No compatible magazine");
  const isEmpty = weapon.requiresAmmo && ammoCur <= 0;
  const disabled = Boolean(weapon.disabledReason) || (isEmpty && !canReload);

  const mainCard = `
    <div class="ohud-gun-main"${tipAttr(weapon.name, [weapon.currentFireMode ? `Mode: ${weapon.currentFireMode}` : ""])}>
      <span class="ohud-gun-name">${esc(weapon.name)}</span>
      <button type="button" class="ohud-gun-caret" data-action="toggle-weapon-selector" aria-label="Choose weapon" title="${esc(syncPending ? "Synchronizing combat..." : "Select a different weapon")}">${ICON_CARET_DOWN}</button>
      <span class="ohud-gun-silhouette">${weaponSvg(weapon.svgRef)}</span>
      ${renderFireModeControl(weapon, syncPending)}
      ${secondary ? `<span class="ohud-gun-secondary"${tipAttr("Secondary weapon", [esc(secondary.name || "")])}>2nd</span>` : ""}
    </div>`;

  const body = `<div class="${cls("ohud-gun", disabled ? "is-disabled" : "")}"${disabled ? tipAttr("Weapon unavailable", [esc(weapon.disabledReason || "Out of ammo")]) : ""}>
    ${mainCard}
    <div class="ohud-gun-side">${renderMagazineCard(weapon, reserve, reloadMag, syncPending)}${renderAmmoCard(weapon, mag, isEmpty, canReload, reloadMag, reloadBlockReason, syncPending)}</div>
  </div>`;

  return panel({ key: "gun", label: "Weapon", bodyHtml: body });
}

// The small magazine card shows ONLY the selected spare (reload candidate) —
// never the inserted magazine's ammo type. The ammo card below is the only
// place the inserted magazine's rounds are shown; the two must never mix.
function renderMagazineCard(weapon, reserve, reloadMag, syncPending = false) {
  const usesMag = Boolean(weapon.usesMagazine);
  const spareLabel = reloadMag ? (reloadMag.ammoType ?? reloadMag.caliberLabel ?? "—") : "—";

  return `<div class="ohud-mag-card${usesMag ? "" : " is-consumable"}">
    <span class="ohud-mag-icon" aria-hidden="true">${usesMag ? ICON_MAGAZINE : ""}</span>
    ${usesMag && reserve.length > 0 ? `<button type="button" class="ohud-mag-selector-btn" data-action="toggle-magazine-selector" aria-label="Choose magazine" title="${esc(syncPending ? "Synchronizing combat..." : "Select spare magazine")}">${ICON_CARET_DOWN}</button>` : ""}
    <span class="ohud-mag-type"${tipAttr("Selected spare magazine", [esc(spareLabel)])}>${esc(spareLabel)}</span>
  </div>`;
}

function renderAmmoCard(weapon, mag, isEmpty, canReload, reloadMag, reloadBlockReason, syncPending = false) {
  let ammoDisplay = "—";
  if (mag && (mag.current || mag.max)) {
    ammoDisplay = `${Number(mag.current ?? 0)}/${Number(mag.max ?? 0)}`;
  } else if (!mag && weapon.ammo && (weapon.ammo.current || weapon.ammo.max)) {
    ammoDisplay = `${Number(weapon.ammo.current ?? 0)}/${Number(weapon.ammo.max ?? 0)}`;
  }

  const reloadDisabled = syncPending || !canReload;
  const reloadTitle = syncPending ? "Synchronizing combat..." : (canReload ? "Insert compatible magazine" : (reloadBlockReason || "No compatible magazine"));

  return `<div class="ohud-ammo-card">
    <span class="ohud-ammo-head">
      <span class="ohud-ammo-label">ammo</span>
      <button type="button" class="${cls("ohud-ammo-reload", reloadDisabled ? "is-off" : "")}" data-action="reload" data-weapon-id="${esc(weapon.id)}" data-magazine-id="${esc(reloadMag?.id ?? "")}" ${reloadDisabled ? "disabled" : ""} title="${esc(reloadTitle)}">${ICON_RELOAD}</button>
    </span>
    <span class="${cls("ohud-ammo-count", isEmpty ? "ohud-ammo-count--empty" : "")}">
      <span>${esc(ammoDisplay)}</span>
    </span>
  </div>`;
}
