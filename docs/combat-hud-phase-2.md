# Combat HUD — Phase 2: Visual Layout Shell

Phase 2 replaces the Phase 1A placeholder shell with the full visual Combat HUD:
a dark sci-fi bottom panel composed of modular blocks
(Player · Gun · Skills · Target · Modifiers + Action · Battle Log), built to the
approved reference images. It runs entirely on the Phase 0 **mock store** — no
real attacks, targeting, reloads, resource spending, RPCs, Supabase, or combat
backend. The existing action popup (Resolve Attack / Character / Bridge Shell)
is untouched, and the Phase 1A overlay controller, collapse/reopen and
UI-state restore continue to work.

## What is implemented (visual + read-only)

- **Player block** — identity, `YOUR TURN`/`WAITING`/`GM VIEW`, body silhouette
  with per-zone condition colours, shield + psi bars, MAIN/MOVE pips, status
  chips (≤5 + `+N` overflow). Mech scenario swaps to a mech silhouette + a
  `PILOT` strip.
- **Gun block** — large weapon-silhouette card with a (read-only) dropdown
  caret and fire-mode indicator, plus a right column: magazine/ammo-type card
  and a big ammo counter (turns red at 0) with a reload glyph.
- **Skill block** — quick-slot bar from the mock action library; tiles are
  accent-coloured by semantic type (attack/psionic/implant/…), with cooldown,
  resource-cost, toggle, disabled and empty states, and rich hover tooltips.
- **Target block** — prospective target derived from the mock combat queue
  (silhouette + selected body zone + shield); calm `PICK TARGET ON MAP`
  placeholder when there is none.
- **Modifier block** — compact chip grid (positive/negative/passive/narrative
  + `God Bless`), colour-coded by polarity, selected chips outlined.
- **Action block** — one large verb button (`ATTACK`/`THROW`/`CAST`/`USE`/
  `ACTIVATE`), MAIN/MOVE economy hint and a readable disabled reason.
- **Battle Log block** — compact separate card (3–5 public entries, no hidden
  HP/armour/dice); a full column on wide, a `LOG` button that expands a floating
  panel on medium/compact/mini.
- **States** — `ready` (full HUD), `waiting` (Action dimmed, Player shows
  WAITING), `empty` (calm "SELECT YOUR CHARACTER" — shell + collapse + dev
  kept, no fake data), `error` (compact card, collapse kept), `GM VIEW` badge.
- **Dev controls** — a small `DEV` toggle reveals the scenario + Player/GM
  selectors; hidden by default so the player-facing HUD doesn't look like a
  debug panel.
- **Tooltip** — one reusable cursor-following tooltip, clamped to the viewport,
  `pointer-events:none`; used by skill slots, status chips, modifier chips, the
  disabled Action button, weapon/ammo and body-zone hints.

## Intentionally deferred (NOT in Phase 2)

Real token selection · body-part targeting · drag-and-drop · magazine
swap/reload · MAIN/MOVE/psi/ammo spending · combat rolls · RPCs · Supabase ·
ownership/RLS · changes to existing APIs or the Phase 0 store. The Action
button only shows a transient "later phase" note; it never resolves combat.

## Component map

```
hud/components/
  CombatHudLayout.js     Orchestrator: composes blocks into the responsive grid,
                         wires hover/dev/collapse/log events, tooltip, local state.
  HudPanel.js            Panel frame (small top-left label + body).
  PlayerBlock.js         Identity, silhouette/zones, shield/psi, MAIN/MOVE, statuses, pilot.
  GunBlock.js            Weapon card + magazine/ammo column + fire mode.
  SkillBlock.js          Quick-slot tile bar.
  TargetBlock.js         Derived target silhouette / no-target placeholder.
  ModifierBlock.js       Modifier chip grid.
  ActionBlock.js         Primary action button + economy hint + reason.
  BattleLogBlock.js      Compact log card / expandable panel / LOG button.
  EmptyHudState.js       Empty / error / loading bodies.
  StatusChip.js          Status/effect pill.
  Tooltip.js             Reusable cursor tooltip.
  hudIcons.js            Original inline SVG icons + silhouettes (no external art).
  hudLayoutModel.js      Pure helpers: battle-log mode, empty-state copy, zone/accent class.
  combatHudLayout.css    All Phase 2 layout/module styles (scoped under .odyssey-hud).
```

