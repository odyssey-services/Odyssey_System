// Combat HUD overlay — background controller (Phase 1A · 2 · 2.1).
//
// Runs in the BACKGROUND extension context (background.js). Owns the OBR
// popover lifecycle for the persistent bottom-left-anchored HUD: open once,
// re-anchor on viewport resize, resize in place on collapse, reposition on
// personal-placement change, and close on teardown.
//
// Placement: the HUD position is a per-user preference held in lastUiState
// (normalized fractions). OBR's Popover API has NO setPosition — only
// open/close/setWidth/setHeight (see PopoverApi.d.ts) — so a position change
// requires a re-open (which may reload the iframe). The iframe therefore shows
// a local drag-preview during the gesture and commits the real OBR position
// ONCE on pointerup via a BC_HUD_UI_STATE broadcast (never per pointermove).
//
// This module is OBR-coupled and imports NO Phase 0 core/models/adapters.

import OBR from "@owlbear-rodeo/sdk";
import {
  OVERLAY_POPOVER_ID,
  OVERLAY_HTML,
  BC_HUD_UI_STATE,
  HUD_RENDER_PARAM_KEYS,
  DEFAULT_HUD_UI_STATE,
  normalizeHudUiState,
  serializeHudUiState,
  buildOverlayPopoverParams,
  computeHudGap,
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

function samePlacement(a, b) {
  if (!a || !b) return a === b;
  if (a.mode !== b.mode) return false;
  return Math.abs((a.x ?? 0) - (b.x ?? 0)) < 0.001 && Math.abs((a.y ?? 0) - (b.y ?? 0)) < 0.001;
}

/** Resolve the overlay page URL: persisted UI snapshot + render context (the
 *  true viewport size + computed gap the iframe needs for drag math). */
function resolveOverlayUrl(vw, vh) {
  const params = new URLSearchParams(serializeHudUiState(lastUiState));
  params.set(HUD_RENDER_PARAM_KEYS.vw, String(Math.round(vw)));
  params.set(HUD_RENDER_PARAM_KEYS.vh, String(Math.round(vh)));
  params.set(HUD_RENDER_PARAM_KEYS.gap, String(computeHudGap(vw)));
  const query = params.toString();
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

/** (Re)open the popover with the current viewport + UI snapshot + placement. */
async function openOrReanchor() {
  const { vw, vh } = await readViewport();
  lastVW = vw;
  lastVH = vh;
  const params = buildOverlayPopoverParams({
    vw, vh, collapsed: isCollapsed(), placement: lastUiState.hudPlacement,
  });
  const url = resolveOverlayUrl(vw, vh);
  await OBR.popover.open({ id: OVERLAY_POPOVER_ID, url, ...params });
}

/** Resize the popover in place (no reload) to match the collapsed state. The
 *  bottom-left corner is pinned, so the pill stays at the personal position. */
async function applyCollapsedSize() {
  try {
    const { width, height } = buildOverlayPopoverParams({
      vw: lastVW, vh: lastVH, collapsed: isCollapsed(), placement: lastUiState.hudPlacement,
    });
    await OBR.popover.setWidth(OVERLAY_POPOVER_ID, width);
    await OBR.popover.setHeight(OVERLAY_POPOVER_ID, height);
  } catch (error) {
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
      await openOrReanchor(); // normalized placement clamps to the new viewport
    } catch (_e) {
      /* transient OBR errors are ignored; next tick retries */
    }
  }, VIEWPORT_POLL_MS);
  cleanups.push(() => {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  });
}

/**
 * Start the overlay. Idempotent and safe when OBR is unavailable (no-op).
 */
export function setupCombatHudOverlay() {
  if (started) return;
  if (typeof OBR === "undefined" || OBR.isAvailable === false) return;
  started = true;

  OBR.onReady(async () => {
    try {
      await openOrReanchor();
      startViewportPoll();

      // UI-state coordination from the popover iframe (same client → LOCAL).
      const unsubUiState = OBR.broadcast.onMessage(BC_HUD_UI_STATE, async (event) => {
        const next = normalizeHudUiState(event?.data);
        const collapseChanged = next.isHudCollapsed !== lastUiState.isHudCollapsed;
        const placementChanged = !samePlacement(next.hudPlacement, lastUiState.hudPlacement);
        lastUiState = next;
        if (placementChanged) {
          // Position changed (drag commit / reset) → re-open at the new anchor.
          await openOrReanchor();
        } else if (collapseChanged) {
          // Only collapse flipped → resize in place (no reload, state preserved).
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
