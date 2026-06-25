# Combat HUD — Phase 1A: Persistent Owlbear Scene Overlay

Phase 1A mounts a persistent Combat HUD surface over the bottom of the Owlbear
map. It covers mounting, lifecycle, positioning, pointer behaviour, collapse/
reopen and wiring to the Phase 0 mock store. It does **not** implement the
Player/Gun/Skill/Target blocks, combat actions, targeting or Supabase.

## Chosen OBR overlay mechanism

`OBR.popover.open(popover)` from the **background** extension context.

Evidence from the installed SDK (`@owlbear-rodeo/sdk@3.1.0`):

- `lib/api/PopoverApi.d.ts` — `open(popover)`, `close(id)`, `setWidth(id,w)`,
  `setHeight(id,h)`.
- `lib/types/Popover.d.ts` — `id`, `url`, `width`, `height`, `anchorPosition`,
  `anchorOrigin`/`transformOrigin` (vertical accepts `"BOTTOM"`),
  `anchorReference: "ELEMENT" | "POSITION"`, `hidePaper`, `disableClickAway`.
- `lib/api/ViewportApi.d.ts` — exposes `getWidth()/getHeight()` but **no resize
  event**, so the controller polls to re-anchor.
- `lib/api/ActionApi.d.ts` — the action button popup (the existing tabbed
  `index.html`); not a persistent scene surface, so it is left untouched.

### Why this mechanism

- A popover is a real overlay above the map: it does not resize, push or
  replace the map and the map remains visible behind it.
- With `anchorReference: "POSITION"` we anchor to viewport coordinates rather
  than a map element, so the HUD never behaves like a token.
- `anchorOrigin`/`transformOrigin = { CENTER, BOTTOM }` plus
  `anchorPosition = { left: vw/2, top: vh − inset }` pin the popover's
  **bottom-center** near the viewport bottom. Because the bottom-center is
  pinned, calling `setWidth/setHeight` keeps it bottom-centered with no
  re-anchor.
- `hidePaper: true` removes the default surface so only our panel is visible;
  `disableClickAway: true` keeps it open when the user clicks the map.
- The popover iframe rect equals the HUD footprint, so the map stays
  interactive everywhere outside that rect — no full-screen click blocker.

## Module map

```
hud/overlay/
  overlayConstants.js            Pure constants + positioning math (no DOM/OBR/CSS).
  combatHudOverlayController.js   Background: popover open/re-anchor/resize/close (OBR).
  combatHudOverlayView.js         DOM renderer for the shell/pill (no OBR).
  mountCombatHudOverlay.js        Wires Phase 0 mock store ↔ view; returns { unmount }.
  combatHudOverlayPage.js         Popover iframe entry (injects CSS, detects OBR, mounts).
  combatHudOverlay.css            Overlay shell styles (uses Phase 0 semantic tokens).
combat-hud-overlay.html           Root page loaded into the popover iframe.
```

Context separation:

- **Background** (`combatHudOverlayController.js`, reached from `background.js`)
  imports the OBR SDK + pure `overlayConstants`. It imports **no** Phase 0
  core/models/adapters.
- **Popover iframe** (`combatHudOverlayPage.js` → `mountCombatHudOverlay` →
  `combatHudOverlayView`) is the DOM/CSS side. It consumes the Phase 0 pure
  store + mock adapter (same pattern as the Phase 0 dev panel). The Phase 0
  modules themselves remain free of DOM/OBR/CSS.

## Overlay lifecycle (mount & dispose)

1. `background.js` calls `setupCombatHudOverlay()` (guarded; independent of the
   bridge bootstrap).
2. The controller no-ops if `OBR.isAvailable === false`; otherwise it waits for
   `OBR.onReady`.
3. On ready it reads viewport size and calls `OBR.popover.open({ id, url, … })`
   with a deterministic id (`com.odyssey.combat-hud/overlay`). The url is
   resolved from `window.location` (`combat-hud-overlay.html`) — no manifest
   entry needed.
4. The popover iframe loads `combatHudOverlayPage.js`, which injects styles,
   detects OBR, and mounts the shell wired to a fresh mock store.
5. A 600 ms viewport poll re-anchors on size change by re-opening the **same
   id** with a recomputed anchor.
6. `teardownCombatHudOverlay()` stops the poll, drops listeners and closes the
   popover.

## Collapse / reopen behaviour

- The collapse button lives in the popover iframe. Clicking it calls
  `store.setHudCollapsed(true)` (Phase 0 UI action) and the view swaps the full
  shell for a small "◆ ODYSSEY" pill near the bottom edge.
- The page broadcasts the full UI snapshot on `BC_HUD_UI_STATE` (LOCAL) to the
  background, which resizes the popover in place via `setWidth/setHeight`
  (pill ↔ shell) when the collapse flag flips. Because the bottom-center is
  pinned, it stays centered with **no iframe reload**, so the mock store (and
  selected scenario) is preserved.
- Reopening reverses the same path. The store is never disposed by collapsing.
- Collapse state is not stored in token metadata. It survives a re-open via the
  UI-state restore mechanism below.

