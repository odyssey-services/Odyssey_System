# Combat HUD — Phase 2.1: Reference correction + personal placement

Phase 2.1 is a visual/geometric correction of the Phase 2 HUD to match the
approved references (`UI/Main interface.png`, `UI/Gun_block.png`,
`UI/Skill_block.png`, `UI/Modifier_block.png`, `UI/target_block.png`) and a fix
of the broken in-Owlbear state (`UI/current-hud-actual.png`: centered, oversized
Action button, native scrollbar, empty popover height). It also adds a personal,
draggable HUD position. No store / selectors / mock-data / OBR lifecycle /
Supabase / API / action logic / dev workflow changes.

## Before → after

| Problem (before) | After |
|---|---|
| HUD centered + small | Anchored **bottom-left** (left margin 10px), content-fit width |
| Player not separated | PlayerBlock 144×146, its own tall panel, gap to the rail |
| Battle Log a permanent block | Removed; only a small **LOG** toggle (top-right of strip), expands a floating panel |
| Action button huge / misplaced | Compact button at the bottom of the Mod+Action column, **22px** tall |
| Skills dim/small | Group captions (Attack/Shield/Psy/…) + one dense row of 44–54px tiles |
| Native white scrollbar | `overflow:hidden` on html/body/#root/overlay — gone |
| Huge empty popover height | Popover height tight to the HUD (**166px** desktop) |

Screenshots could not be captured this session (the preview screenshot tool
timed out repeatedly while the page itself stayed responsive); the geometry was
verified instead by live DOM measurement (see "Verification").

## Desktop geometry (measured at viewport 1440, gap 172)

```
[ Player 144×146 ]      gap 172      [ Gun 240×95 ][ Skills flex×95 ][ Target 100×95 ][ Mod+Action 126×95 ]
   x=6                                  x=322          x=572 (w 616)     x=1198           x=1308
   bottom edges of Player and every rail block aligned · Action button 22px · grip 22×14 at top-left
```

- Layout = flex row: `PlayerBlock` (fixed 144) · gap `var(--ohud-gap)` · `.ohud-rail`
  (flex row, `align-items:flex-end`). Rail children are fixed except **Skills**
  (`flex:1`, the widest). The gap is `clamp(110, 12vw, 235)` computed by the
  controller from the true viewport and seeded to the iframe as `--ohud-gap`.
- All sizes are fixed/near-fixed (no even `1fr` grid), per the reference.

## Popover sizing & scrollbar fix

- `overlayConstants.js`: bottom-left anchoring (`anchorOrigin`/`transformOrigin`
  `{LEFT, BOTTOM}`, `marginThreshold: 0`); width = `min(content, viewport-20)`
  for single row, fills width for two rows; height **166** (single row) /
  **300** (two-row compact/mini). `computeAnchorPosition` derives the popover's
  bottom-left corner from the normalized placement.
- The controller (`combatHudOverlayController.js`) opens the popover at that
  size/anchor and re-anchors on viewport resize; the normalized placement keeps
  the HUD on-screen after resizes.
- Scrollbar: `html, body, #root, .ohud-overlay, .ohud-hud` all `overflow:hidden`.
  The only permitted scroll is inside the expanded Battle Log list. No `100vh`,
  no oversized bottom-aligned child in a tall iframe.

## Personal placement (drag to move)

