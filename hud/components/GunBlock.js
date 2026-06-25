// Combat HUD — Gun block (Phase 2, read-only).
//
// Mirrors the reference: a large weapon-silhouette card on the left with a
// (read-only) dropdown caret and a fire-mode indicator, plus a narrow right
// column — magazine/ammo-type card on top, a big ammo counter below with a
// reload glyph. No real magazine swap / reload happens in Phase 2.

import { selectVisibleReserveMagazines } from "../core/combatHudSelectors.js";
import { weaponSvg, ICON_MAGAZINE, ICON_CARET_DOWN, ICON_RELOAD } from "./hudIcons.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr, cls } from "./hudDom.js";

function fireModeLetter(mode) {
  if (!mode) return "—";
  const m = String(mode).toLowerCase();
  if (m.startsWith("semi")) return "S";
  if (m.startsWith("burst")) return "B";
  if (m.startsWith("auto")) return "A";
  if (m.startsWith("full")) return "F";
  return String(mode).charAt(0).toUpperCase();
}

function emptyGun() {
  return panel({
    key: "gun",
    label: "WEAPON",
    bodyHtml: `<div class="ohud-gun is-disabled"><div class="ohud-gun-main"><div class="ohud-muted-fill">NO WEAPON</div></div></div>`,
  });
}

export function renderGunBlock(state) {
  const weapon = state?.snapshot?.weapon?.primary ?? null;
  const secondary = state?.snapshot?.weapon?.secondary ?? null;
  if (!weapon) return emptyGun();

  const mag = weapon.loadedMagazine ?? null;
  const usesMag = Boolean(weapon.usesMagazine);
  const ammoCur = mag ? Number(mag.current ?? 0) : Number(weapon.ammo?.current ?? 0);
  const ammoMax = mag ? Number(mag.max ?? 0) : Number(weapon.ammo?.max ?? 0);
  const ammoType = mag?.ammoType ?? (weapon.usesConsumable ? "item" : "—");
  const isEmpty = weapon.requiresAmmo && ammoCur <= 0;
  const reserve = selectVisibleReserveMagazines(state);
  const canReload = Boolean(weapon.canReload) && reserve.length > 0;
  const disabled = Boolean(weapon.disabledReason) || (isEmpty && !canReload);
  const fm = fireModeLetter(weapon.currentFireMode);

  const fireModeTip = tipAttr("Fire mode", [
    `Current: ${weapon.currentFireMode ?? "—"}`,
    weapon.fireModes?.length ? `Available: ${weapon.fireModes.join(", ")}` : "",
  ]);
  const swapTip = tipAttr("Magazine / ammo", [
    "Swap available in a later phase",
    reserve.length ? `${reserve.length} compatible magazine(s) in reserve` : "No spare magazines",
  ]);

  const mainCard = `
    <div class="ohud-gun-main"${tipAttr(weapon.name, [weapon.currentFireMode ? `Mode: ${weapon.currentFireMode}` : ""])}>
      <span class="ohud-gun-name">${esc(weapon.name)}</span>
      <span class="ohud-gun-caret is-readonly" aria-hidden="true"${swapTip}>${ICON_CARET_DOWN}</span>
      <span class="ohud-gun-silhouette">${weaponSvg(weapon.svgRef)}</span>
      <span class="ohud-firemode is-readonly"${fireModeTip}><span class="ohud-firemode-knob"></span><span class="ohud-firemode-letter">${esc(fm)}</span></span>
      ${secondary ? `<span class="ohud-gun-secondary"${tipAttr("Secondary weapon", [esc(secondary.name || "")])}>2nd</span>` : ""}
    </div>`;

  const magCard = `
    <div class="ohud-mag-card${usesMag ? "" : " is-consumable"}"${swapTip}>
      <span class="ohud-mag-icon" aria-hidden="true">${usesMag ? ICON_MAGAZINE : ""}</span>
      ${usesMag ? `<span class="ohud-mag-caret is-readonly" aria-hidden="true">${ICON_CARET_DOWN}</span>` : ""}
      <span class="ohud-mag-type">${esc(ammoType)}</span>
    </div>`;

  const ammoCard = `
    <div class="ohud-ammo-card">
      <span class="ohud-ammo-head">
        <span class="ohud-ammo-label">ammo</span>
        <span class="${cls("ohud-ammo-reload", "is-readonly", canReload ? "" : "is-off")}" aria-hidden="true"${tipAttr("Reload", [canReload ? "Reserve magazine available" : "No reload available", "Reload arrives in a later phase"])}>${ICON_RELOAD}</span>
      </span>
      <span class="${cls("ohud-ammo-count", isEmpty ? "ohud-ammo-count--empty" : "")}">
        <span class="ohud-ammo-cur">${ammoCur}</span><span class="ohud-ammo-max">/${ammoMax}</span>
      </span>
    </div>`;

  const body = `<div class="${cls("ohud-gun", disabled ? "is-disabled" : "")}"${disabled ? tipAttr("Weapon unavailable", [esc(weapon.disabledReason || "Out of ammo")]) : ""}>
    ${mainCard}
    <div class="ohud-gun-side">${magCard}${ammoCard}</div>
  </div>`;

  return panel({ key: "gun", label: "WEAPON", bodyHtml: body });
}
