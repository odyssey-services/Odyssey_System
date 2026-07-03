// Combat HUD — body-part condition evaluator (PURE: no OBR, no DOM, no Supabase).
//
// Single source of truth for "how bad is this body part", shared by:
//   - the SOURCE's own silhouette (hud/runtime/runtimeBundleMapper.js mapZones)
//   - the TARGET's silhouette (hud/targeting/targetBodyZones.js), whose combat
//     data comes from a narrower, best-effort fetch that can legitimately fail
//     (RLS denial, network) — that must render as "unknown", never "healthy".
//
// Real body-part model (verified against supabase/odyssey_supabase.sql and
// mirrored by the existing Character sheet UI / resolveAttackScreen.js): there
// is NO current/max HP on a body part. Severity is three independent WOUND
// COUNTS (minor/serious/critical), a hard disabled/destroyed flag, and a
// SEPARATE armor track (armor_value/armor_critical/armor_max_critical/
// armor_destroyed) — never conflated with body condition here. This mirrors
// runtimeBundleMapper.js's zoneStateFromBodyPart() exactly (that function now
// delegates to this module instead of duplicating the same severity order).

export const BODY_CONDITION_STATE = Object.freeze({
  healthy: "healthy",
  minor: "minor",
  serious: "serious",
  critical: "critical",
  disabled: "disabled",
  // Combat data for this body part is missing, not yet fetched, or the fetch
  // was denied (target refresh blocked by RLS/access) — NEVER "healthy".
  unknown: "unknown",
});

/** bodyConditionPolicy state → the CSS-facing ZONE_STATES value used by
 *  hudLayoutModel.zoneStateClass()/hudIcons.humanoidSvg(). "minor" reuses the
 *  existing "wounded" CSS token — no new stylesheet rule needed for it. */
const TO_ZONE_STATE = Object.freeze({
  healthy: "healthy",
  minor: "wounded",
  serious: "serious",
  critical: "critical",
  disabled: "disabled",
  unknown: "unknown",
});

const COLOR_TOKEN = Object.freeze({
  healthy: "--odyssey-hud-zone-healthy",
  minor: "--odyssey-hud-zone-wounded",
  serious: "--odyssey-hud-zone-serious",
  critical: "--odyssey-hud-zone-critical",
  disabled: "--odyssey-hud-zone-disabled",
  unknown: "--odyssey-hud-zone-unknown",
});

const LABEL = Object.freeze({
  healthy: "Healthy",
  minor: "Minor damage",
  serious: "Serious damage",
  critical: "Critical damage",
  disabled: "Disabled",
  unknown: "Unknown",
});

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * @param {{minor?, serious?, critical?, disabled?, destroyed?}|null} bp  A raw
 *   body-part row (or null/undefined when data is missing/denied).
 * @returns {{ state:string, zoneState:string, colorToken:string, label:string }}
 */
export function evaluateBodyCondition(bp) {
  if (!bp || typeof bp !== "object") {
    return build(BODY_CONDITION_STATE.unknown);
  }
  if (bp.destroyed || bp.disabled) return build(BODY_CONDITION_STATE.disabled);
  if (num(bp.critical) > 0) return build(BODY_CONDITION_STATE.critical);
  if (num(bp.serious) > 0) return build(BODY_CONDITION_STATE.serious);
  if (num(bp.minor) > 0) return build(BODY_CONDITION_STATE.minor);
  return build(BODY_CONDITION_STATE.healthy);
}

function build(state) {
  return { state, zoneState: TO_ZONE_STATE[state], colorToken: COLOR_TOKEN[state], label: LABEL[state] };
}

/** The wound-count detail lines for a hover tooltip — ONLY real fields, never
 *  a fabricated current/max fraction (the model has no such field). Empty
 *  array when data is unknown or the part is perfectly healthy (nothing to
 *  report beyond the label itself). */
export function bodyConditionDetailLines(bp) {
  if (!bp || typeof bp !== "object") return [];
  const lines = [];
  if (bp.destroyed) lines.push("Destroyed");
  else if (bp.disabled) lines.push("Disabled");
  if (num(bp.critical) > 0) lines.push(`Critical damage: ${num(bp.critical)}`);
  if (num(bp.serious) > 0) lines.push(`Serious wounds: ${num(bp.serious)}`);
  if (num(bp.minor) > 0) lines.push(`Minor wounds: ${num(bp.minor)}`);
  if (Number.isFinite(Number(bp.armor_value)) && Number(bp.armor_value) > 0) {
    lines.push(`Armor: ${num(bp.armor_value)}`);
  }
  return lines;
}
