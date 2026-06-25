# Combat HUD — Phase 0

Foundation for the persistent on-map Combat HUD. This phase delivers the
**data, state, adapter, mock and validation layer only**. There is no visible
overlay yet, and no backend is touched.

## Scope completed in Phase 0

- Normalized HUD data contracts (JSDoc typedefs + frozen enums).
- A reactive, framework-free `CombatHudStore` with explicit state actions.
- An adapter boundary so the store never depends on a concrete data source.
- A mock adapter + seven realistic, deterministic mock scenarios.
- A Supabase adapter **skeleton** with the same interface (throws until built).
- Pure selectors for the values future components will read.
- A development-only diagnostics panel.
- Reusable semantic CSS design tokens.
- A zero-dependency Node verification script (10 checks).

## Explicit non-goals (NOT done in Phase 0)

- No persistent Owlbear stage overlay / rendering.
- No Player / Gun / Skill / Target / Modifier / Action / Log components.
- No real Supabase calls, no schema, RPC, RLS or auth changes.
- No real combat: no attacks, damage, reloads, initiative, realtime sync.
- No changes to the existing Resolve Attack / Character / Bridge Shell screens.
- No new runtime dependencies and no state-management framework.

## Module map

```
hud/
  models/
    combatHudContracts.js      Enums, JSDoc typedefs, cloneDeep, factory helpers.
    combatHudMockScenarios.js  Scenario factories A–G (fresh objects each call).
  adapters/
    combatHudAdapter.js        createCombatHudAdapter(impl, source): validates the interface.
    mockCombatHudAdapter.js    Mock data source + role/token overrides + subscribe.
    supabaseCombatHudAdapter.js Skeleton; same interface; throws "not implemented".
  core/
    combatHudActions.js        Pure state transitions + computeAccess + reasons.
    combatHudStore.js          createCombatHudStore({ adapter }): reactive store.
    combatHudSelectors.js      Pure read helpers (no DOM/CSS).
  dev/
    mountCombatHudDevPanel.js  Browser-only diagnostics panel (not for production).
  styles/
    combatHudTokens.css        Semantic CSS custom properties only.
docs/combat-hud-phase-0.md     This file.
scripts/combat-hud-phase0.test.mjs  node:assert verification.
```

Dependency rule: `core`, `models` and `adapters` import **nothing** from the
OBR SDK, Supabase, or CSS. This keeps them loadable by the Node verification
script (which runs without `node_modules`) and by the browser bundle alike.
Only `dev/` touches the DOM.

## Store lifecycle

1. `createCombatHudStore({ adapter })` — builds initial `idle` state.
2. `initialize()` — sets `loading`, subscribes to the adapter once, then runs
   the single refresh path `refreshRuntime()`.
3. `refreshRuntime()` — the one place that reads the adapter and recomputes
   state. Used after mutation / external update / error reconciliation.
4. Adapter notifications (`subscribe`) re-trigger `refreshRuntime()`.
5. `dispose()` — unsubscribes from the adapter, clears listeners, becomes inert.

State statuses: `idle → loading → ready | empty | error`.

```
{
  status, source, viewer, selectedTokenId, selectedCharacterId,
  access: { canViewSelectedCharacter, reason },
  snapshot: { entity, weapon, skills, combatSession, modifiers, battleLog },
  ui: { isHudCollapsed, selectedTechniqueId, selectedAbilityId,
        selectedReloadMagazineId, selectedModifierIds, targeting,
        isBattleLogExpanded },
  error
}
```

The store never mutates adapter-returned payloads: everything ingested is
deep-cloned (`cloneDeep`) before it enters `snapshot`. UI-only changes
(`setHudCollapsed`, `resetActionDraft`) touch the `ui` branch and leave the
server-derived `snapshot` intact.

### Public store actions

`initialize`, `selectToken`, `setViewer`, `setViewerRole`, `setHudCollapsed`,
`setMockScenario`, `resetActionDraft`, `dispose`. Reads: `getState`,
`subscribe`, `isReady()`, `status`.

