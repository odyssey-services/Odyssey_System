// Combat HUD overlay — shared constants & pure positioning helpers (Phase 1A).
//
// Imported by BOTH the background controller (OBR-coupled) and the popover
// page (DOM-coupled), so this module must stay PURE: no OBR SDK, no DOM, no
// CSS. Only data + math. This is overlay-specific code, NOT a Phase 0
// core/models/adapters module.

/** Deterministic popover id — re-opening with this id updates in place
 *  rather than spawning a duplicate overlay. */
export const OVERLAY_POPOVER_ID = "com.odyssey.combat-hud/overlay";

/** Root HTML page loaded into the popover iframe (resolved against the
 *  background page's origin at runtime). */
export const OVERLAY_HTML = "combat-hud-overlay.html";

/** LOCAL broadcast channel: popover iframe → background controller, carrying
 *  the full minimal UI snapshot whenever it changes. The controller keeps the
 *  latest snapshot in memory so it can (a) resize the popover in place when
 *  `isHudCollapsed` flips (setWidth/setHeight — no reload) and (b) re-seed the
 *  iframe via URL params if OBR reloads it on a re-anchor.
 *  Payload: HudUiState (see DEFAULT_HUD_UI_STATE). */
export const BC_HUD_UI_STATE = "com.odyssey.combat-hud/ui-state";

/* ----------------- sizing ----------------- */

/** Max expanded width; clamps down on narrow viewports (Phase 2 target). */
export const EXPANDED_MAX_WIDTH = 1480;
/** Total horizontal safe margin (12px each side). */
export const EDGE_MARGIN = 24;
/**
 * Expanded HUD height for the WIDE/MEDIUM single-row layout. This stays the
 * canonical `EXPANDED_HEIGHT` so the Phase 1A geometry tests (which sample
 * wide viewports) keep passing; compact two-row layouts use a taller height
 * via computeExpandedHeight().
 */
export const EXPANDED_HEIGHT = 184;
/** Taller height for the COMPACT/MINI two-row layout (< MEDIUM_BREAKPOINT). */
export const COMPACT_EXPANDED_HEIGHT = 324;
/** Collapsed pill size (just the reopen button). */
export const COLLAPSED_WIDTH = 156;
export const COLLAPSED_HEIGHT = 46;
/** Gap between the popover's bottom edge and the viewport bottom. */
export const BOTTOM_INSET = 14;

/* ----------------- responsive layout modes ----------------- */
//
// Breakpoints are evaluated against the HUD/iframe width (which tracks the
// viewport width closely: width ≈ min(EXPANDED_MAX_WIDTH, vw - EDGE_MARGIN)).
// Both the CSS (media queries) and the controller (popover height) use these.

/** ≥ this → full single-row "wide" layout. */
export const WIDE_BREAKPOINT = 1280;
/** ≥ this (and < WIDE) → "medium" single-row layout (blocks compress). */
export const MEDIUM_BREAKPOINT = 960;
/** ≥ this (and < MEDIUM) → "compact" two-row layout. Below → "mini". */
export const MINI_BREAKPOINT = 620;
/** Back-compat alias (Phase 1A). The shell switched layout below this width. */
export const COMPACT_BREAKPOINT = MEDIUM_BREAKPOINT;

/**
 * Resolve the responsive layout mode for a given width.
 * Pure; used by both CSS-mode decisions and the popover height calc.
 * @param {number} width  HUD/iframe width in px
 * @returns {"wide"|"medium"|"compact"|"mini"}
 */
export function resolveLayoutMode(width) {
  const w = Math.max(0, Number(width) || 0);
  if (w >= WIDE_BREAKPOINT) return "wide";
  if (w >= MEDIUM_BREAKPOINT) return "medium";
  if (w >= MINI_BREAKPOINT) return "compact";
  return "mini";
}

/** True when the layout mode stacks the HUD into two rows. */
export function isTwoRowMode(mode) {
  return mode === "compact" || mode === "mini";
}

/**
 * Expanded popover height for a given viewport width. Two-row (compact/mini)
 * layouts need more vertical space than the single-row wide/medium layouts.
 * The width is what drives the layout mode (see resolveLayoutMode), so the
 * mode is resolved from the post-clamp HUD width.
 * @param {number} vw
 * @returns {number}
 */
export function computeExpandedHeight(vw) {
  const hudWidth = computeExpandedWidth(vw);
  return isTwoRowMode(resolveLayoutMode(hudWidth)) ? COMPACT_EXPANDED_HEIGHT : EXPANDED_HEIGHT;
}

/** Origins that pin the popover's bottom-center to the anchor point, so
 *  resizing width/height keeps it bottom-centered without re-anchoring. */
export const ANCHOR_ORIGIN = Object.freeze({ horizontal: "CENTER", vertical: "BOTTOM" });
export const TRANSFORM_ORIGIN = Object.freeze({ horizontal: "CENTER", vertical: "BOTTOM" });

/**
 * Expanded width for a given viewport width: min(MAX, vw - margin), never
 * negative. Mirrors the spec's `min(1180px, calc(100vw - 24px))`.
 * @param {number} vw
 * @returns {number}
 */
export function computeExpandedWidth(vw) {
  const available = Math.max(0, Number(vw) || 0) - EDGE_MARGIN;
  return Math.max(0, Math.min(EXPANDED_MAX_WIDTH, available));
}

/**
 * Popover width/height for the current collapsed state.
 * @param {boolean} collapsed
 * @param {number} vw
 * @returns {{width:number, height:number}}
 */
