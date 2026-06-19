import { mountBridgeShell } from "./shell/appShell.js";
import { createOdysseyRuntime } from "./runtime/createRuntime.js";
import { mountResolveAttackScreen } from "./screens/resolveAttack/resolveAttackScreen.js";
import { mountCharacterScreen } from "./screens/character/characterScreen.js";
import { mountPlacementScreen } from "./screens/placement/placementScreen.js";

const runtime = createOdysseyRuntime();
globalThis.OdysseyBridge = runtime;

const root = document.getElementById("app");

if (!(root instanceof HTMLElement)) {
  throw new Error("Unable to mount Odyssey Bridge Shell.");
}

// Composition root: a thin tab switcher between the existing Bridge Shell and the
// Stage 5A Resolve Attack slice. The shell stays clean; each view is isolated and
// lazily mounted on first open. Resolve Attack does not block on Owlbear, so it
// works in standalone/dev mode as well as inside Owlbear.
root.innerHTML = `
  <nav class="app-nav">
    <button class="app-tab active" type="button" data-view="resolve">Combat · Resolve Attack</button>
    <button class="app-tab" type="button" data-view="character">Character</button>
    <button class="app-tab" type="button" data-view="placement">Placement</button>
    <button class="app-tab" type="button" data-view="shell">Bridge Shell</button>
  </nav>
  <div class="app-view" data-view-host="resolve"></div>
  <div class="app-view hidden" data-view-host="character"></div>
  <div class="app-view hidden" data-view-host="placement"></div>
  <div class="app-view hidden" data-view-host="shell"></div>
`;

const hosts = {
  resolve: root.querySelector('[data-view-host="resolve"]'),
  character: root.querySelector('[data-view-host="character"]'),
  placement: root.querySelector('[data-view-host="placement"]'),
  shell: root.querySelector('[data-view-host="shell"]'),
};

const views = {
  resolve: {
    mounted: false,
    mount() {
      mountResolveAttackScreen({ root: hosts.resolve, runtime });
    },
  },
  character: {
    mounted: false,
    mount() {
      mountCharacterScreen({ root: hosts.character, runtime });
    },
  },
  placement: {
    mounted: false,
    mount() {
      mountPlacementScreen({ root: hosts.placement, runtime });
    },
  },
  shell: {
    mounted: false,
    mount() {
      void mountBridgeShell({
        root: hosts.shell,
        title: "Odyssey Bridge Shell",
        subtitle:
          "Supabase backend, Owlbear bridge, and RPC wrappers are preserved. Gameplay UI is delivered as vertical slices.",
        runtime,
        globalName: "OdysseyBridge",
      }).catch((error) => {
        hosts.shell.innerHTML = `
          <section class="panel">
            <div class="panel-title">Odyssey Bridge Shell</div>
            <p class="status error">Failed to initialize shell: ${String(error?.message ?? error)}</p>
          </section>
        `;
      });
    },
  },
};

function show(view) {
  for (const key of Object.keys(hosts)) {
    hosts[key].classList.toggle("hidden", key !== view);
    root.querySelector(`[data-view="${key}"]`)?.classList.toggle("active", key === view);
  }
  const target = views[view];
  if (target && !target.mounted) {
    target.mounted = true;
    target.mount();
  }
  // Notify the newly shown panel so it can refresh stale data
  hosts[view]?.dispatchEvent(new CustomEvent("odyssey:tabshow", { bubbles: false }));
}

root.querySelectorAll("[data-view]").forEach((btn) => {
  btn.addEventListener("click", () => show(btn.dataset.view));
});

show("resolve");