OBR's `PopoverApi` (verified in `node_modules/@owlbear-rodeo/sdk/lib/api/
PopoverApi.d.ts`) exposes only `open/close/getWidth/setWidth/getHeight/
setHeight` — **no `setPosition`**. Repositioning therefore needs a re-open
(which may reload the iframe), so this is the **branch-5** design:

- A 22×14 **grip handle** (six-dot icon) sits at the top-left of the control
  strip (`cursor: grab`, tooltip "Перетащить HUD · двойной клик — сбросить").
  Only the grip starts a drag — blocks, buttons, tiles and the map never do.
- During drag: a **local CSS-transform preview** (bounded by the overlay rect);
  the real OBR position is **never** re-opened per `pointermove`.
- On `pointerup`: the new normalized placement is committed once — written to
  `localStorage` and broadcast to the controller, which re-opens the popover at
  the new anchor.
- Double-click the grip → reset to the default bottom-left.

### Placement model & storage

```js
hudPlacement: { mode: "default"|"custom", x: 0..1, y: 0..1 }
// x/y are fractions of the available travel space, not pixels:
//   availW = vw - hudW - 2*safeMargin;  left = safeMargin + x*availW
//   availH = vh - hudH - 2*safeMargin;  top  = safeMargin + y*availH
// default = bottom-left (x=0, y=1)
```

Pure math + validation live in `hud/overlay/hudPlacement.js`
(`placementToPixels`, `pixelsToPlacement`, `clampPlacement`, `validatePlacement`,
`readStoredPlacement`/`writeStoredPlacement`). Placement is:

- part of the UI-state (so it survives collapse/reopen within a session),
- additionally persisted to `localStorage["odyssey.hud.placement.v1"]`
  (durable, per-browser, strictly validated),
- restored **before first render** (localStorage takes precedence over the
  URL-seeded value on a cold start),
- **local only** — never synced to other players, Supabase, or token metadata.

On resize, normalized fractions are re-projected and clamped, so the HUD never
ends up off-screen.

## Responsive

| Mode | Viewport | Layout |
|------|----------|--------|
| wide | ≥1280 | bottom-left single row (geometry above) |
| medium | 960–1279 | single row; gap + Skills compress |
| compact | 620–959 | two rows (Player on top, rail wraps); height 300 |
| mini | <620 | two rows densified; grip + collapse still work |

## Constraints honored

No duplicate popover (single deterministic id) · map clickable outside the HUD
rect (the iframe is sized to the HUD) · collapse/reopen intact · UI-state never
lost · no native scrollbar · no `100vh` empty area. Mock scenarios, Phase 0
contracts, store, selector APIs, Supabase, RPC, token metadata, OBR selection
logic, gameplay, action semantics, the production manifest, the dev workflow and
the existing popup are all unchanged.

## Verification

```bash
npm run test:hud   # Phase 0 (10) + 1A/2.1 geometry+UI-state (14) + Phase 2 (13) + Phase 2.1 placement (8) = 45
npm run build      # bundles incl. assets/combat-hud-overlay.js
```

Live preview (`combat-hud-overlay.html`, sized to the popover with seeded
`?vw&vh&gap`) confirmed by DOM measurement at viewport 1440/2048 and 880/560:

- Exact block footprints (Player 144×146, Gun 240×95, Skills flex×95, Target
  100×95, Mod+Action 126×95), bottoms aligned, Action button 22px, grip 22×14.
- **No** horizontal/vertical overflow at any width (`scrollHeight == innerHeight`).
- No permanent Battle Log block; LOG toggle opens a floating panel (5 rows)
  within the overlay bounds.
- Drag commits a `custom` placement to localStorage; double-click resets to
  default; a custom localStorage placement is restored before first render
  (a fresh drag starts from the restored position, not the default).
- Collapse → pill → reopen; tooltips render (attached to `<body>` so they
  survive layout re-renders).

## Manual Owlbear checklist (Local Extension `manifest.dev.json`)

Drag to centre / to the bottom-right / past the edge (auto-clamp) · double-click
reset · collapse keeps the pill at the personal position · reopen returns there ·
window resize keeps the HUD on-screen · room reload restores the position ·
another player does NOT receive your position · the map stays clickable around
the HUD.

## Known limitations

- Live drag preview is bounded by the overlay iframe rect (it can't paint
  outside it); the final position is applied on release via one controller
  re-open. This is the documented branch-5 behavior given OBR has no
  `setPosition`.
- Cross-session cold start may show one position correction (controller opens at
  its default, then the iframe's localStorage placement is applied once).
