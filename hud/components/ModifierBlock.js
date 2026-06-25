// Combat HUD — Modifier + Action column (Phase 2 · 2.1, read-only).
//
// One narrow right-hand module: a small "Mod" label, a few thin modifier chips
// (positive/negative/passive/narrative + the "God Bless" intervention), and the
// compact Action button pinned to the bottom. No real toggling in Phase 2.

import { selectModifierChips } from "../core/combatHudSelectors.js";
import { renderActionButton } from "./ActionBlock.js";
import { esc, tipAttr, cls } from "./hudDom.js";

const MAX_CHIPS = 4;

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
  return `<span class="${cls("ohud-mod", `ohud-mod--${accent}`, mod.selected ? "is-selected" : "", mod.alwaysActive ? "is-passive" : "")}"${tip}>
    <span class="ohud-mod-name">${esc(mod.name)}</span>${sign ? `<span class="ohud-mod-val">${esc(sign)}</span>` : ""}
  </span>`;
}

export function renderModifierActionColumn(state) {
  const chips = selectModifierChips(state).slice(0, MAX_CHIPS);
  const chipsHtml = chips.map(modChip).join("");
  return `<section class="ohud-panel ohud-panel--modact" data-block="modact">
    <div class="ohud-panel-head"><span class="ohud-panel-label">Mod</span></div>
    <div class="ohud-mods">${chipsHtml}</div>
    ${renderActionButton(state)}
  </section>`;
}

// Back-compat export (older callers); now an alias of the combined column.
export const renderModifierBlock = renderModifierActionColumn;
