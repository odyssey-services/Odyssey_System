// Combat HUD — Player block (Phase 2, read-only).
//
// Left-most module: character identity, turn state, body silhouette with zone
// conditions, shield + psi resources, MAIN/MOVE action economy, status chips.
// For a mech it swaps to the mech silhouette + a small PILOT strip.

import {
  selectCurrentEntity,
  selectPlayerStatusLabel,
  selectVisibleStatuses,
} from "../core/combatHudSelectors.js";
import { entitySilhouetteSvg } from "./hudIcons.js";
import { ICON_SHIELD } from "./hudIcons.js";
import { statusChip, overflowChip } from "./StatusChip.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr, cls } from "./hudDom.js";

function zonesMap(entity) {
  const map = {};
  for (const z of entity.zones ?? []) map[z.id] = z.state;
  return map;
}

function resourceBar(kind, label, res) {
  const maxRaw = res?.max;
  const curRaw = res?.current;
  const hasMax = Number.isFinite(Number(maxRaw)) && Number(maxRaw) > 0;
  const hasCur = Number.isFinite(Number(curRaw));
  const max = hasMax ? Math.max(0, Number(maxRaw)) : null;
  const cur = hasCur ? Math.max(0, Number(curRaw)) : null;
  const pct = max > 0 && cur != null ? Math.round((cur / max) * 100) : 0;
  const labelText = max != null && cur != null ? `${cur} / ${max}` : "—";
  return `<div class="ohud-res ohud-res--${kind}"${tipAttr(label, [labelText])}>
    <span class="ohud-res-label">${esc(label)}</span>
    <span class="ohud-res-track"><span class="ohud-res-fill" style="width:${pct}%"></span></span>
    <span class="ohud-res-num">${esc(cur != null ? cur : "—")}${max != null ? `<span class="ohud-res-max">/${max}</span>` : ""}</span>
  </div>`;
}

function actionPips(actions) {
  const pip = (on, name) =>
    `<span class="${cls("ohud-pip", on ? "is-on" : "is-off")}"${tipAttr(`${name} action`, [on ? "Available" : "Spent"])}>${name}</span>`;
  return `<div class="ohud-pips">${pip(Boolean(actions?.main), "MAIN")}${pip(Boolean(actions?.move), "MOVE")}</div>`;
}

function pilotStrip(pilot) {
  if (!pilot) return "";
  const psi = pilot.psi ? `${pilot.psi.current}/${pilot.psi.max}` : "";
  return `<div class="ohud-pilot"${tipAttr(`Pilot: ${pilot.name}`, [psi ? `Psi ${psi}` : ""])}>
    <span class="ohud-pilot-tag">PILOT</span>
    <span class="ohud-pilot-name">${esc(pilot.name)}</span>
    ${psi ? `<span class="ohud-pilot-psi">Ψ ${esc(psi)}</span>` : ""}
  </div>`;
}

export function renderPlayerBlock(state) {
  const entity = selectCurrentEntity(state);
  if (!entity) {
    return panel({ key: "player", label: "PLAYER", bodyHtml: `<div class="ohud-muted-fill">—</div>` });
  }
  const turn = selectPlayerStatusLabel(state);
  const turnClass = turn === "YOUR TURN" ? "active" : turn === "WAITING" ? "waiting" : turn === "GM VIEW" ? "gm" : "idle";
  const { shown, overflow } = selectVisibleStatuses(state, 5);
  const isMech = entity.summary?.svgRef === "mech";

  const headerRight = `<span class="ohud-turn ohud-turn--${turnClass}">${esc(turn)}</span>`;

  const body = `
    <div class="ohud-player-grid">
      <div class="ohud-figure">
        <div class="ohud-figure-svg">${entitySilhouetteSvg(entity.summary, { zones: zonesMap(entity) })}</div>
        <div class="ohud-figure-shield" aria-hidden="true">${ICON_SHIELD}</div>
      </div>
      <div class="ohud-player-stats">
        <div class="ohud-player-name" title="${esc(entity.summary.name)}">${esc(entity.summary.name)}</div>
        ${resourceBar("shield", "SHIELD", entity.shield)}
        ${entity.psi ? resourceBar("psi", "PSI", entity.psi) : ""}
        ${actionPips(entity.actions)}
      </div>
    </div>
    ${isMech ? pilotStrip(entity.pilot) : ""}
    <div class="ohud-statuses">
      ${shown.map(statusChip).join("")}
      ${overflowChip(overflow)}
    </div>
  `;

  return panel({
    key: "player",
    label: isMech ? "Mech" : "You",
    bodyHtml: body,
    headerRightHtml: headerRight,
  });
}
