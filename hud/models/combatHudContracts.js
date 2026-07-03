// Combat HUD — normalized data contracts (Phase 0).
//
// This module is the single source of truth for the *shapes* the future
// HUD consumes. It contains:
//   - frozen enums for every closed value set used by the HUD;
//   - JSDoc typedefs describing the normalized snapshot;
//   - tiny pure helpers (deep clone, empty-state/snapshot factories).
//
// It intentionally has NO imports: no Owlbear SDK, no Supabase, no CSS.
// That keeps it loadable by the plain-Node verification script (which runs
// without `node_modules`) and by the browser bundle alike.
//
// Business data stores SEMANTIC state names only. UI colours live in CSS
// (see styles/combatHudTokens.css); never encode hex/rgb here.

/* ===================== Enumerations ===================== */

/** Store lifecycle status. @enum {string} */
export const HUD_STATUS = Object.freeze({
  idle: "idle",
  loading: "loading",
  ready: "ready",
  empty: "empty",
  error: "error",
});

/** Where the store's data currently comes from. @enum {string} */
export const HUD_SOURCE = Object.freeze({
  mock: "mock",
  supabase: "supabase",
});

/** Viewer roles. The HUD only distinguishes player vs GM. @enum {string} */
export const VIEWER_ROLES = Object.freeze({
  player: "player",
  gm: "gm",
});

/** Token kinds for selection/targeting. @enum {string} */
export const TOKEN_KINDS = Object.freeze({
  player: "player",
  npc: "npc",
  turret: "turret",
  mech: "mech",
  other: "other",
});

/**
 * Semantic body/zone condition states (worsening order).
 * Do NOT add colours here — components map state → CSS token.
 * @enum {string}
 */
export const ZONE_STATES = Object.freeze({
  healthy: "healthy",
  wounded: "wounded",
  serious: "serious",
  critical: "critical",
  disabled: "disabled",
  // Phase 3D.1: combat data for this zone is missing or the fetch was denied
  // (e.g. a target refresh blocked by RLS) — must NEVER silently render as
  // "healthy". See hud/targeting/bodyConditionPolicy.js.
  unknown: "unknown",
});

/** Ordered list of zone states, mild → severe. */
export const ZONE_STATE_ORDER = Object.freeze([
  ZONE_STATES.healthy,
  ZONE_STATES.wounded,
  ZONE_STATES.serious,
  ZONE_STATES.critical,
  ZONE_STATES.disabled,
]);

/** Combat session lifecycle status. @enum {string} */
export const COMBAT_STATUS = Object.freeze({
  inactive: "inactive",
  active: "active",
  ended: "ended",
});

/** Quick-slot skill behaviours. @enum {string} */
export const SKILL_TYPES = Object.freeze({
  attackTechnique: "attackTechnique",
  targetedAbility: "targetedAbility",
  instantAbility: "instantAbility",
  toggleAbility: "toggleAbility",
  itemAction: "itemAction",
});

/** Where a quick-slot action originates. @enum {string} */
export const SKILL_SOURCES = Object.freeze({
  perk: "perk",
  psionic: "psionic",
  implant: "implant",
  item: "item",
});

/** Action economy cost categories. @enum {string} */
export const ACTION_COSTS = Object.freeze({
  free: "FREE",
  move: "MOVE",
  main: "MAIN",
  turn: "TURN",
});

/** Semantic colour roles (resolved to CSS tokens by components). @enum {string} */
export const COLOR_SEMANTICS = Object.freeze({
  attack: "attack",
  neutral: "neutral",
  psionic: "psionic",
  implant: "implant",
  intervention: "intervention",
  positive: "positive",
  negative: "negative",
});

/** Map-targeting modes. @enum {string} */
export const TARGETING_MODES = Object.freeze({
  none: "none",
  token: "token",
  multipleTokens: "multipleTokens",
  point: "point",
});

/** Modifier kinds. @enum {string} */
export const MODIFIER_KINDS = Object.freeze({
  passive: "passive",
  active: "active",
  narrative: "narrative",
});