Data flow: components import **pure Phase 0 selectors** (and a few new view-model
selectors in `hud/core/combatHudSelectors.js`: `selectActionLabel`,
`selectTargetView`, `selectPlayerStatusLabel`, `selectVisibleStatuses`,
`selectModifierChips`, `selectBodyPartLabel`) and render strings. They contain
no business logic, never call the OBR SDK or Supabase, and never write to the
store. `CombatHudLayout` subscribes to the store and re-renders on change;
overlay-only UI (dev-open, battle-log-expand) is local and never persisted to
the backend.

## Integration with the Phase 1A overlay

`combatHudOverlayView.js` switches collapsed → reopen pill, expanded →
`CombatHudLayout`. Its constructor signature and return surface are unchanged,
so `mountCombatHudOverlay`, the controller and the URL-restore flow are
untouched. The expanded HUD is taller than the 1A placeholder, so the overlay
sizing was updated in `hud/overlay/overlayConstants.js`:

- `EXPANDED_MAX_WIDTH` 1180 → **1480**
- `EXPANDED_HEIGHT` (wide/medium single row) → **184**
- new `COMPACT_EXPANDED_HEIGHT` (compact/mini two rows) → **324**
- new `resolveLayoutMode(width)` + `computeExpandedHeight(vw)` so the controller
  re-sizes the popover taller for two-row layouts on resize.

A latent restore bug was fixed in `mountCombatHudOverlay.js`: a null/empty
restored `selectedTokenId` no longer force-deselects the scenario's default
token (which previously made the HUD render empty on first load).

## Responsive breakpoints

Evaluated against the HUD/iframe width (≈ viewport width):

| Mode | Width | Layout |
|------|-------|--------|
| wide | ≥1280 | single row; Skills widest; Battle Log is its own column |
| medium | 960–1279 | single row; Gun/Skills compress; Battle Log → `LOG` button |
| compact | 620–959 | two rows — `Player Gun Target` / `Skills Mod Action`; Log button |
| mini | <620 | two rows, densified (labels/fallback trimmed); collapse still works |

Composition uses CSS grid + `grid-template-areas` + `clamp()` + `minmax`; no
fixed-everything sizing. Verified with no horizontal overflow at 1440 / 1280 /
1024 / 860 / 560.

## Design tokens

`hud/styles/combatHudTokens.css` carries the approved palette (deep navy
surfaces, thin blue-grey borders, accent colours for game state only). JS never
hard-codes colours — it emits semantic state names and CSS maps them:
`--odyssey-hud-zone-{healthy|wounded|serious|critical|disabled}` (healthy is a
muted cool tone, not green), `--odyssey-hud-{attack|psionic|implant|
intervention|positive|negative|neutral}`, `--odyssey-hud-{shield|psi|weapon}`,
plus `--odyssey-purple/cyan/yellow/red/green`. Geometry: outer panels
`14px`, inner cards `10px`, chips `9px`, 1px borders.

## Local preview (no Owlbear)

```bash
node dev.mjs
# open http://127.0.0.1:3000/combat-hud-overlay.html
```

Shows the HUD with an "OBR unavailable — local HUD preview" banner and working
dev scenario/role controls. Exercised scenarios: A (player, own turn →
`YOUR TURN`), B (waiting), A target = Scrap Raider, E (mech + pilot →
`PICK TARGET ON MAP`), F (unauthorised → empty), G (GM view). Resize the window
to see wide/medium/compact/mini reflow; collapse → pill and reopen both work.

## Manual Owlbear test procedure

1. `npm run build`; `node dev.mjs`.
2. Owlbear → Add Local Extension → `http://127.0.0.1:3000/manifest.dev.json`.
3. HUD appears over the bottom of the map; the action popup still opens (tabs intact).
4. Click uncovered map space — map stays interactive.
5. Resize the browser — HUD stays bottom-centered; layout reflows; the popover
   re-sizes (taller in two-row modes); no duplicate overlay.
6. Collapse → only the pill remains; reopen restores; scenario/role survive.
7. Dev controls switch scenarios (A–G) and Player/GM live.

## Validation

```bash
npm run test:hud   # Phase 0 (10) + Phase 1A (14) + Phase 2 (13) = 37 checks
npm run build      # bundles incl. assets/combat-hud-overlay.js
```

## Known limitations

- Mock store only; no live data, selection, targeting or combat.
- Target block derives the "enemy" from the mock combat queue, not a real map
  selection; its silhouette is neutral (the target's private zones aren't shown).
- Tooltips are clamped to the popover iframe rect, so they appear within the HUD
  bounds rather than floating over the whole screen.
- mini (<620px) is a densified fallback; secondary labels are hidden.

## Next task — Phase 3

Live selection state and Player/Target **read** interactions (reflecting the
real selected token / target), still without resolving combat actions.
