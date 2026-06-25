// Combat HUD overlay — popover iframe entry (Phase 1A + follow-up).
//
// Build entry loaded by combat-hud-overlay.html INSIDE the OBR popover iframe.
// It injects styles, restores the UI snapshot from the URL (seeded by the
// background controller), mounts the shell wired to the Phase 0 mock store,
// and broadcasts UI-state changes back to the controller so the state survives
// the next popover re-open.
//
// Standalone fallback: if opened directly (not inside Owlbear), it still mounts
// and shows an "OBR unavailable — local HUD preview" banner. It never
// simulates the OBR API.

import OBR from "@owlbear-rodeo/sdk";
import tokenStyles from "../styles/combatHudTokens.css";
import overlayStyles from "./combatHudOverlay.css";
import layoutStyles from "../components/combatHudLayout.css";
import { mountCombatHudOverlay } from "./mountCombatHudOverlay.js";
import { BC_HUD_UI_STATE, parseHudUiState, parseRenderContext } from "./overlayConstants.js";

function injectStyles() {
  for (const [id, css] of [
    ["ohud-tokens", tokenStyles],
    ["ohud-overlay-styles", overlayStyles],
    ["ohud-layout-styles", layoutStyles],
  ]) {
    if (document.getElementById(id)) continue;
    const el = document.createElement("style");
    el.id = id;
    el.textContent = css;
    document.head.appendChild(el);
  }
}

function start() {
  injectStyles();
  document.documentElement.style.background = "transparent";
  document.body.style.background = "transparent";
  document.body.style.margin = "0";

  const root = document.getElementById("root") || document.body;
  const available = !!(OBR && OBR.isAvailable);

  // Restore the UI snapshot the controller seeded into the URL on (re)open.
  let restored = {};
  let renderContext = {};
  try { restored = parseHudUiState(window.location.search); } catch { restored = {}; }
  try { renderContext = parseRenderContext(window.location.search); } catch { renderContext = {}; }

  mountCombatHudOverlay({
    root,
    uiState: restored,
    renderContext,
    devControls: true,
    integration: {
      available,
      onUiStateChange(uiState) {
        // Persist the latest snapshot in the background controller (same
        // client → LOCAL). The controller resizes in place on collapse and
        // re-seeds this snapshot via URL on the next re-anchor. No-op when
        // not embedded in OBR.
        if (!available) return;
        try {
          OBR.broadcast.sendMessage(BC_HUD_UI_STATE, uiState, { destination: "LOCAL" });
        } catch (_e) {
          /* ignore — UI still updated locally via the store */
        }
      },
    },
  });
}

// Mount after OBR is ready when embedded; mount immediately when standalone.
if (OBR && OBR.isAvailable) {
  OBR.onReady(start);
} else {
  start();
}