/** Modifier polarity. @enum {string} */
export const MODIFIER_POLARITY = Object.freeze({
  positive: "positive",
  negative: "negative",
  neutral: "neutral",
});

/** Battle-log entry kinds. @enum {string} */
export const LOG_ENTRY_KINDS = Object.freeze({
  action: "action",
  system: "system",
  narrative: "narrative",
});

/**
 * Machine-readable reasons for an `empty` HUD. Human-readable text is in
 * EMPTY_REASON_TEXT; components localise from the code, never the text.
 * @enum {string}
 */
export const EMPTY_REASONS = Object.freeze({
  noToken: "NO_TOKEN_SELECTED",
  noCharacterLink: "TOKEN_HAS_NO_CHARACTER",
  notOwner: "CHARACTER_NOT_CONTROLLED_BY_VIEWER",
});

/** Default English copy for empty reasons (Phase 0 dev/diagnostics). */
export const EMPTY_REASON_TEXT = Object.freeze({
  [EMPTY_REASONS.noToken]: "No token selected.",
  [EMPTY_REASONS.noCharacterLink]: "Selected token is not linked to a character.",
  [EMPTY_REASONS.notOwner]: "You do not control this character.",
});

/** Default body zone selected for an attack before the player changes it. */
export const DEFAULT_BODY_PART_ID = "torso";

/* ===================== Pure helpers ===================== */

/**
 * Deep-clone a JSON-safe value. Prefers the platform `structuredClone`
 * (Node 17+ / modern browsers) and falls back to a JSON round-trip.
 * Used everywhere the store ingests adapter payloads so we never mutate
 * data owned by the adapter.
 * @template T
 * @param {T} value
 * @returns {T}
 */
export function cloneDeep(value) {
  if (value === null || typeof value !== "object") return value;
  if (typeof structuredClone === "function") {
    try {
      return structuredClone(value);
    } catch (_error) {
      /* fall through to JSON clone for non-structured-cloneable values */
    }
  }
  try {
    return JSON.parse(JSON.stringify(value));
  } catch (_error) {
    return value;
  }
}

/**
 * Build the empty normalized snapshot. Every HUD block can read from this
 * shape unconditionally; "no data" is represented by nulls / empty arrays
 * rather than missing keys.
 * @returns {CombatHudSnapshot}
 */
export function createEmptySnapshot() {
  return {
    entity: null,
    weapon: { primary: null, secondary: null },
    skills: { library: [], quickSlots: [] },
    combatSession: createInactiveCombatSession(),
    modifiers: { passive: [], active: [], narrative: [] },
    battleLog: { entries: [] },
  };
}

/**
 * Build an inactive combat session record.
 * @returns {CombatSession}
 */
export function createInactiveCombatSession() {
  return {
    id: null,
    status: COMBAT_STATUS.inactive,
    round: 0,
    currentParticipantId: null,
    participants: [],
    isViewerTurn: false,
  };
}

/**
 * Build the default ephemeral UI branch (the "action draft").
 * `resetActionDraft` returns the HUD to exactly this, without touching the
 * server-derived snapshot or the collapsed flag.
 * @returns {CombatHudUiState}
 */
export function createDefaultUiState() {
  return {
    isHudCollapsed: false,
    selectedTechniqueId: null,
    selectedAbilityId: null,
    selectedReloadMagazineId: null,
    selectedModifierIds: [],
    targeting: createDefaultTargeting(),
    isBattleLogExpanded: false,
  };
}

/**
 * Build the default targeting sub-state.
 * @returns {TargetingState}
 */
export function createDefaultTargeting() {
  return {
    mode: TARGETING_MODES.none,
    selectedTargetIds: [],
    selectedBodyPartId: DEFAULT_BODY_PART_ID,
    selectedPoint: null,
    radius: null,
  };
}

/* ===================== Typedefs (documentation only) ===================== */

/**
 * @typedef {Object} Viewer
 * @property {string} playerId   Owlbear Player ID of the current client.
 * @property {string} playerName Display name.
 * @property {"player"|"gm"} role
 */

