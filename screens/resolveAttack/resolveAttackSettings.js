// Stage 5A connection settings for the Resolve Attack screen.
//
// Priority:
//   1. Local dev override (localStorage) — primary for standalone Stage 5A testing.
//   2. Room-level Supabase settings (OBR room metadata) — when running inside Owlbear.
//
// No real project URL/key is committed anywhere; values are entered at runtime.

import {
  normalizeSupabaseSettings,
  loadRoomSupabaseSettings,
} from "../../bridge/settingsBridge.js";

const DEV_STORAGE_KEY = "odyssey.resolveAttack.devSettings";

function readLocalStorage() {
  try {
    return JSON.parse(localStorage.getItem(DEV_STORAGE_KEY) || "{}") || {};
  } catch {
    return {};
  }
}

export function loadDevSettings() {
  return normalizeSupabaseSettings(readLocalStorage());
}

export function saveDevSettings(raw) {
  const normalized = normalizeSupabaseSettings(raw);
  try {
    localStorage.setItem(DEV_STORAGE_KEY, JSON.stringify(normalized));
  } catch {
    /* ignore quota/availability errors */
  }
  return normalized;
}

export function clearDevSettings() {
  try {
    localStorage.removeItem(DEV_STORAGE_KEY);
  } catch {
    /* ignore */
  }
  return normalizeSupabaseSettings({});
}

export function hasUsableSettings(settings) {
  const s = normalizeSupabaseSettings(settings);
  return Boolean(s.url && s.apiKey);
}

// Race a promise against a timeout so OBR-dependent calls never hang the screen
// when running outside Owlbear (where OBR.onReady never fires).
function withTimeout(promise, ms, fallback) {
  return Promise.race([
    promise.catch(() => fallback),
    new Promise((resolve) => setTimeout(() => resolve(fallback), ms)),
  ]);
}

// Returns the effective settings to use for RPC calls.
// Dev override wins; otherwise best-effort room settings (guarded by timeout).
export async function resolveEffectiveSettings() {
  const dev = loadDevSettings();
  if (hasUsableSettings(dev)) return { settings: dev, source: "local" };

  const room = await withTimeout(loadRoomSupabaseSettings(), 1500, null);
  if (room && hasUsableSettings(room)) return { settings: room, source: "room" };

  return { settings: dev, source: hasUsableSettings(dev) ? "local" : "none" };
}
