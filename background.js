import { getPlayerInfo, getRoomSceneContext, waitForObrReady } from "./bridge/obrBridge.js";
import { hasSupabaseSettings, loadRoomSupabaseSettings } from "./bridge/settingsBridge.js";
import { addDiagnosticEntry } from "./utils/diagnostics.js";
import { setupCombatHudOverlay } from "./hud/overlay/combatHudOverlayController.js";

async function bootstrapBackgroundShell() {
  await waitForObrReady();
  const [player, roomContext, settings] = await Promise.all([
    getPlayerInfo(),
    getRoomSceneContext(),
    loadRoomSupabaseSettings(),
  ]);

  globalThis.OdysseyBackgroundBridge = {
    player,
    roomContext,
    settings,
    supabaseConfigured: hasSupabaseSettings(settings),
  };

  addDiagnosticEntry(
    "info",
    "Background shell ready",
    `role=${player.role || "PLAYER"} room=${roomContext.roomId || "unknown"}`,
  );
}

void bootstrapBackgroundShell().catch((error) => {
  addDiagnosticEntry(
    "error",
    "Background shell failed",
    String(error?.message ?? error),
  );
  throw error;
});

// Phase 1A/2: mount the persistent on-map Combat HUD overlay. Independent of
// the bridge bootstrap above and safe to run regardless of its outcome — the
// controller waits for OBR ready internally and no-ops when OBR is unavailable.
// It uses the Phase 0 mock store; no backend dependency.
try {
  setupCombatHudOverlay();
} catch (error) {
  addDiagnosticEntry(
    "error",
    "Combat HUD overlay setup failed",
    String(error?.message ?? error),
  );
}
