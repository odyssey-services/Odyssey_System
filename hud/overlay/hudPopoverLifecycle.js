// Combat HUD - pure popover lifecycle helpers.
//
// Single source of truth for which HUD popovers should be open for a given
// mode and selection status. Kept pure so the open/close policy is testable
// without OBR, DOM, or Supabase.

import { HUD_MODULE_IDS } from "./hudLayout.js";

export function moduleShouldBeOpen(mode, status, id) {
  void status;
  void id;
  if (mode !== "modules") return false;
  return true;
}

export function primaryModuleOpenMap(mode, status) {
  const map = {};
  for (const id of HUD_MODULE_IDS) {
    map[id] = moduleShouldBeOpen(mode, status, id);
  }
  return map;
}

export function secondaryReconcileAction(prevStatus, nextStatus) {
  void prevStatus;
  void nextStatus;
  return "none";
}

export function characterChangeClosesCompanions(prevCharId, nextCharId) {
  return (prevCharId ?? null) !== (nextCharId ?? null);
}

/* ===================== Companion popover sizing (pure) =====================
 *
 * The gun-magazine-selector (and weapon-selector) companion popovers must be
 * sized to their CONTENT — a fixed oversized rect leaves a large empty area
 * and forces the row markup into a tiny absolutely-positioned corner (the
 * exact bug this module fixes). These constants mirror the row layout in
 * combatHudModule.css (.ohud-reserve-list / .ohud-reserve-mag): keep both in
 * sync if the row height/gap ever changes. */

/** Companion popover width (fits the 180–230px content spec). */
export const COMPANION_SELECTOR_WIDTH = 210;
/** One magazine/weapon row, including its border. */
const ROW_HEIGHT = 22;
/** Gap between rows (.ohud-reserve-list / .ohud-weapon-list `gap`). */
const ROW_GAP = 4;
/** Panel chrome: top+bottom padding (6px each) + header row (~11px) + the
 *  panel's own head→body gap (4px). */
const PANEL_CHROME_HEIGHT = 27;
/** Never collapse below one row's worth of content (loading/empty message). */
const MIN_HEIGHT = 56;
/** Cap growth and let the list scroll internally beyond this many rows. */
const MAX_HEIGHT = 220;

/**
 * Height for a companion selector popover with `rowCount` visible rows (a
 * magazine or weapon entry each). `rowCount` is clamped to >= 1 so the
 * loading/empty single-line message still gets a sane, non-empty popover.
 * Pure — no OBR, no DOM.
 */
export function computeCompanionSelectorHeight(rowCount) {
  const rows = Math.max(1, Number(rowCount) || 0);
  const rowsHeight = rows * ROW_HEIGHT + (rows - 1) * ROW_GAP;
  const total = PANEL_CHROME_HEIGHT + rowsHeight;
  return Math.min(MAX_HEIGHT, Math.max(MIN_HEIGHT, total));
}