/**
 * @typedef {Object} HudToken
 * @property {string} tokenId
 * @property {string} name
 * @property {string|null} characterId  Linked character, or null.
 * @property {"player"|"npc"|"turret"|"mech"|"other"} kind
 * @property {{x:number,y:number}} [position]
 */

/**
 * @typedef {Object} CombatParticipant
 * @property {string} id            Participant id (character id in mocks).
 * @property {string} name
 * @property {string|null} tokenId
 * @property {boolean} isPlayer
 * @property {number} initiative    Final initiative total (d20 + reaction).
 * @property {number} initiativeRoll Raw d20 for tie-breaking.
 * @property {number} order         Position in the queue (0-based).
 * @property {boolean} isCurrent
 * @property {boolean} canAct
 * @property {"active"|"unconscious"|"dead"|"removed"} condition
 */

/**
 * @typedef {Object} CombatSession
 * @property {string|null} id
 * @property {"inactive"|"active"|"ended"} status
 * @property {number} round
 * @property {string|null} currentParticipantId
 * @property {CombatParticipant[]} participants
 * @property {boolean} isViewerTurn
 */

/**
 * @typedef {Object} EntityZone
 * @property {string} id            Stable zone id (matches SVG zone id).
 * @property {string} label
 * @property {"healthy"|"wounded"|"serious"|"critical"|"disabled"} state
 * @property {boolean} canBeTargeted
 */

/**
 * Owner-only armour detail for a zone. Hidden from non-owner players by the
 * adapter/store; present here so the contract is explicit.
 * @typedef {Object} ZoneArmor
 * @property {string} zoneId
 * @property {string} type
 * @property {number} protection
 * @property {number} durability
 * @property {number} maxDurability
 */

/**
 * @typedef {Object} EntityStatus
 * @property {string} id
 * @property {string} name
 * @property {"positive"|"negative"|"neutral"} polarity
 * @property {number|null} durationTurns  null = condition-based / indefinite.
 * @property {string} description
 */

/**
 * @typedef {Object} EntitySummary
 * @property {string} id
 * @property {string} name
 * @property {string} icon            Asset reference / portrait id.
 * @property {"player"|"npc"|"turret"|"mech"|"other"} characterType
 * @property {string|null} ownerPlayerId  Canonical ownership (OBR Player ID).
 * @property {string} svgRef          Which SVG schema to render.
 */

/**
 * @typedef {Object} EntityRuntime
 * @property {EntitySummary} summary
 * @property {EntityZone[]} zones
 * @property {{current:number,max:number}} shield
 * @property {ZoneArmor[]} armorByZone  Owner-only; [] for restricted views.
 * @property {{current:number,max:number}} psi
 * @property {{main:boolean,move:boolean}} actions  true = available.
 * @property {EntityStatus[]} statuses
 * @property {EntityStatus[]} effects
 * @property {{alive:boolean,conscious:boolean}} flags
 * @property {MechState|null} mech
 * @property {PilotState|null} pilot
 */

/**
 * @typedef {Object} MechState
 * @property {boolean} active        true when this entity is currently a mech.
 * @property {string} name
 * @property {EntityZone[]} zones
 * @property {{current:number,max:number}} shield
 * @property {ZoneArmor[]} armorByZone
 */

/**
 * @typedef {Object} PilotState
 * @property {string} characterId
 * @property {string} name
 * @property {string} icon
 * @property {{current:number,max:number}} psi
 * @property {EntityStatus[]} statuses
 * @property {{alive:boolean,conscious:boolean}} flags
 */

/**
 * @typedef {Object} Magazine
 * @property {string} id
 * @property {string} ammoType
 * @property {string} description
 * @property {number} current
 * @property {number} max
 * @property {string} caliber       Compatibility key.
 */

