// Combat HUD — status chip (Phase 2).
//
// Compact pill for an entity status/effect. Polarity drives the accent; a
// tooltip carries the name + duration + description. Read-only.

import { esc, tipAttr } from "./hudDom.js";

/** Short glyph per polarity (kept tiny — the colour carries most meaning). */
function polarityClass(polarity) {
  if (polarity === "positive") return "positive";
  if (polarity === "negative") return "negative";
  return "neutral";
}

/** @param {import("../models/combatHudContracts.js").EntityStatus} status */
export function statusChip(status) {
  if (!status) return "";
  const dur = status.durationTurns == null ? "Ongoing" : `${status.durationTurns}t`;
  const tip = tipAttr(status.name, [
    status.description || "",
    `Duration: ${dur}`,
  ]);
  const initial = esc((status.name || "?").trim().charAt(0).toUpperCase());
  return `<span class="ohud-chip-status ohud-chip-status--${polarityClass(status.polarity)}"${tip}>
    <span class="ohud-chip-dot" aria-hidden="true">${initial}</span>
    <span class="ohud-chip-name">${esc(status.name)}</span>
  </span>`;
}

/** "+N" overflow chip. */
export function overflowChip(n) {
  if (!n || n <= 0) return "";
  return `<span class="ohud-chip-status ohud-chip-status--more" data-tip-title="More statuses" data-tip-lines="${n} more active">+${n}</span>`;
}
