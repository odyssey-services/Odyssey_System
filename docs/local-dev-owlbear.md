# Local Owlbear development (no GitHub Pages)

Test a local build inside your own Owlbear room without pushing or deploying.
Production keeps using `manifest.json` (GitHub Pages); this flow uses a
separate **`manifest.dev.json`** that points at `http://127.0.0.1:3000`.

## 1. Start the dev server

```bash
node dev.mjs
```

This builds every entry (including the Combat HUD overlay
`hud/overlay/combatHudOverlayPage.js` → `assets/combat-hud-overlay.js`),
watches source folders (`hud`, `screens`, `bridge`, `api`, …) and rebuilds on
change, and serves the project root over HTTP with `Cache-Control: no-store`
(so a rebuild is always picked up). The console prints the exact URL to use.

## 2. Local manifest URL

Add this as a **Local Extension** in Owlbear (it is the manifest URL, not the
popup page):

```
http://127.0.0.1:3000/manifest.dev.json
```

`manifest.dev.json` is git-ignored and must never be deployed. It mirrors the
production manifest but points `background_url`, the action `popover` and the
`icon` at localhost. The Combat HUD overlay needs **no** manifest entry — the
background page resolves `combat-hud-overlay.html` from its own origin
(`127.0.0.1:3000`) at runtime, so it loads locally automatically.

## 3. Add the Local Extension in Owlbear

1. Open Owlbear Rodeo and enter (or create) a room/scene.
2. Open the **Extensions** menu → **Add Extension**.
3. Choose **Add Local Extension** (or paste a URL) and enter:
   `http://127.0.0.1:3000/manifest.dev.json`
4. Enable it. The action button opens the existing popup; the persistent
   Combat HUD overlay appears over the bottom of the map.

Keep `node dev.mjs` running the whole time — Owlbear loads everything from the
local server live.

## 4. What you can check in the browser WITHOUT Owlbear

- `http://127.0.0.1:3000/combat-hud-overlay.html` — the HUD shell renders
  standalone with an **"OBR unavailable — local HUD preview"** banner; the
  dev scenario/role controls, collapse → pill and reopen all work against the
  Phase 0 mock store.
- `http://127.0.0.1:3000/index.html` — the existing tabbed popup app.
- `http://127.0.0.1:3000/manifest.dev.json` — should return HTTP 200.

These verify rendering, mock state, collapse/reopen and layout.

## 5. What can only be checked INSIDE an Owlbear room

- The overlay actually mounting over the map via `OBR.popover.open()`.
- Bottom-center anchoring and re-anchor on browser-window resize.
- Map remaining interactive outside the HUD rect (pan/select).
- Collapse resizing the popover in place (pill) with the map clickable around it.
- No duplicate overlay after reload/reconnect.
- UI-state (collapse / scenario / role / selected token) surviving a re-open.

## 6. Why localhost only works for you

`http://127.0.0.1:3000` resolves to the machine running `node dev.mjs`. Other
players in the room cannot reach your localhost, so a dev manifest is only
usable by the developer who started the server. For shared testing, deploy a
build that the production `manifest.json` references (GitHub Pages). Do not add
tunnels/ngrok/Cloudflare for this — it is intentionally local-only.
