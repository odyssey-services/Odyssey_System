# Combat HUD — Phase 2.2: Modular layout + per-module Arrange editor

Phase 2.2 changes how the HUD is positioned. The single draggable rail of Phase
2.1 is replaced by **seven independent HUD modules**, each its own OBR popover,
freely placed by the player, with a dedicated fullscreen **Arrange HUD** editor.
No store / selectors / mock-data / Supabase / RPC / RLS / token-metadata /
gameplay / Resolve-Attack-popup / Phase 0 contract changes. No frameworks/CDN.

## Multi-popover architecture

Each module is a separate popover with a stable id, loading the same page with a
`?module=` param so it renders only its own block, tight to its rect:

```
odyssey-hud-player  odyssey-hud-gun     odyssey-hud-skills  odyssey-hud-target
odyssey-hud-modifiers  odyssey-hud-action  odyssey-hud-log
odyssey-hud-editor (fullscreen Arrange)   odyssey-hud-pill (collapsed)
```

**OBR API used** (verified in `@owlbear-rodeo/sdk@3.1.0`,
`lib/api/PopoverApi.js`): every call is keyed by `id`
(`OBR_POPOVER_OPEN/CLOSE/GET/SET`), so distinct ids create distinct simultaneous
popovers and re-opening an id updates it in place. Modules use
`anchorReference:"POSITION"`, `anchorOrigin/transformOrigin {LEFT,TOP}`,
`anchorPosition {left, top}`, `hidePaper:true`, `disableClickAway:true`,
`marginThreshold:0`. Viewport size via `viewport.getWidth()/getHeight()` (no
resize event → 600 ms poll). Coordination via `broadcast` (LOCAL):
`BC_HUD_UI_STATE` (collapse), `BC_HUD_EDITOR` (open/close), `BC_HUD_LAYOUT`
(layout state). The single background controller
(`combatHudOverlayController.js`) owns all popover lifecycle.

Because each iframe is exactly its module rect, the map stays clickable in the
gaps between modules. Combat/mock state is NOT duplicated per backend call: each
module iframe builds the same deterministic Phase 0 mock snapshot from the
scenario/role/token seeded in its URL — no Supabase request from any block.

**Stacking / repositioning constraints.** The Popover type has **no z-index** and
there is **no `setPosition`** (only `open/close/set{Width,Height}`). So:
- cross-popover stacking is controlled by **open order** — modules open ascending
  by z-index, so higher-z (Player 30, Action 40) open last and render on top of
  the modules they intentionally overlap (Gun 20, Modifiers 20);
- repositioning is a **re-open**, done only on resize, layout Save, collapse/
  reopen and editor open/close — **never per pointermove**.

Inside the editor's single fullscreen iframe, stacking is plain CSS z-index, so
overlaps render exactly.

## Reference viewport + exact default layout

`HUD_LAYOUT_REFERENCE_VIEWPORT = { width: 1920, height: 1080 }`. At 1920×1080 the
default rects are exact (verified by DOM measurement — all seven match):

| Module | left | top | width | height | z |
|--------|-----:|----:|------:|-------:|--:|
| player | 16 | 814 | 250 | 250 | 30 |
| gun | 126 | 899 | 340 | 165 | 20 |
| skills | 663 | 899 | 600 | 165 | 20 |
| target | 1263 | 899 | 165 | 165 | 20 |
| modifiers | 1428 | 899 | 125 | 165 | 20 |
| action | 1428 | 1024 | 165 | 40 | 40 |
| log | 1656 | 814 | 250 | 250 | 20 |

(`top = 1080 − bottom(16) − height`.) Defined in `DEFAULT_HUD_LAYOUT_V2`
(`hud/overlay/hudLayout.js`).

**Intentional, preserved overlaps / gaps** (not auto-fixed):
- Player overlaps Gun's left; Player (z30) renders above Gun (z20).
- Action overlaps the bottom of Modifiers and is wider, jutting right;
  Action (z40) above Modifiers (z20).
- The wide Gun↔Skills gap is deliberate (no grid/flex collapses it).
- Log is a full 250×250 module (not collapsed to a LOG button by default).

## Responsive

`scale = min(vw/1920, vh/1080, 1)` (capped at 1 — never upscaled).
- **≥1600 / 1100–1599:** the exact default geometry scaled by one factor; custom
  positions are normalized fractions, re-projected + clamped each viewport.
