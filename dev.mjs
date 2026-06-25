import { createServer } from "http";
import { promises as fs } from "fs";
import { join } from "path";
import { build } from "esbuild";
import { watch } from "fs";

const PORT = 3000;
const HOST = "127.0.0.1";

const buildConfigs = [
  { entry: "main.js", out: "assets/main.js" },
  { entry: "gm-extension/main.js", out: "gm-extension/assets/main.js" },
  { entry: "character-sheet-extension/main.js", out: "character-sheet-extension/assets/main.js" },
  { entry: "background.js", out: "assets/background.js" },
  { entry: "hud/overlay/combatHudOverlayPage.js", out: "assets/combat-hud-overlay.js" },
];

const buildSettings = {
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2020",
  sourcemap: false,
  legalComments: "none",
  logLevel: "info",
  loader: { ".css": "text" },
};

async function runBuild() {
  console.log("\n[Build] Starting build...");
  try {
    for (const { entry, out } of buildConfigs) {
      await build({ ...buildSettings, entryPoints: [entry], outfile: out });
    }
    console.log("[Build] ✓ Build complete\n");
  } catch (e) {
    console.error("[Build] ✗ Build failed:", e.message);
  }
}

async function startServer() {
  // Initial build
  await runBuild();

  // File watcher for auto-rebuild
  const watchPaths = ["main.js", "gm-extension", "character-sheet-extension", "background.js", "screens", "bridge", "api", "constants", "runtime", "utils", "shell", "styles.css", "hud"];

  watchPaths.forEach((path) => {
    watch(path, { recursive: true }, async (event, file) => {
      if (file && !file.includes("node_modules") && !file.includes("assets")) {
        console.log(`[Watch] File changed: ${file}`);
        await runBuild();
      }
    });
  });

  const server = createServer(async (req, res) => {
    // Strip the query string (assets are referenced as `?v=1.7.x`) and decode
    // the path; otherwise readFile would look for "background.js?v=1.7.8" → 404.
    // This is what lets the dev manifest's background/popover/overlay scripts
    // actually load locally.
    let pathname = "/";
    try {
      pathname = decodeURIComponent(new URL(req.url, `http://${HOST}:${PORT}`).pathname);
    } catch {
      pathname = "/";
    }
    const filePath = join(process.cwd(), pathname === "/" ? "index.html" : pathname.replace(/^\//, ""));

    try {
      const content = await fs.readFile(filePath);
      const ext = filePath.split(".").pop();
      const contentTypes = {
        html: "text/html",
        js: "application/javascript",
        css: "text/css",
        json: "application/json",
        png: "image/png",
        svg: "image/svg+xml",
      };
      res.writeHead(200, {
        "Content-Type": contentTypes[ext] || "text/plain",
        // Always serve fresh local builds — avoids stale assets after a rebuild.
        "Cache-Control": "no-store",
      });
      res.end(content);
    } catch {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("404 Not Found");
    }
  });

  // Surface a clear hint if the local dev manifest is missing.
  const manifestUrl = `http://${HOST}:${PORT}/manifest.dev.json`;
  let hasDevManifest = true;
  try {
    await fs.access(join(process.cwd(), "manifest.dev.json"));
  } catch {
    hasDevManifest = false;
  }

  server.listen(PORT, HOST, () => {
    console.log(`\n✓ Dev server running at http://${HOST}:${PORT}`);
    if (hasDevManifest) {
      console.log("\n  Owlbear → Add Extension → paste this LOCAL MANIFEST URL:");
      console.log(`    ${manifestUrl}`);
    } else {
      console.log("\n  ⚠ manifest.dev.json not found at project root.");
      console.log("    Create it (see docs/local-dev-owlbear.md), then it will be served at:");
      console.log(`    ${manifestUrl}`);
    }
    console.log(`\n  Standalone HUD preview (no Owlbear): http://${HOST}:${PORT}/combat-hud-overlay.html\n`);
  });
}

startServer().catch(console.error);
