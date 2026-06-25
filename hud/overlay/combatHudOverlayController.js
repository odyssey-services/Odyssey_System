// Combat HUD overlay — background controller (Phase 1A + follow-up).
//
// Runs in the BACKGROUND extension context (background.js). Owns the OBR
// popover lifecycle for the persistent bottom-anchored HUD: open once,
// re-anchor on viewport resize, resize on collapse (no iframe reload), and
// close on teardown.
//
// Follow-up: holds the latest minimal HUD UI snapshot (collapse / scenario /
// role / selected token) in memory for the current background session, and
// re-seeds the iframe with it via URL params on every (re)open — so if OBR
// reloads the iframe during a viewport-resize re-anchor, the UI state is
// restored instead of resetting to defaults. This is UI preference/draft
// state only: no runtime/combat snapshot, no token metadata, no Supabase.
//
// This module is OBR-coupled. Per the phase constraint it does NOT import any
// Phase 0 core/models/adapters — those live in the popover iframe (the view).
// It only imports the OBR SDK and the pure overlay constants/helpers.

import OBR from "@owlbear-rodeo/sdk";
import {
  OVERLAY_POPOVER_ID,
  OVERLAY_HTML,
  BC_HUD_UI_STATE,
  DEFAULT_HUD_UI_STATE,
  normalizeHudUiState,
  serializeHudUiState,
  buildOverlayPopoverParams,
} from "./overlayConstants.js";

const VIEWPORT_POLL_MS = 600;

let started = false;
/** Latest UI snapshot for this background session (memory only). */
let lastUiState = { ...DEFAULT_HUD_UI_STATE };
let lastVW = 0;
let lastVH = 0;
let pollTimer = null;
/** @type {Array<() => void>} */
const cleanups = [];

function isCollapsed() {
  return Boolean(lastUiState.isHudCollapsed);
}

/** Resolve the overlay page URL against the background page's origin, seeding
 *  the current UI snapshot as query params. */
function resolveOverlayUrl() {
  const query = serializeHudUiState(lastUiState);
  try {
    const base = typeof window !== "undefined" ? window.location.href : "";
    const url = new URL(OVERLAY_HTML, base);
    url.search = query;
    return url.toString();
  } catch {
    return `${OVERLAY_HTML}?${query}`;
  }
}

async function readViewport() {
  const [vw, vh] = await Promise.all([
    OBR.viewport.getWidth(),
    OBR.viewport.getHeight(),
  ]);
  return { vw, vh };
}

/** (Re)open the popover with the current viewport + UI snapshot. Re-using
 *  OVERLAY_POPOVER_ID updates the existing popover instead of duplicating. */
async function openOrReanchor() {
  const { vw, vh } = await readViewport();
  lastVW = vw;
  lastVH = vh;
  const params = buildOverlayPopoverParams({ vw, vh, collapsed: isCollapsed() });
  const url = resolveOverlayUrl();
  await OBR.popover.open({ id: OVERLAY_POPOVER_ID, url, ...params });
}

/** Resize the popover in place (no reload) to match the collapsed state. */
async function applyCollapsedSize() {
  try {
    const { width, height } = buildOverlayPopoverParams({
      vw: lastVW, vh: lastVH, collapsed: isCollapsed(),
    });
    await OBR.popover.setWidth(OVERLAY_POPOVER_ID, width);
    await OBR.popover.setHeight(OVERLAY_POPOVER_ID, height);
  } catch (error) {
    // If in-place resize fails for any reason, fall back to a full re-anchor.
    try { await openOrReanchor(); } catch (_e) { /* ignore */ }
    void error;
  }
}

function startViewportPoll() {
  if (pollTimer) return;
  pollTimer = setInterval(async () => {
    try {
      const { vw, vh } = await readViewport();
      if (vw === lastVW && vh === lastVH) return;
      await openOrReanchor();
    } catch (_e) {
      /* transient OBR errors are ignored; next tick retries */
    }
  }, VIEWPORT_POLL_MS);
  cleanups.push(() => {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  });
}

/**
 * Start the overlay. Safe to call multiple times (idempotent) and safe when
 * OBR is unavailable (no-op). Waits for OBR ready before opening.
 */
export function setupCombatHudOverlay() {
  if (started) return;
  // Degrade safely outside Owlbear — do not throw, do not open anything.
  if (typeof OBR === "undefined" || OBR.isAvailable === false) {
    return;
  }
  started = true;

  OBR.onReady(async () => {
    try {
      await openOrReanchor();
      startViewportPoll();

      // UI-state coordination from the popover iframe (same client → LOCAL).
      // Update the in-memory snapshot and resize in place when collapse flips.
      const unsubUiState = OBR.broadcast.onMessage(BC_HUD_UI_STATE, async (event) => {
        const next = normalizeHudUiState(event?.data);
        const collapseChanged = next.isHudCollapsed !== lastUiState.isHudCollapsed;
        lastUiState = next;
        if (collapseChanged) {
          await applyCollapsedSize();
        }
      });
      cleanups.push(unsubUiState);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error("[combatHud/overlay] setup failed", error);
      started = false;
    }
  });
}

/** Tear down the overlay: stop the poll, drop listeners, close the popover. */
export async function teardownCombatHudOverlay() {
  for (const fn of cleanups.splice(0)) {
    try { fn(); } catch (_e) { /* ignore */ }
  }
  started = false;
  lastUiState = { ...DEFAULT_HUD_UI_STATE };
  try { await OBR.popover.close(OVERLAY_POPOVER_ID); } catch (_e) { /* ignore */ }
}
