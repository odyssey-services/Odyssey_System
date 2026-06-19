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
  const watchPaths = ["main.js", "gm-extension", "character-sheet-extension", "background.js", "screens", "bridge", "api", "constants", "runtime", "utils", "shell", "styles.css"];

  watchPaths.forEach((path) => {
    watch(path, { recursive: true }, async (event, file) => {
      if (file && !file.includes("node_modules") && !file.includes("assets")) {
        console.log(`[Watch] File changed: ${file}`);
        await runBuild();
      }
    });
  });

  const server = createServer(async (req, res) => {
    let filePath = req.url === "/" ? "index.html" : req.url.replace(/^\//, "");
    filePath = join(process.cwd(), filePath);

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
      res.writeHead(200, { "Content-Type": contentTypes[ext] || "text/plain" });
      res.end(content);
    } catch {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("404 Not Found");
    }
  });

  server.listen(PORT, HOST, () => {
    console.log(`\n✓ Dev server running at http://${HOST}:${PORT}`);
    console.log(`✓ Load http://${HOST}:${PORT}/index.html in OBR as Local Extension\n`);
  });
}

startServer().catch(console.error);
