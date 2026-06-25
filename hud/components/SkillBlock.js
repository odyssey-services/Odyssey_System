// Combat HUD — Skill block (Phase 2, read-only).
//
// The central, widest module. Renders the quick-slot bar from the mock action
// library: square tiles, accent-coloured by semantic type, with cooldown /
// resource-cost / toggle / disabled / empty states and rich hover tooltips.
// Clicking a tile does NOT execute anything in Phase 2.

import {
  selectQuickSlots,
  selectSkillById,
  selectSelectedSkill,
} from "../core/combatHudSelectors.js";
import { accentClass } from "./hudLayoutModel.js";
import { skillIconSvg } from "./hudIcons.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr, cls } from "./hudDom.js";

const COST_ABBR = { FREE: "F", MOVE: "Mv", MAIN: "M", TURN: "T" };

function emptyTile(index) {
  return `<div class="ohud-slot ohud-slot--empty" data-slot="${index}" aria-hidden="true"></div>`;
}

function skillTile(skill, index, selectedId) {
  const accent = accentClass(skill.color);
  const disabled = Boolean(skill.disabledReason);
  const selected = skill.id === selectedId;
  const cost = COST_ABBR[skill.actionCost] ?? "";
  const cd = Number(skill.cooldownTurns) || 0;
  const res = skill.resourceCost ? `${skill.resourceCost.amount}${String(skill.resourceCost.type).charAt(0).toUpperCase()}` : "";

  const tip = tipAttr(skill.name, [
    `Source: ${skill.source}`,
    `Cost: ${skill.actionCost}${res ? ` · ${res}` : ""}`,
    cd > 0 ? `Cooldown: ${cd} turn(s)` : "",
    skill.isToggled ? "Active (toggled on)" : "",
    skill.disabledReason ? `Disabled: ${skill.disabledReason}` : (skill.tooltip || ""),
  ]);

  return `<div class="${cls(
      "ohud-slot",
      `ohud-accent--${accent}`,
      disabled ? "is-disabled" : "",
      selected ? "is-selected" : "",
      skill.isToggled ? "is-toggled" : "",
    )}" data-slot="${index}" data-skill="${esc(skill.id)}"${tip}>
    <span class="ohud-slot-icon">${skillIconSvg(skill.icon)}</span>
    ${cost ? `<span class="ohud-slot-cost">${esc(cost)}</span>` : ""}
    ${res ? `<span class="ohud-slot-res">${esc(res)}</span>` : ""}
    ${cd > 0 ? `<span class="ohud-slot-cd">${cd}</span>` : ""}
    ${skill.isToggled ? `<span class="ohud-slot-toggle" aria-hidden="true"></span>` : ""}
  </div>`;
}

export function renderSkillBlock(state) {
  const slots = selectQuickSlots(state);
  const selected = selectSelectedSkill(state);
  const selectedId = selected?.id ?? null;

  const tiles = (slots.length ? slots : Array.from({ length: 6 }, (_, i) => ({ index: i, skillId: null })))
    .map((slot) => {
      const skill = selectSkillById(state, slot.skillId);
      return skill ? skillTile(skill, slot.index, selectedId) : emptyTile(slot.index);
    })
    .join("");

  return panel({
    key: "skills",
    label: "SKILLS",
    bodyHtml: `<div class="ohud-slots">${tiles}</div>`,
  });
}
