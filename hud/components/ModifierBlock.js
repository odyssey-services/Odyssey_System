// Combat HUD — Modifier block (Phase 2, read-only).
//
// Compact chip grid of attack modifiers: positive/negative/passive/narrative
// and the special "God Bless" intervention. Colour conveys polarity; selected
// chips get an accent outline. No real toggling in Phase 2.

import { selectModifierChips } from "../core/combatHudSelectors.js";
import { panel } from "./HudPanel.js";
import { esc, tipAttr, cls } from "./hudDom.js";

const MAX_CHIPS = 6;

function chipAccent(mod) {
  if (mod.source === "intervention") return "intervention";
  if (mod.kind === "narrative" || mod.requiresGMApproval) return "narrative";
  if (mod.polarity === "negative") return "negative";
  if (mod.polarity === "positive") return "positive";
  return "neutral";
}

function modChip(mod) {
  const accent = chipAccent(mod);
  const sign = mod.value > 0 ? `+${mod.value}` : (mod.value < 0 ? `${mod.value}` : "");
  const tip = tipAttr(mod.name, [
    mod.description || "",
    sign ? `Value: ${sign}` : "",
    `Source: ${mod.source}`,
    mod.alwaysActive ? "Always active (passive)" : "",
    mod.requiresGMApproval ? "Requires GM approval" : "",
  ]);
  return `<span class="${cls(
      "ohud-mod",
      `ohud-mod--${accent}`,
      mod.selected ? "is-selected" : "",
      mod.alwaysActive ? "is-passive" : "",
    )}"${tip}>
    <span class="ohud-mod-name">${esc(mod.name)}</span>
    ${sign ? `<span class="ohud-mod-val">${esc(sign)}</span>` : ""}
  </span>`;
}

export function renderModifierBlock(state) {
  const chips = selectModifierChips(state).slice(0, MAX_CHIPS);
  const filled = chips.map(modChip).join("");
  // Pad to an even grid so the block keeps its shape (reference look).
  const padCount = Math.max(0, Math.min(2, MAX_CHIPS - chips.length));
  const pads = Array.from({ length: padCount }, () => `<span class="ohud-mod ohud-mod--empty" aria-hidden="true"></span>`).join("");

  return panel({
    key: "mod",
    label: "MOD",
    bodyHtml: `<div class="ohud-mods">${filled}${pads}</div>`,
  });
}