/**
 * @typedef {Object} WeaponState
 * @property {string} id
 * @property {string} name
 * @property {string} svgRef
 * @property {string[]} fireModes        Subset of Semi/Burst/Auto actually available.
 * @property {string|null} currentFireMode
 * @property {boolean} usesMagazine
 * @property {boolean} usesConsumable
 * @property {boolean} requiresAmmo
 * @property {Magazine|null} loadedMagazine
 * @property {Magazine[]} reserveMagazines  Compatible & non-empty; excludes loaded.
 * @property {{current:number,max:number}} ammo  For consumable/resource weapons.
 * @property {string|null} reloadCandidateId    Selected spare magazine id (mock seed).
 * @property {boolean} canReload
 * @property {string|null} disabledReason
 */

/**
 * @typedef {Object} SkillAction
 * @property {string} id
 * @property {string} name
 * @property {"attackTechnique"|"targetedAbility"|"instantAbility"|"toggleAbility"|"itemAction"} type
 * @property {"perk"|"psionic"|"implant"|"item"} source
 * @property {string} icon
 * @property {string} color           Semantic colour role.
 * @property {"FREE"|"MOVE"|"MAIN"|"TURN"} actionCost
 * @property {{type:string,amount:number}|null} resourceCost
 * @property {number} cooldownTurns
 * @property {string[]} weaponRequirements
 * @property {"none"|"token"|"multipleTokens"|"point"} targeting
 * @property {boolean} allowsMultipleTargets
 * @property {boolean} usesPoint
 * @property {number|null} radius
 * @property {boolean} isToggled
 * @property {string|null} disabledReason
 * @property {string} tooltip
 */

/**
 * @typedef {Object} QuickSlot
 * @property {number} index          Position in the bar.
 * @property {string|null} skillId   null = empty slot.
 */

/**
 * @typedef {Object} HudModifier
 * @property {string} id
 * @property {string} name
 * @property {number} value
 * @property {string} source
 * @property {"positive"|"negative"|"neutral"} polarity
 * @property {boolean} selected
 * @property {boolean} alwaysActive
 * @property {boolean} requiresGMApproval
 * @property {boolean} consumesOnAction
 * @property {"passive"|"active"|"narrative"} kind
 * @property {string} description
 */

/**
 * @typedef {Object} BattleLogEntry
 * @property {string} id
 * @property {number} sequence
 * @property {"action"|"system"|"narrative"} kind
 * @property {string} actor
 * @property {string} action
 * @property {string} target
 * @property {string} delta          Short public outcome (no secret HP/armour).
 * @property {string} summary        One-line compact text.
 * @property {string} detail         Roll-relevant expansion (public-safe).
 */

/**
 * @typedef {Object} CombatHudSnapshot
 * @property {EntityRuntime|null} entity
 * @property {{primary:WeaponState|null,secondary:WeaponState|null}} weapon
 * @property {{library:SkillAction[],quickSlots:QuickSlot[]}} skills
 * @property {CombatSession} combatSession
 * @property {{passive:HudModifier[],active:HudModifier[],narrative:HudModifier[]}} modifiers
 * @property {{entries:BattleLogEntry[]}} battleLog
 */

/**
 * @typedef {Object} TargetingState
 * @property {"none"|"token"|"multipleTokens"|"point"} mode
 * @property {string[]} selectedTargetIds
 * @property {string|null} selectedBodyPartId
 * @property {{x:number,y:number}|null} selectedPoint
 * @property {number|null} radius
 */

/**
 * @typedef {Object} CombatHudUiState
 * @property {boolean} isHudCollapsed
 * @property {string|null} selectedTechniqueId
 * @property {string|null} selectedAbilityId
 * @property {string|null} selectedReloadMagazineId
 * @property {string[]} selectedModifierIds
 * @property {TargetingState} targeting
 * @property {boolean} isBattleLogExpanded
 */

/**
 * @typedef {Object} CombatHudState
 * @property {"idle"|"loading"|"ready"|"empty"|"error"} status
 * @property {"mock"|"supabase"} source
 * @property {Viewer} viewer
 * @property {string|null} selectedTokenId
 * @property {string|null} selectedCharacterId
 * @property {{canViewSelectedCharacter:boolean,reason:(string|null)}} access
 * @property {CombatHudSnapshot} snapshot
 * @property {CombatHudUiState} ui
 * @property {{message:string,cause:(string|null)}|null} error
 */
