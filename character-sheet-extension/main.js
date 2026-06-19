import { mountBridgeShell } from "../shell/appShell.js";
import { createOdysseyRuntime } from "../runtime/createRuntime.js";

const runtime = createOdysseyRuntime();
globalThis.OdysseyCharacterSheetBridge = runtime;

const root = document.getElementById("app");

if (!(root instanceof HTMLElement)) {
  throw new Error("Unable to mount Odyssey Character Sheet Shell.");
}

void mountBridgeShell({
  root,
  title: "Odyssey Character Sheet Shell",
  subtitle:
    "Legacy character sheet editing flow has been removed. This surface now exposes only the shared bridge foundation for future UI slices.",
  runtime,
  globalName: "OdysseyCharacterSheetBridge",
}).catch((error) => {
  root.innerHTML = `
    <section class="panel">
      <div class="panel-title">Odyssey Character Sheet Shell</div>
      <p class="status error">Failed to initialize shell: ${String(error?.message ?? error)}</p>
    </section>
  `;
  throw error;
});
