// Combat HUD — Phase 3E.0 GM Combat Tracker panel (PURE render).
//
// GM-only companion popover content. Shows either the Start-Combat roster
// (linked characters of the current scene, checkbox list, dedupe already done
// by combatSessionPolicy.buildStartCandidates) or the live initiative list
// with Skip Turn / Force Next / End Combat. Displays ONLY safe fields:
// display name, initiative total, current/eligible markers — never private
// stats. Never rendered for a plain player (double-gated: the overlay
// controller refuses to open the popover, and this render refuses too).

import { esc, cls } from "../components/hudDom.js";
import { canSeeGmTracker } from "./combatSessionPolicy.js";

function candidateRow(candidate) {
  return `<label class="ohud-gmct-candidate">
    <input type="checkbox" data-gmct-candidate="${esc(candidate.characterId)}" checked />
    <span class="ohud-gmct-name">${esc(candidate.displayName || "Unnamed")}</span>
    <span class="ohud-gmct-tag">${candidate.isPlayerCharacter ? "PC" : "NPC"}</span>
  </label>`;
}

function participantRow(p) {
  return `<li class="${cls("ohud-gmct-row", p.isCurrent && "is-current", !p.isEligible && "is-skipped")}">
    <span class="ohud-gmct-marker">${p.isCurrent ? "▶" : ""}</span>
    <span class="ohud-gmct-name">${esc(p.displayName || "Unnamed")}</span>
    <span class="ohud-gmct-init">${p.initiativeTotal ?? "—"}</span>
    ${p.isEligible ? "" : `<span class="ohud-gmct-tag is-skip">SKIP</span>`}
  </li>`;
}

/**
 * @param {{ session:object|null, candidates:Array<object>, viewerRole:string, busy?:boolean }} input
 */
export function renderGmCombatTracker({ session, candidates, viewerRole, busy = false } = {}) {
  if (!canSeeGmTracker(viewerRole)) {
    return `<section class="ohud-panel ohud-gmct" data-block="gm-combat-tracker">
      <div class="ohud-gmct-denied">GM only.</div>
    </section>`;
  }

  const active = !!session && session.exists === true && session.status === "active";

  if (!active) {
    const list = Array.isArray(candidates) && candidates.length
      ? candidates.map(candidateRow).join("")
      : `<div class="ohud-gmct-empty">No linked characters in this scene.</div>`;
    return `<section class="ohud-panel ohud-gmct" data-block="gm-combat-tracker">
      <div class="ohud-panel-head"><span class="ohud-panel-label">Combat</span></div>
      <div class="ohud-gmct-candidates">${list}</div>
      <div class="ohud-gmct-actions">
        <button type="button" class="ohud-gmct-btn is-primary" data-action="gm-start-combat"${busy ? " disabled" : ""}>Start Combat</button>
      </div>
    </section>`;
  }

  const current = session.participants.find((p) => p.isCurrent) ?? null;
  const rows = session.participants
    .slice()
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
    .map(participantRow)
    .join("");

  return `<section class="ohud-panel ohud-gmct" data-block="gm-combat-tracker">
    <div class="ohud-panel-head">
      <span class="ohud-panel-label">ROUND ${esc(session.roundNumber ?? 0)}</span>
      <span class="ohud-gmct-current">Current: ${esc(current?.displayName ?? "—")}</span>
    </div>
    <ul class="ohud-gmct-list">${rows}</ul>
    <div class="ohud-gmct-actions">
      <button type="button" class="ohud-gmct-btn" data-action="gm-skip-turn"${busy ? " disabled" : ""}>Skip Turn</button>
      <button type="button" class="ohud-gmct-btn" data-action="gm-force-next"${busy ? " disabled" : ""}>Force Next</button>
      <button type="button" class="ohud-gmct-btn is-danger" data-action="gm-end-combat"${busy ? " disabled" : ""}>End Combat</button>
    </div>
  </section>`;
}