## UI-state persistence across re-open (follow-up)

A viewport-resize re-anchor re-opens the popover, which OBR may service by
reloading the iframe. To stop that from resetting the HUD, a minimal UI
snapshot is preserved and restored — **UI preference/draft state only**
(`isHudCollapsed`, `mockScenarioId`, `viewerRole`, `selectedTokenId`); never a
runtime/combat snapshot, never token metadata, never Supabase.

Flow:

1. **iframe → controller:** on any change (collapse, scenario, role, token) the
   page broadcasts the snapshot on `BC_HUD_UI_STATE` (LOCAL).
2. **controller memory:** the background controller keeps the last valid
   snapshot for the current background session (`lastUiState`).
3. **controller → iframe:** every `OBR.popover.open()` (initial open and each
   re-anchor) seeds the snapshot into the iframe URL as query params via
   `serializeHudUiState`.
4. **restore before first render:** the page parses the URL
   (`parseHudUiState`), and `mountCombatHudOverlay` applies role + selected
   token to the mock adapter and the collapse flag to the store **before** the
   view's first render, so the first painted frame is already correct.

Serialization helpers (`serializeHudUiState` / `parseHudUiState` /
`normalizeHudUiState`) live in the pure `overlayConstants.js` and are unit
tested without DOM or OBR.

## Duplicate prevention

- A single deterministic popover id means re-opening (on re-anchor, reload or
  reconnect) updates the existing popover rather than spawning a second one.
- The controller also guards with a module-level `started` flag so
  `setupCombatHudOverlay()` is idempotent within a background session.

## Standalone fallback (outside Owlbear)

- No module throws at import time when OBR is absent.
- The controller's `setupCombatHudOverlay()` becomes a no-op, so the existing
  tabbed popup app is unaffected.
- `combat-hud-overlay.html` can be opened directly for a local preview: the
  page detects `OBR.isAvailable === false`, mounts the shell anyway, and shows
  an **"OBR unavailable — local HUD preview"** banner. The OBR API is never
  simulated.
- Manual standalone mount into any DOM root:
  ```js
  import { mountCombatHudOverlay } from "./hud/overlay/mountCombatHudOverlay.js";
  mountCombatHudOverlay({ root: document.body, integration: { available: false } });
  ```

## Dev scenario controls

The shell includes a compact, dev-only row (hidden on narrow widths): a
scenario `<select>` (A–G) and Player/GM toggle. These drive
`store.setMockScenario` / `store.setViewerRole`, letting you exercise:
controlled player on their turn (A), waiting player (B), unauthorised selection
(F), GM inspection (G) and the mech scenario (E). This is not a player-facing
production feature.

## Manifest changes

**None.** The popover URL is resolved at runtime from the background page
origin, so no manifest entry is required. The existing `action.popover`,
`background_url` and icon configuration are unchanged, and the existing
Resolve Attack / Character / Bridge Shell popup continues to open as before.

## Validation

```bash
npm run test:hud   # Phase 0 (10 checks) + Phase 1A positioning (8 checks)
npm run build      # bundles incl. assets/combat-hud-overlay.js
```

## Known limitations

- Placeholder shell only — no Player/Gun/Skill/Target blocks yet (Phase 2).
- Mock store only; no Supabase, no live selection, no combat actions.
- Viewport-resize re-anchor re-opens the popover with the same id. If OBR
  reloads the iframe on re-open, the UI snapshot (collapse / scenario / role /
  selected token) is restored from URL params seeded by the controller, so it
  no longer resets to defaults. The snapshot is held in **background-session
  memory only** — a full extension reload (fresh background) starts from
  defaults; durable cross-session persistence is out of scope for 1A.
- No automated DOM/integration test for the iframe — covered by the manual
  Owlbear checklist below. Pure positioning + UI-state serialize/parse logic
  is unit-tested.

## Manual Owlbear test procedure

1. `npm run build`, deploy/serve, load the extension in a room/scene.
2. Confirm the Combat HUD appears centered over the bottom of the map.
3. Open the existing Odyssey action popup — it still works (tabs intact).
4. Click uncovered map space — map interaction still works (pan/select).
5. Collapse the HUD — only the small "◆ ODYSSEY" pill remains at the bottom.
6. Reopen it — the previously selected mock scenario/role is preserved.
7. Resize the browser window — the HUD stays bottom-centered and usable, and
   the selected scenario / role / collapse state are preserved (even if OBR
   reloads the iframe on re-anchor).
8. Reload/reopen the extension — exactly one HUD overlay, no duplicates.
9. Open `combat-hud-overlay.html` outside OBR — shell renders with the
   "OBR unavailable — local HUD preview" banner; the main popup app is fine.

## Next task — Phase 2

Build the visual Combat HUD layout shell: the Player, Gun, Skill, Target,
Modifier, Action and Battle Log blocks (read-only, against the Phase 0 mock
store), with the responsive layout and empty/loading/disabled/overflow states.
