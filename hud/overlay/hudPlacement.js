// Combat HUD — personal placement math (Phase 2.1).
//
// Pure helpers for the user-draggable HUD position. NO DOM, NO OBR, NO CSS —
// only data + math, so it is unit-testable under plain Node and shared by both
// the background controller (computes the real popover anchor) and the popover
// page (drag math + localStorage restore).
//
// The placement is stored NORMALIZED (fractions of the available travel space)
// so it survives viewport resizes and always clamps back on-screen. It is a
// local UI preference only: never synced to other players, never written to
// Supabase or token metadata.

/** Safe inset (px) kept between the HUD and every viewport edge. */
export const SAFE_MARGIN = 10;

/** localStorage key for the durable per-browser placement preference. */
export const PLACEMENT_STORAGE_KEY = "odyssey.hud.placement.v1";

/**
 * @typedef {Object} HudPlacement
 * @property {"default"|"custom"} mode
 * @property {number} x  0..1 fraction of available horizontal travel
 * @property {number} y  0..1 fraction of available vertical travel
 */

/** Default placement: bottom-left corner (x=0, y=1). */
export const DEFAULT_PLACEMENT = Object.freeze({ mode: "default", x: 0, y: 1 });

function clamp01(n) {
  const v = Number(n);
  if (!Number.isFinite(v)) return 0;
  if (v < 0) return 0;
  if (v > 1) return 1;
  return v;
}

/**
 * Coerce arbitrary input into a valid HudPlacement. Unknown / malformed input
 * collapses to the default. Never throws.
 * @param {*} raw
 * @returns {HudPlacement}
 */
export function clampPlacement(raw) {
  if (!raw || typeof raw !== "object") return { ...DEFAULT_PLACEMENT };
  const mode = raw.mode === "custom" ? "custom" : "default";
  if (mode === "default") return { ...DEFAULT_PLACEMENT };
  return { mode: "custom", x: clamp01(raw.x), y: clamp01(raw.y) };
}

/** Available travel space (px) for the HUD's top-left within the viewport. */
export function availableTravel({ vw, vh, hudW, hudH, safeMargin = SAFE_MARGIN }) {
  return {
    width: Math.max(0, (Number(vw) || 0) - (Number(hudW) || 0) - 2 * safeMargin),
    height: Math.max(0, (Number(vh) || 0) - (Number(hudH) || 0) - 2 * safeMargin),
  };
}

/**
 * Normalized placement → pixel top-left of the HUD rect, clamped on-screen.
 * @returns {{left:number, top:number}}
 */
export function placementToPixels(placement, dims) {
  const p = clampPlacement(placement);
  const safeMargin = dims.safeMargin ?? SAFE_MARGIN;
  const { width: availW, height: availH } = availableTravel({ ...dims, safeMargin });
  return {
    left: Math.round(safeMargin + p.x * availW),
    top: Math.round(safeMargin + p.y * availH),
  };
}

/**
 * Pixel top-left of the HUD rect → normalized custom placement, clamped.
 * @returns {HudPlacement}
 */
export function pixelsToPlacement(left, top, dims) {
  const safeMargin = dims.safeMargin ?? SAFE_MARGIN;
  const { width: availW, height: availH } = availableTravel({ ...dims, safeMargin });
  const x = availW > 0 ? clamp01((left - safeMargin) / availW) : 0;
  const y = availH > 0 ? clamp01((top - safeMargin) / availH) : 0;
  return { mode: "custom", x, y };
}

/**
 * Validate a parsed object as a HudPlacement, or return null. Use after
 * JSON.parse of an untrusted localStorage payload.
 * @param {*} raw
 * @returns {HudPlacement|null}
 */
export function validatePlacement(raw) {
  if (!raw || typeof raw !== "object") return null;
  if (raw.mode !== "default" && raw.mode !== "custom") return null;
  if (raw.mode === "custom") {
    if (typeof raw.x !== "number" || typeof raw.y !== "number") return null;
    if (!Number.isFinite(raw.x) || !Number.isFinite(raw.y)) return null;
  }
  return clampPlacement(raw);
}

/** Parse a JSON string (or object) into a HudPlacement, or null. Never throws. */
export function parsePlacement(rawJson) {
  if (rawJson == null) return null;
  let obj = rawJson;
  if (typeof rawJson === "string") {
    try { obj = JSON.parse(rawJson); } catch { return null; }
  }
  return validatePlacement(obj);
}

/** Serialize a placement to a compact JSON string. */
export function serializePlacement(placement) {
  return JSON.stringify(clampPlacement(placement));
}

/**
 * Read + validate the placement from a Storage-like object (localStorage).
 * Returns the default placement when missing/invalid. Storage is injected so
 * this stays testable without a real browser.
 * @param {{getItem:(k:string)=>(string|null)}} storage
 * @returns {HudPlacement}
 */
export function readStoredPlacement(storage) {
  try {
    const raw = storage && storage.getItem ? storage.getItem(PLACEMENT_STORAGE_KEY) : null;
    return parsePlacement(raw) ?? { ...DEFAULT_PLACEMENT };
  } catch {
    return { ...DEFAULT_PLACEMENT };
  }
}

/** Write the placement to a Storage-like object. Swallows quota/security errors. */
export function writeStoredPlacement(storage, placement) {
  try {
    if (storage && storage.setItem) {
      storage.setItem(PLACEMENT_STORAGE_KEY, serializePlacement(placement));
    }
  } catch { /* ignore */ }
}
