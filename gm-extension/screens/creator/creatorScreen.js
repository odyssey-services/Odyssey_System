import { getPlayerInfo, subscribePlayerChanges, waitForObrReady } from "../../../bridge/obrBridge.js";
import { loadRoomSupabaseSettings } from "../../../bridge/settingsBridge.js";
import { mountCreatorMenu } from "../../../shell/creatorMenu.js";

function createMarkup() {
  return `
    <section class="panel">
      <div class="panel-title">Creator Catalog</div>
      <p class="panel-note">GM-only catalog editor for skills and equipment models. Save updates goes straight into Supabase definitions.</p>
    </section>
    <div data-creator-screen-host></div>
  `;
}

export async function mountCreatorScreen({ root, runtime }) {
  if (!(root instanceof HTMLElement)) {
    throw new Error("Creator screen root is missing.");
  }

  await waitForObrReady();
  root.innerHTML = createMarkup();

  const creatorHost = root.querySelector("[data-creator-screen-host]");
  if (!(creatorHost instanceof HTMLElement)) {
    throw new Error("Creator screen host is missing.");
  }

  const state = {
    player: await getPlayerInfo(),
    settings: await loadRoomSupabaseSettings(),
  };

  const controller = mountCreatorMenu({
    root: creatorHost,
    runtime,
    getPlayer: () => state.player,
    getSettings: () => state.settings,
  });

  const unsubscribePlayer = await subscribePlayerChanges(async (player) => {
    state.player = player;
    state.settings = await loadRoomSupabaseSettings().catch(() => state.settings);
    controller.syncAccess();
  });

  root.addEventListener("odyssey:tabshow", () => {
    void loadRoomSupabaseSettings()
      .then((settings) => {
        state.settings = settings;
        controller.refresh();
      })
      .catch(() => {
        controller.refresh();
      });
  });

  return () => {
    if (typeof unsubscribePlayer === "function") {
      unsubscribePlayer();
    }
  };
}