export function computeOverlaySize(collapsed, vw) {
  if (collapsed) {
    return { width: COLLAPSED_WIDTH, height: COLLAPSED_HEIGHT };
  }
  return { width: computeExpandedWidth(vw), height: computeExpandedHeight(vw) };
}

/**
 * Anchor point that pins the popover bottom-center near the viewport bottom.
 * @param {number} vw
 * @param {number} vh
 * @returns {{left:number, top:number}}
 */
export function computeAnchorPosition(vw, vh) {
  const w = Math.max(0, Number(vw) || 0);
  const h = Math.max(0, Number(vh) || 0);
  return {
    left: Math.round(w / 2),
    top: Math.max(0, Math.round(h - BOTTOM_INSET)),
  };
}

/* ----------------- HUD UI state persistence ----------------- */
//
// Minimal local UI snapshot that must survive a popover re-open (which OBR may
// service by reloading the iframe). This is UI PREFERENCE / DRAFT state only —
// never runtime/combat snapshot, never token metadata.

/**
 * @typedef {Object} HudUiState
 * @property {boolean} isHudCollapsed
 * @property {string} mockScenarioId
 * @property {"player"|"gm"} viewerRole
 * @property {string|null} selectedTokenId
 */

/** Default snapshot. `mockScenarioId` mirrors DEFAULT_SCENARIO_ID in
 *  hud/models/combatHudMockScenarios.js (kept as a literal so this pure
 *  module does not import a Phase 0 model). */
export const DEFAULT_HUD_UI_STATE = Object.freeze({
  isHudCollapsed: false,
  mockScenarioId: "A",
  viewerRole: "player",
  selectedTokenId: null,
});

/** URL param keys used to carry the snapshot to the iframe on (re)open. */
export const HUD_UI_PARAM_KEYS = Object.freeze({
  collapsed: "collapsed",
  scenario: "scenario",
  role: "role",
  token: "token",
});

/**
 * Serialize a HUD UI snapshot to a URL query string (without leading `?`).
 * All four keys are always written so the snapshot round-trips deterministically.
 * @param {Partial<HudUiState>} ui
 * @returns {string}
 */
export function serializeHudUiState(ui) {
  const src = ui && typeof ui === "object" ? ui : {};
  const params = new URLSearchParams();
  params.set(HUD_UI_PARAM_KEYS.collapsed, src.isHudCollapsed ? "1" : "0");
  params.set(HUD_UI_PARAM_KEYS.scenario, src.mockScenarioId != null ? String(src.mockScenarioId) : "");
  params.set(HUD_UI_PARAM_KEYS.role, src.viewerRole === "gm" ? "gm" : "player");
  params.set(HUD_UI_PARAM_KEYS.token, src.selectedTokenId == null ? "" : String(src.selectedTokenId));
  return params.toString();
}

/**
 * Parse a URL query string into a partial HUD UI snapshot. Only well-formed
 * keys are returned; unknown/invalid values are dropped so the caller can
 * safely merge over its defaults. Never throws.
 * @param {string} search  e.g. window.location.search
 * @returns {Partial<HudUiState>}
 */
export function parseHudUiState(search) {
  /** @type {Partial<HudUiState>} */
  const out = {};
  let params;
  try {
    params = new URLSearchParams(search || "");
  } catch {
    return out;
  }
  if (params.has(HUD_UI_PARAM_KEYS.collapsed)) {
    out.isHudCollapsed = params.get(HUD_UI_PARAM_KEYS.collapsed) === "1";
  }
  const scenario = params.get(HUD_UI_PARAM_KEYS.scenario);
  if (scenario) out.mockScenarioId = scenario;
  const role = params.get(HUD_UI_PARAM_KEYS.role);
  if (role === "player" || role === "gm") out.viewerRole = role;
  if (params.has(HUD_UI_PARAM_KEYS.token)) {
    const token = params.get(HUD_UI_PARAM_KEYS.token);
    out.selectedTokenId = token ? token : null;
  }
  return out;
}

/**
 * Merge a partial snapshot over the defaults, producing a complete HudUiState.
 * @param {Partial<HudUiState>} [partial]
 * @returns {HudUiState}
 */
export function normalizeHudUiState(partial) {
  const p = partial && typeof partial === "object" ? partial : {};
  return {
    isHudCollapsed: typeof p.isHudCollapsed === "boolean" ? p.isHudCollapsed : DEFAULT_HUD_UI_STATE.isHudCollapsed,
    mockScenarioId: p.mockScenarioId != null && p.mockScenarioId !== "" ? String(p.mockScenarioId) : DEFAULT_HUD_UI_STATE.mockScenarioId,
    viewerRole: p.viewerRole === "gm" ? "gm" : "player",
    selectedTokenId: Object.prototype.hasOwnProperty.call(p, "selectedTokenId") ? p.selectedTokenId : DEFAULT_HUD_UI_STATE.selectedTokenId,
  };
}

/**
 * Build the full Popover params object (minus id/url, which the controller
 * adds) for OBR.popover.open(). Pure data — no OBR import here.
 * @param {{vw:number, vh:number, collapsed:boolean}} params
 */
export function buildOverlayPopoverParams({ vw, vh, collapsed }) {
  const { width, height } = computeOverlaySize(collapsed, vw);
  return {
    width,
    height,
    anchorReference: "POSITION",
    anchorPosition: computeAnchorPosition(vw, vh),
    anchorOrigin: { ...ANCHOR_ORIGIN },
    transformOrigin: { ...TRANSFORM_ORIGIN },
    hidePaper: true,
    disableClickAway: true,
  };
}