- **<1100 (compact):** a separate stacked fallback (`compactModuleRect`) keeps
  each module at a readable min size, packed in wrapped rows from the bottom, so
  every module stays reachable and editable. Custom positions still apply.

## localStorage schema (v2)

```js
const STORAGE_KEY = "odyssey.hud.layout.v2";
{ version: 2, modules: { player:{mode,x,y}, gun:{…}, … log:{…} } }
```
`mode` is `"default"` (exact reference rect) or `"custom"`; `x/y ∈ [0,1]` are
fractions of available travel, not pixels. All values validated + clamped;
invalid payloads → default; the legacy `odyssey.hud.placement.v1` key is ignored
by v2. Browser-local only — never synced to players, Supabase, or metadata.
Restored before first render; survives reload, collapse/reopen and resize. Pure
math + storage live in `hud/overlay/hudLayout.js`.

## Arrange HUD editor

Opened from a small grid button in the Player module (normal mode shows no
grips). The editor is a fullscreen popover (may block the map — the player is
editing the UI). It renders all seven modules as live preview cards at their
draft rects; each card has a six-dot grip. Dragging a grip moves only that card
(CSS, no popover re-open), with **8px snap**, **edge/centre alignment guides**,
and viewport clamping; the card stays visible and gains a high z-index. Buttons:
- **Save layout** → writes v2 localStorage, broadcasts the new layout; the
  controller closes the editor and re-opens every module popover at the new
  positions (no duplicates).
- **Cancel** → closes the editor, active layout unchanged.
- **Reset layout** → draft reverts to the exact `DEFAULT_HUD_LAYOUT_V2`.

## Global collapse

The Player module's collapse button hides all seven modules and shows one
Odyssey pill near the saved Player position; reopening restores every module at
its personal position. Collapse never resets the layout.

## Tests & build

```bash
npm run test:hud   # 10 + 14 + 13 + 8 + 12 = 57 pure tests
npm run build      # bundles incl. assets/combat-hud-overlay.js
```
Phase 2.2 adds `scripts/combat-hud-phase22.test.mjs` (12 tests): exact default
rects, scaling, normalized↔pixels, per-module clamp, intentional overlaps,
reset, invalid v2 payload, save/cancel draft, collapse/reopen persistence,
skills ≤10/row wrapping + snap.

## Verified in standalone preview (DOM-measured)

- Editor: all seven cards at the exact spec rects at 1920×1080; dragging Gun
  moved only Gun (snapped) and Save wrote `{mode:"custom"}` to v2 localStorage;
  a custom v2 payload is restored on load (Log top-left, Gun raised).
- Single module pages render and fill their iframe; Player hosts Arrange +
  collapse; pill renders. No native scrollbar; Skills centred; Target silhouette
  enlarged.

## Manual Owlbear checklist (Local Extension)

1. ~1920×1080: default layout matches the exact coordinates above.
2. All seven modules visible at once.
3. Map clickable in the gaps between modules.
4. Open Arrange HUD.
5. Drag only Gun — others don't move; Gun stays visible while dragging.
6. Move Skills and Log independently.
7. Player/Gun and Modifiers/Action overlaps render correctly (higher-z on top).
8. Cancel discards; Save applies to all module popovers.
9. Reload room → custom layout restored.
10. Collapse → pill (near Player) → reopen → layout preserved.
11. Resize window → modules stay reachable.
12. Reset layout → exact default.
13. No white scrollbars; no duplicate popovers.

## Known limitations

- Cross-popover stacking relies on open order (no z-index API); if the OBR host
  ever reorders popovers, the editor (CSS z-index) remains exact while normal
  mode is best-effort.
- Real multi-popover behaviour (7 simultaneous popovers, map click-through
  between them, reposition on Save, collapse/reopen, no duplicates) is verified
  by API surface + controller logic + the checklist above; it cannot be
  exercised outside a live Owlbear room (no OBR runtime in the dev sandbox), and
  the preview screenshot tool only captures the standalone editor/module pages.
- Cold start opens modules at default once, then the Player module broadcasts the
  stored layout and the controller repositions (one correction).
- Compact (<1100) is a basic stacked fallback, not a bespoke small-screen design.
