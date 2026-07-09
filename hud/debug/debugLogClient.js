// Odyssey Debug Console — cross-bundle error reporting client (TEMPORARY).
//
// hud/debug/debugLogStore.js is a plain in-memory singleton that only works
// for callers running in the SAME JS realm as background.js (sceneSelection
// Controller.js, quickbarController.js, targetSelectionController.js,
// combatHudOverlayController.js). screens/character/characterScreen.js (the
// Character overlay) and any other bundle built as its own esbuild entry
// point (main.js, gm-extension/main.js, character-sheet-extension/main.js)
// run in a DIFFERENT iframe/JS realm and cannot import debugLogStore.js
// directly — importing it there would just create a second, empty, never-
// displayed store.
//
// This module is the one thing every bundle CAN safely import: a single
// `reportUiError()` call that broadcasts to background.js over
// BC_DEBUG_CONSOLE_LOG_EVENT (LOCAL destination — same client only, exactly
// like every other Combat HUD broadcast channel; this never leaves the
// player's own browser, let alone the room). debugConsoleController.js is the
// only listener and folds it into the SAME debugLogStore every other event
// already goes through — one Debug Console, one place every overlay's
// errors land, regardless of which bundle they came from.
//
// Same isolation rules as the rest of hud/debug/: no Supabase import, no
// localStorage, no OBR scene/room metadata — see scripts/debug-console.test.mjs.

import OBR from "@owlbear-rodeo/sdk";
import { BC_DEBUG_CONSOLE_LOG_EVENT } from "./debugConsoleConstants.js";

/**
 * @param {{
 *   source: string,      e.g. "character_overlay" | "weapon_overlay" | "skills_overlay" | "quickbar" | "combat_actions"
 *   operation: string,   e.g. "switch_active_weapon"
 *   code?: (string|null),
 *   message?: string,
 *   details?: object,
 *   payload?: object,
 *   result?: object,
 * }} event
 */
export function reportUiError(event) {
  try {
    if (typeof OBR === "undefined" || OBR.isAvailable === false) return;
    const source = String(event?.source ?? "unknown");
    const operation = String(event?.operation ?? "unknown");
    OBR.broadcast.sendMessage(
      BC_DEBUG_CONSOLE_LOG_EVENT,
      {
        source,
        operation,
        code: event?.code ?? null,
        message: String(event?.message ?? ""),
        details: event?.details && typeof event.details === "object" ? event.details : {},
        payload: event?.payload && typeof event.payload === "object" ? event.payload : null,
        result: event?.result && typeof event.result === "object" ? event.result : null,
        createdAt: Date.now(),
      },
      { destination: "LOCAL" },
    );
  } catch (_e) { /* diagnostics must never throw */ }
}
