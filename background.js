import { getPlayerInfo, getRoomSceneContext, waitForObrReady } from "./bridge/obrBridge.js";
import { hasSupabaseSettings, loadRoomSupabaseSettings } from "./bridge/settingsBridge.js";
import { setupCombatHudOverlay } from "./hud/overlay/combatHudOverlayController.js";
import { addDiagnosticEntry } from "./utils/diagnostics.js";

async function bootstrapBackgroundShell() {
  setupCombatHudOverlay();
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
