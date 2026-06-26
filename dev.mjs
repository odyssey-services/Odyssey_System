import { createServer } from "http";
import { promises as fs } from "fs";
import { join } from "path";
import { build } from "esbuild";
import { watch } from "fs";

const PORT = 3000;

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
    console.log("[Build] Build complete\n");
  } catch (e) {
    console.error("[Build] Build failed:", e.message);
  }
}

async function startServer() {
  await runBuild();

  const watchPaths = [
    "main.js",
    "gm-extension",
    "character-sheet-extension",
    "background.js",
    "screens",
    "bridge",
    "api",
    "constants",
    "runtime",
    "utils",
    "shell",
    "styles.css",
    "hud",
  ];

  watchPaths.forEach((path) => {
    watch(path, { recursive: true }, async (_event, file) => {
      if (file && !file.includes("node_modules") && !file.includes("assets")) {
        console.log(`[Watch] File changed: ${file}`);
        await runBuild();
      }
    });
  });

  const server = createServer(async (req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    res.setHeader("Cache-Control", "no-store");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    let pathname = "/";
    try {
      pathname = decodeURIComponent(new URL(req.url, `http://localhost:${PORT}`).pathname);
    } catch {
      pathname = "/";
    }

    const filePath = join(
      process.cwd(),
      pathname === "/" ? "index.html" : pathname.replace(/^\//, ""),
    );

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
        "Cache-Control": "no-store",
      });
      res.end(content);
    } catch {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("404 Not Found");
    }
  });

  const manifestUrl = `http://localhost:${PORT}/manifest.dev.json`;
  let hasDevManifest = true;
  try {
    await fs.access(join(process.cwd(), "manifest.dev.json"));
  } catch {
    hasDevManifest = false;
  }

  server.listen(PORT, () => {
    console.log(`\nDev server running at http://localhost:${PORT}`);
    if (hasDevManifest) {
      console.log("\n  Owlbear -> Add Extension -> paste this LOCAL MANIFEST URL:");
      console.log(`    ${manifestUrl}`);
    } else {
      console.log("\n  manifest.dev.json not found at project root.");
      console.log("    Create it, then it will be served at:");
      console.log(`    ${manifestUrl}`);
    }
    console.log(`\n  Standalone HUD preview: http://localhost:${PORT}/combat-hud-overlay.html\n`);
  });
}

startServer().catch(console.error);
