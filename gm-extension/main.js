import { mountBridgeShell } from "../shell/appShell.js";
import { createOdysseyRuntime } from "../runtime/createRuntime.js";
import { createTokenRealtimeSync } from "../bridge/tokenRealtimeSync.js";

const runtime = createOdysseyRuntime();
const tokenRealtimeSync = createTokenRealtimeSync({ runtime });
globalThis.OdysseyGmToolsBridge = runtime;
globalThis.OdysseyGmTokenSync = tokenRealtimeSync;

const root = document.getElementById("app");

if (!(root instanceof HTMLElement)) {
  throw new Error("Unable to mount Odyssey GM Tools Shell.");
}

void tokenRealtimeSync.start().catch(() => {});

void mountBridgeShell({
  root,
  title: "Odyssey GM Tools Shell",
  subtitle:
    "GM token placement, Supabase room settings, and token metadata reconciliation live here. Combat state remains server-authoritative.",
  runtime,
  globalName: "OdysseyGmToolsBridge",
  features: {},
  tokenRealtimeSync,
}).catch((error) => {
  root.innerHTML = `
    <section class="panel">
      <div class="panel-title">Odyssey GM Tools Shell</div>
      <p class="status error">Failed to initialize shell: ${String(error?.message ?? error)}</p>
    </section>
  `;
  throw error;
});

globalThis.addEventListener("beforeunload", () => {
  tokenRealtimeSync.stop();
});
