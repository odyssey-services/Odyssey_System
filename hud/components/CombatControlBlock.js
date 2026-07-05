// Combat HUD — Combat Control composite (Phase 2.2.3, read-only).
//
// One module that merges the former three popovers into a single cohesive panel:
//   ┌─────────────┬───────────────┐
//   │  Target     │  Mod (chips)  │   ← right column top
//   │  (165 wide) ├───────────────┤
//   │             │  Action 165×40│   ← right column bottom strip
//   └─────────────┴───────────────┘
// Outer 330×165. The three sections REUSE the existing block renderers verbatim
// (TargetBlock, ModifierBlock chips, ActionBlock button) — CSS makes the inner
// panels seamless so it reads as one panel. No combat mechanics here.

import { renderTargetBlock } from "./TargetBlock.js";
import { renderModifierChips } from "./ModifierBlock.js";
import { renderActionButton } from "./ActionBlock.js";

/** Max modifier chips shown in the dense 2-column grid before a `+N` overflow. */
const COMBAT_CONTROL_MAX_CHIPS = 6;

export function renderCombatControlBlock(state) {
  // Phase 3E.0: GM-only COMBAT button toggles the GM Combat Tracker companion
  // popover. Rendered inside the existing Mod header (no geometry change) and
  // NEVER rendered for a plain player.
  const combatButton = state?.viewer?.role === "gm"
    ? `<button type="button" class="ohud-cc-combat-btn" data-action="toggle-gm-tracker" title="GM Combat Tracker">COMBAT</button>`
    : "";
  return `<section class="ohud-panel ohud-panel--cc" data-block="combatControl">
    <div class="ohud-cc">
      <div class="ohud-cc-target">${renderTargetBlock(state)}</div>
      <div class="ohud-cc-right">
        <section class="ohud-panel ohud-panel--modifiers ohud-cc-mod" data-block="modifiers">
          <div class="ohud-panel-head"><span class="ohud-panel-label">Mod</span>${combatButton}</div>
          ${renderModifierChips(state, COMBAT_CONTROL_MAX_CHIPS)}
        </section>
        <section class="ohud-panel ohud-panel--action ohud-panel--bare ohud-cc-action" data-block="action">
          ${renderActionButton(state)}
        </section>
      </div>
    </div>
  </section>`;
}