## Adapter contract

`createCombatHudAdapter(impl, source)` requires these methods:

Data getters: `getViewer`, `getSelectedTokenId`, `getSceneTokens`,
`getCharacterForToken`, `getCharacterRuntime`, `getWeaponState`,
`getAvailableSkills`, `getModifiers`, `getCombatSession`, `getBattleLog`.

Mutators (Phase 0): `selectToken`, `setViewerRole`, `setMockScenario`.

Lifecycle: `subscribe(listener) → unsubscribe`, `dispose`.

The store depends only on this surface. Swapping mock → Supabase is a
one-line adapter swap at the composition root.

## Ownership rule expected by the future Supabase adapter

- Canonical ownership is `public.odyssey_characters.owner_player_id`
  (the OBR Player ID). Token links (`odyssey_token_links`) map token →
  character only and are **not** authorization.
- A player may view a character's HUD only when `owner_player_id` equals the
  viewer's OBR Player ID. The GM bypasses this.
- In Phase 0 this is computed client-side by `computeAccess(viewer, entity)`
  purely for UX. **This is not security.** The server must enforce ownership
  (Task B0) and must never trust an `owner_player_id` sent from the client.

## Mock scenarios

| ID | Name | Purpose |
|----|------|---------|
| A | Player, own turn | Owned character, active combat, viewer's turn; full weapon/magazine/skill/modifier/log data. |
| B | Player, waiting | Same character not current participant; actions spent; `WAITING`. |
| C | NPC target (humanoid) | Linked NPC; empty for a player, inspectable by GM. |
| D | Turret (non-humanoid) | Custom zone schema + own SVG ref; no humanoid assumptions. |
| E | Mech + pilot | Mech is primary entity; nested pilot summary (psi/status). |
| F | Unauthorised selection | Player selects an NPC → empty with reason. |
| G | GM inspection | Same selection as F but viewer is GM → ready. |

Each scenario is produced by a factory, so every load yields fresh,
independently-mutable objects.

## Migration path: mock adapter → Supabase adapter

1. Implement `supabaseCombatHudAdapter` method-by-method against the same
   interface (mapping notes are inline in that file), driven by `runtime`
   (`bridges.obr`, `api.placement`, etc.).
2. Source the viewer/selection from OBR; source character/weapon/skill/
   modifier data from `get_character_runtime_bundle`; source session/log from
   the combat-session RPCs (Tasks B1/B2, not yet built).
3. At the composition root, build the Supabase adapter instead of the mock and
   pass it to `createCombatHudStore`. No store, selector or component change.
4. Keep the mock adapter for tests and offline development.

## Running the verification

```bash
npm run test:hud
# or: node scripts/combat-hud-phase0.test.mjs
```

Covers: ready/empty access outcomes, GM inspection, unlinked token, scenario
refresh, subscription firing, safe dispose, reserve-magazine filtering,
compact-log truncation, and draft reset preserving the snapshot.

> Note: `npm run build` (esbuild) requires `npm install` first; the HUD core is
> validated independently by the dependency-free script above.

## Using the dev diagnostics panel (development only)

Not wired into the production popup. Mount it manually in a dev context:

```js
import { mountCombatHudDevPanel } from "./hud/dev/mountCombatHudDevPanel.js";
const panel = mountCombatHudDevPanel({ root: document.body });
// ... later: panel.unmount();
```

It lets you switch scenario, flip viewer player/GM, select a token, and inspect
the live store status, access result and normalized JSON state.

## Next task — Phase 1A

Implement the **persistent Owlbear stage overlay**: mount a bottom-anchored
HUD surface via `OBR.popover.open()` (same pattern proven by the initiative
strip), with collapse/reopen, responsive re-anchoring on viewport resize, and
the store wired to live OBR selection — still rendering from the mock adapter
until the Supabase combat backend exists.
