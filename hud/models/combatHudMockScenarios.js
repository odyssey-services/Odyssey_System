// Combat HUD — mock scenarios (Phase 0).
//
// Realistic, deterministic, *local* data used to develop the HUD before the
// Supabase combat backend exists. Each scenario is produced by a FACTORY so
// every call returns fresh, independently-mutable objects (no shared mutable
// global constant). The mock adapter consumes these; production API modules
// never import this file.
//
// Pure module: no SDK, no Supabase, no CSS. Loadable under plain Node.

import {
  VIEWER_ROLES,
  TOKEN_KINDS,
  ZONE_STATES,
  COMBAT_STATUS,
  SKILL_TYPES,
  SKILL_SOURCES,
  ACTION_COSTS,
  COLOR_SEMANTICS,
  TARGETING_MODES,
  MODIFIER_KINDS,
  MODIFIER_POLARITY,
  LOG_ENTRY_KINDS,
} from "./combatHudContracts.js";

/* ===================== Stable identities ===================== */

// The "self" player — the client viewing the HUD in most scenarios.
const SELF_PLAYER = Object.freeze({ playerId: "obr-player-self", playerName: "Vega (You)" });
// A different player, used to prove ownership rejection.
const OTHER_PLAYER = Object.freeze({ playerId: "obr-player-other", playerName: "Rook" });

/* ===================== Small factory helpers ===================== */

/**
 * @param {string} id
 * @param {string} label
 * @param {string} state
 * @param {boolean} [canBeTargeted]
 * @returns {import("./combatHudContracts.js").EntityZone}
 */
function zone(id, label, state, canBeTargeted = true) {
  return { id, label, state, canBeTargeted };
}

/** Standard humanoid zone set. */
function humanoidZones(states = {}) {
  return [
    zone("head", "Head", states.head ?? ZONE_STATES.healthy),
    zone("torso", "Torso", states.torso ?? ZONE_STATES.healthy),
    zone("l_arm", "Left Arm", states.l_arm ?? ZONE_STATES.healthy),
    zone("r_arm", "Right Arm", states.r_arm ?? ZONE_STATES.healthy),
    zone("l_leg", "Left Leg", states.l_leg ?? ZONE_STATES.healthy),
    zone("r_leg", "Right Leg", states.r_leg ?? ZONE_STATES.healthy),
  ];
}

/** @returns {import("./combatHudContracts.js").ZoneArmor} */
function armor(zoneId, type, protection, durability, maxDurability) {
  return { zoneId, type, protection, durability, maxDurability };
}

/** @returns {import("./combatHudContracts.js").EntityStatus} */
function status(id, name, polarity, durationTurns, description) {
  return { id, name, polarity, durationTurns, description };
}

/** @returns {import("./combatHudContracts.js").Magazine} */
function magazine(id, ammoType, description, current, max, caliber) {
  return { id, ammoType, description, current, max, caliber };
}

/**
 * @param {Partial<import("./combatHudContracts.js").SkillAction>} overrides
 * @returns {import("./combatHudContracts.js").SkillAction}
 */
function skill(overrides) {
  return {
    id: overrides.id,
    name: overrides.name ?? "Ability",
    type: overrides.type ?? SKILL_TYPES.instantAbility,
    source: overrides.source ?? SKILL_SOURCES.perk,
    icon: overrides.icon ?? "ability",
    color: overrides.color ?? COLOR_SEMANTICS.neutral,
    actionCost: overrides.actionCost ?? ACTION_COSTS.main,
    resourceCost: overrides.resourceCost ?? null,
    cooldownTurns: overrides.cooldownTurns ?? 0,
    weaponRequirements: overrides.weaponRequirements ?? [],
    targeting: overrides.targeting ?? TARGETING_MODES.none,
    allowsMultipleTargets: overrides.allowsMultipleTargets ?? false,
    usesPoint: overrides.usesPoint ?? false,
    radius: overrides.radius ?? null,
    isToggled: overrides.isToggled ?? false,
    disabledReason: overrides.disabledReason ?? null,
    tooltip: overrides.tooltip ?? "",
  };
}

/** Build a quick-slot layout from an array of skill ids (null = empty slot). */
function quickSlots(ids) {
  return ids.map((skillId, index) => ({ index, skillId: skillId ?? null }));
}

/**
 * @param {Partial<import("./combatHudContracts.js").HudModifier>} overrides
 * @returns {import("./combatHudContracts.js").HudModifier}
 */
function modifier(overrides) {
  return {
    id: overrides.id,
    name: overrides.name ?? "Modifier",
    value: overrides.value ?? 0,
    source: overrides.source ?? "system",
    polarity: overrides.polarity ?? MODIFIER_POLARITY.neutral,
    selected: overrides.selected ?? false,
    alwaysActive: overrides.alwaysActive ?? false,
    requiresGMApproval: overrides.requiresGMApproval ?? false,
    consumesOnAction: overrides.consumesOnAction ?? false,
    kind: overrides.kind ?? MODIFIER_KINDS.active,
    description: overrides.description ?? "",
  };
}

/** @returns {import("./combatHudContracts.js").BattleLogEntry} */
function logEntry(sequence, kind, actor, action, target, delta, detail) {
  return {
    id: `log-${sequence}`,
    sequence,
    kind,
    actor,
    action,
    target,
    delta,
    summary: [actor, action, target, delta].filter(Boolean).join(" · "),
    detail: detail ?? "",
  };
}

/** @returns {import("./combatHudContracts.js").CombatParticipant} */
function participant(overrides) {
  return {
    id: overrides.id,
    name: overrides.name ?? overrides.id,
    tokenId: overrides.tokenId ?? null,
    isPlayer: overrides.isPlayer ?? false,
    initiative: overrides.initiative ?? 0,
    initiativeRoll: overrides.initiativeRoll ?? 0,
    order: overrides.order ?? 0,
    isCurrent: overrides.isCurrent ?? false,
    canAct: overrides.canAct ?? true,
    condition: overrides.condition ?? "active",
  };
}

/* ===================== Reusable entity / weapon builders ===================== */

/** Player-owned rifleman "Vega". */
function makeVegaEntity() {
  return {
    summary: {
      id: "char-vega",
      name: "Vega",
      icon: "portrait-vega",
      characterType: TOKEN_KINDS.player,
      ownerPlayerId: SELF_PLAYER.playerId,
      svgRef: "humanoid",
    },
    zones: humanoidZones({
      l_arm: ZONE_STATES.wounded,
      r_leg: ZONE_STATES.serious,
    }),
    shield: { current: 6, max: 15 },
    armorByZone: [
      armor("head", "Composite Helm", 3, 8, 10),
      armor("torso", "Ceramic Plate", 5, 14, 20),
      armor("l_arm", "Mesh", 2, 3, 6),
    ],
    psi: { current: 4, max: 10 },
    actions: { main: true, move: true },
    statuses: [
      status("st-focus", "Focused", MODIFIER_POLARITY.positive, 2, "+10 to next attack."),
      status("st-bleed", "Bleeding", MODIFIER_POLARITY.negative, 3, "Lose 1 minor wound per turn."),
    ],
    effects: [
      status("ef-adrenaline", "Adrenaline", MODIFIER_POLARITY.positive, 1, "MOVE actions are free this turn."),
    ],
    flags: { alive: true, conscious: true },
    mech: null,
    pilot: null,
  };
}

/** Vega's primary firearm with a realistic magazine economy. */
function makeVegaWeapon() {
  return {
    id: "wpn-vega-rifle",
    name: "AR-7 Marksman Rifle",
    svgRef: "rifle",
    fireModes: ["Semi", "Burst"],
    currentFireMode: "Semi",
    usesMagazine: true,
    usesConsumable: false,
    requiresAmmo: true,
    loadedMagazine: magazine("mag-loaded", "AP", "Armor-piercing", 12, 30, "7.62"),
    reserveMagazines: [
      magazine("mag-full", "AP", "Armor-piercing", 30, 30, "7.62"),
      magazine("mag-partial", "HP", "Hollow-point", 8, 30, "7.62"),
      // The following two are intentionally invalid for the reserve list and
      // are filtered by selectVisibleReserveMagazines:
      magazine("mag-empty", "AP", "Armor-piercing", 0, 30, "7.62"), // empty
      magazine("mag-wrong", "SG", "Shotgun shells", 6, 6, "12ga"), // wrong caliber
    ],
    ammo: { current: 12, max: 30 },
    reloadCandidateId: "mag-full",
    canReload: true,
    disabledReason: null,
  };
}

/** Vega's quick-slot library covering all five skill behaviours. */
function makeVegaSkills() {
  const library = [
    skill({
      id: "sk-precise", name: "Precision Shot", type: SKILL_TYPES.attackTechnique,
      source: SKILL_SOURCES.perk, icon: "scope", color: COLOR_SEMANTICS.attack,
      actionCost: ACTION_COSTS.main, weaponRequirements: ["rifle"], targeting: TARGETING_MODES.token,
      tooltip: "Aimed shot. +precision, zone penalty unchanged.",
    }),
    skill({
      id: "sk-burst", name: "Suppressive Burst", type: SKILL_TYPES.attackTechnique,
      source: SKILL_SOURCES.perk, icon: "burst", color: COLOR_SEMANTICS.attack,
      actionCost: ACTION_COSTS.main, weaponRequirements: ["rifle"],
      targeting: TARGETING_MODES.multipleTokens, allowsMultipleTargets: true,
      tooltip: "Hit up to 3 targets in an arc.",
    }),
    skill({
      id: "sk-mindspike", name: "Mind Spike", type: SKILL_TYPES.targetedAbility,
      source: SKILL_SOURCES.psionic, icon: "psi", color: COLOR_SEMANTICS.psionic,
      actionCost: ACTION_COSTS.main, resourceCost: { type: "psi", amount: 3 },
      cooldownTurns: 2, targeting: TARGETING_MODES.token,
      tooltip: "Psionic damage to one mind. Costs 3 Psi, 2-turn cooldown.",
    }),
    skill({
      id: "sk-grenade", name: "Frag Grenade", type: SKILL_TYPES.itemAction,
      source: SKILL_SOURCES.item, icon: "grenade", color: COLOR_SEMANTICS.attack,
      actionCost: ACTION_COSTS.main, targeting: TARGETING_MODES.point,
      usesPoint: true, radius: 3,
      tooltip: "Throw to a point. 3m blast radius.",
    }),
    skill({
      id: "sk-stim", name: "Combat Stim", type: SKILL_TYPES.instantAbility,
      source: SKILL_SOURCES.item, icon: "injector", color: COLOR_SEMANTICS.positive,
      actionCost: ACTION_COSTS.free,
      tooltip: "Instant self-heal. No confirmation.",
    }),
    skill({
      id: "sk-cloak", name: "Optic Cloak", type: SKILL_TYPES.toggleAbility,
      source: SKILL_SOURCES.implant, icon: "cloak", color: COLOR_SEMANTICS.implant,
      actionCost: ACTION_COSTS.move, isToggled: false,
      tooltip: "Toggle camouflage. Active until disabled.",
    }),
    skill({
      id: "sk-overload", name: "Implant Overload", type: SKILL_TYPES.instantAbility,
      source: SKILL_SOURCES.implant, icon: "bolt", color: COLOR_SEMANTICS.implant,
      actionCost: ACTION_COSTS.main, cooldownTurns: 4,
      disabledReason: "On cooldown (3 turns left).",
      tooltip: "Disabled: cooling down.",
    }),
  ];
  return { library, quickSlots: quickSlots([
    "sk-precise", "sk-burst", "sk-mindspike", "sk-grenade", "sk-stim", "sk-cloak", null, "sk-overload",
  ]) };
}

/** Vega's modifier set: passive (always), active (selectable), narrative (GM). */
function makeVegaModifiers() {
  return [
    modifier({
      id: "mod-veteran", name: "Veteran Aim", value: 5, source: "perk",
      polarity: MODIFIER_POLARITY.positive, alwaysActive: true, kind: MODIFIER_KINDS.passive,
      description: "Passive +5 to ranged attacks.",
    }),
    modifier({
      id: "mod-scope", name: "Scope", value: 10, source: "weapon",
      polarity: MODIFIER_POLARITY.positive, alwaysActive: true, kind: MODIFIER_KINDS.passive,
      description: "Passive +10 when aiming.",
    }),
    modifier({
      id: "mod-cover", name: "Target in Cover", value: -10, source: "positioning",
      polarity: MODIFIER_POLARITY.negative, kind: MODIFIER_KINDS.active,
      description: "Apply when the target benefits from cover.",
    }),
    modifier({
      id: "mod-prepared", name: "Prepared", value: 20, source: "positioning",
      polarity: MODIFIER_POLARITY.positive, kind: MODIFIER_KINDS.active,
      description: "Aim taken last turn.",
    }),
    modifier({
      id: "mod-godbless", name: "God Bless", value: 0, source: "intervention",
      polarity: MODIFIER_POLARITY.positive, kind: MODIFIER_KINDS.active,
      consumesOnAction: true,
      description: "Intervention: re-roll. Resource consumed only on success.",
    }),
    modifier({
      id: "mod-gm-highground", name: "High Ground (GM)", value: 15, source: "gm",
      polarity: MODIFIER_POLARITY.positive, kind: MODIFIER_KINDS.narrative,
      requiresGMApproval: true,
      description: "GM-granted narrative bonus.",
    }),
  ];
}

/** Build a humanoid NPC raider (used as target / unauthorised selection). */
function makeRaiderEntity() {
  return {
    summary: {
      id: "char-raider", name: "Scrap Raider", icon: "portrait-raider",
      characterType: TOKEN_KINDS.npc, ownerPlayerId: null, svgRef: "humanoid",
    },
    zones: humanoidZones({ torso: ZONE_STATES.wounded, head: ZONE_STATES.healthy }),
    shield: { current: 0, max: 0 },
    armorByZone: [], // hidden from players; GM view still keeps it minimal in mocks
    psi: { current: 0, max: 0 },
    actions: { main: true, move: true },
    statuses: [status("st-enraged", "Enraged", MODIFIER_POLARITY.negative, null, "Attacks recklessly.")],
    effects: [],
    flags: { alive: true, conscious: true },
    mech: null,
    pilot: null,
  };
}

/* ===================== Scenario factories ===================== */

/** Common wrapper so each scenario shares a consistent shape. */
function scenario(base) {
  return {
    id: base.id,
    label: base.label,
    description: base.description,
    defaultViewerRole: base.defaultViewerRole,
    viewer: base.viewer,
    selectedTokenId: base.selectedTokenId ?? null,
    tokens: base.tokens ?? [],
    links: base.links ?? {},
    characters: base.characters ?? {},
    weapons: base.weapons ?? {},
    skills: base.skills ?? {},
    modifiers: base.modifiers ?? {},
    combatSession: base.combatSession ?? null,
    battleLog: base.battleLog ?? { entries: [] },
  };
}

/** Scenario A — controlled player during their own turn. */
function scenarioA() {
  const tokens = [
    { tokenId: "tok-vega", name: "Vega", characterId: "char-vega", kind: TOKEN_KINDS.player, position: { x: 4, y: 2 } },
    { tokenId: "tok-raider", name: "Scrap Raider", characterId: "char-raider", kind: TOKEN_KINDS.npc, position: { x: 9, y: 3 } },
    // Unlinked scene prop — exists as a token but maps to no character.
    // Used to exercise the "token without character" empty state.
    { tokenId: "tok-crate", name: "Supply Crate", characterId: null, kind: TOKEN_KINDS.other, position: { x: 2, y: 8 } },
  ];
  return scenario({
    id: "A", label: "A · Player, own turn",
    description: "Owned player character, active combat, it is the viewer's turn.",
    defaultViewerRole: VIEWER_ROLES.player,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.player },
    selectedTokenId: "tok-vega",
    tokens,
    links: { "tok-vega": "char-vega", "tok-raider": "char-raider" },
    characters: { "char-vega": makeVegaEntity(), "char-raider": makeRaiderEntity() },
    weapons: { "char-vega": { primary: makeVegaWeapon(), secondary: null } },
    skills: { "char-vega": makeVegaSkills() },
    modifiers: { "char-vega": makeVegaModifiers() },
    combatSession: {
      id: "sess-1", status: COMBAT_STATUS.active, round: 2, currentParticipantId: "char-vega",
      participants: [
        participant({ id: "char-vega", name: "Vega", tokenId: "tok-vega", isPlayer: true, initiative: 22, initiativeRoll: 18, order: 0, isCurrent: true }),
        participant({ id: "char-raider", name: "Scrap Raider", tokenId: "tok-raider", initiative: 14, initiativeRoll: 11, order: 1 }),
      ],
    },
    battleLog: { entries: [
      logEntry(1, LOG_ENTRY_KINDS.system, "", "Combat started", "", "", "Round 1 begins."),
      logEntry(2, LOG_ENTRY_KINDS.action, "Scrap Raider", "Attacks", "Vega", "Shield -4", "Rolled 65 vs torso."),
      logEntry(3, LOG_ENTRY_KINDS.action, "Vega", "Precision Shot", "Scrap Raider", "Wounds head", "Rolled 12, hit."),
      logEntry(4, LOG_ENTRY_KINDS.narrative, "GM", "Smoke drifts across the lane", "", "", "Light cover next round."),
      logEntry(5, LOG_ENTRY_KINDS.system, "", "Round 2 begins", "", "", "Actions restored."),
    ] },
  });
}

/** Scenario B — same player, waiting for their turn. */
function scenarioB() {
  const a = scenarioA();
  const vega = a.characters["char-vega"];
  vega.actions = { main: false, move: false }; // spent / not their turn
  return scenario({
    ...a,
    id: "B", label: "B · Player, waiting",
    description: "Owned player character, combat active, NOT the viewer's turn.",
    combatSession: {
      ...a.combatSession,
      currentParticipantId: "char-raider",
      participants: a.combatSession.participants.map((p) => ({
        ...p, isCurrent: p.id === "char-raider",
      })),
    },
  });
}

/** Scenario C — NPC humanoid target (player has no access; GM does). */
function scenarioC() {
  const tokens = [
    { tokenId: "tok-raider", name: "Scrap Raider", characterId: "char-raider", kind: TOKEN_KINDS.npc, position: { x: 9, y: 3 } },
  ];
  return scenario({
    id: "C", label: "C · NPC target (humanoid)",
    description: "Linked NPC humanoid. Player gets empty HUD; GM can inspect.",
    defaultViewerRole: VIEWER_ROLES.gm,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.gm },
    selectedTokenId: "tok-raider",
    tokens,
    links: { "tok-raider": "char-raider" },
    characters: { "char-raider": makeRaiderEntity() },
    weapons: {},
    skills: {},
    modifiers: {},
    combatSession: null,
    battleLog: { entries: [] },
  });
}

/** Scenario D — turret / non-humanoid target with its own zone schema. */
function scenarioD() {
  const turret = {
    summary: {
      id: "char-turret", name: "Sentry Turret MK-II", icon: "portrait-turret",
      characterType: TOKEN_KINDS.turret, ownerPlayerId: null, svgRef: "turret",
    },
    zones: [
      zone("barrel", "Barrel Assembly", ZONE_STATES.healthy),
      zone("housing", "Housing", ZONE_STATES.wounded),
      zone("sensor", "Sensor Array", ZONE_STATES.serious),
      zone("base", "Base Mount", ZONE_STATES.healthy, false),
    ],
    shield: { current: 10, max: 10 },
    armorByZone: [armor("housing", "Plated Steel", 6, 18, 25)],
    psi: { current: 0, max: 0 },
    actions: { main: true, move: false },
    statuses: [],
    effects: [status("ef-overheat", "Overheating", MODIFIER_POLARITY.negative, 1, "Skips next turn if not cooled.")],
    flags: { alive: true, conscious: true },
    mech: null,
    pilot: null,
  };
  return scenario({
    id: "D", label: "D · Turret target (non-humanoid)",
    description: "Non-humanoid entity with a custom zone schema and its own SVG.",
    defaultViewerRole: VIEWER_ROLES.gm,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.gm },
    selectedTokenId: "tok-turret",
    tokens: [{ tokenId: "tok-turret", name: "Sentry Turret", characterId: "char-turret", kind: TOKEN_KINDS.turret, position: { x: 12, y: 7 } }],
    links: { "tok-turret": "char-turret" },
    characters: { "char-turret": turret },
  });
}

/** Scenario E — mech as primary entity with a nested pilot summary. */
function scenarioE() {
  const pilotPsi = { current: 5, max: 8 };
  const mechEntity = {
    summary: {
      id: "char-vega", name: "Vega — 'Ironclad' Mech", icon: "portrait-mech",
      characterType: TOKEN_KINDS.mech, ownerPlayerId: SELF_PLAYER.playerId, svgRef: "mech",
    },
    // Top-level zones mirror the mech while piloting.
    zones: [
      zone("m_head", "Cockpit", ZONE_STATES.healthy),
      zone("m_core", "Reactor Core", ZONE_STATES.wounded),
      zone("m_l_arm", "Left Manipulator", ZONE_STATES.healthy),
      zone("m_r_arm", "Right Weapon Mount", ZONE_STATES.serious),
      zone("m_legs", "Locomotion", ZONE_STATES.healthy),
    ],
    shield: { current: 25, max: 40 },
    armorByZone: [
      armor("m_core", "Reactor Shielding", 12, 30, 50),
      armor("m_r_arm", "Hardpoint Plating", 9, 12, 30),
    ],
    psi: pilotPsi,
    actions: { main: true, move: true },
    statuses: [status("st-locked", "Weapons Locked", MODIFIER_POLARITY.positive, null, "Targeting computer engaged.")],
    effects: [],
    flags: { alive: true, conscious: true },
    mech: {
      active: true,
      name: "'Ironclad' Assault Frame",
      zones: [
        zone("m_core", "Reactor Core", ZONE_STATES.wounded),
        zone("m_r_arm", "Right Weapon Mount", ZONE_STATES.serious),
      ],
      shield: { current: 25, max: 40 },
      armorByZone: [armor("m_core", "Reactor Shielding", 12, 30, 50)],
    },
    pilot: {
      characterId: "char-vega-pilot", name: "Vega", icon: "portrait-vega",
      psi: pilotPsi,
      statuses: [status("st-strain", "Neural Strain", MODIFIER_POLARITY.negative, 2, "Psi regen halved.")],
      flags: { alive: true, conscious: true },
    },
  };
  return scenario({
    id: "E", label: "E · Mech + pilot",
    description: "Mech is the primary displayed entity; pilot summary nested beneath.",
    defaultViewerRole: VIEWER_ROLES.player,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.player },
    selectedTokenId: "tok-mech",
    tokens: [{ tokenId: "tok-mech", name: "Ironclad", characterId: "char-vega", kind: TOKEN_KINDS.mech, position: { x: 5, y: 5 } }],
    links: { "tok-mech": "char-vega" },
    characters: { "char-vega": mechEntity },
    weapons: { "char-vega": { primary: makeVegaWeapon(), secondary: null } },
    skills: { "char-vega": makeVegaSkills() },
    modifiers: { "char-vega": makeVegaModifiers() },
    combatSession: {
      id: "sess-2", status: COMBAT_STATUS.active, round: 1, currentParticipantId: "char-vega",
      participants: [participant({ id: "char-vega", name: "Ironclad", tokenId: "tok-mech", isPlayer: true, initiative: 19, initiativeRoll: 15, order: 0, isCurrent: true })],
    },
    battleLog: { entries: [logEntry(1, LOG_ENTRY_KINDS.system, "", "Combat started", "", "", "Mech deployed.")] },
  });
}

/** Scenario F — unauthorised selection (player selects an NPC). */
function scenarioF() {
  return scenario({
    id: "F", label: "F · Unauthorised selection",
    description: "Player selects an NPC they do not control → empty HUD with reason.",
    defaultViewerRole: VIEWER_ROLES.player,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.player },
    selectedTokenId: "tok-raider",
    tokens: [{ tokenId: "tok-raider", name: "Scrap Raider", characterId: "char-raider", kind: TOKEN_KINDS.npc, position: { x: 9, y: 3 } }],
    links: { "tok-raider": "char-raider" },
    characters: { "char-raider": makeRaiderEntity() },
  });
}

/** Scenario G — GM inspecting the same selection as F. */
function scenarioG() {
  const f = scenarioF();
  return scenario({
    ...f,
    id: "G", label: "G · GM inspection",
    description: "Same selection as F, but the viewer is GM → HUD becomes ready.",
    defaultViewerRole: VIEWER_ROLES.gm,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.gm },
  });
}

/* ===================== Public registry ===================== */

/**
 * Ordered list of scenario factories. Each call returns a fresh scenario.
 * @type {ReadonlyArray<{id:string,label:string,create:()=>any}>}
 */
export const MOCK_SCENARIOS = Object.freeze([
  { id: "A", label: "A · Player, own turn", create: scenarioA },
  { id: "B", label: "B · Player, waiting", create: scenarioB },
  { id: "C", label: "C · NPC target (humanoid)", create: scenarioC },
  { id: "D", label: "D · Turret target (non-humanoid)", create: scenarioD },
  { id: "E", label: "E · Mech + pilot", create: scenarioE },
  { id: "F", label: "F · Unauthorised selection", create: scenarioF },
  { id: "G", label: "G · GM inspection", create: scenarioG },
]);

/** Default scenario id used when a store/adapter initialises. */
export const DEFAULT_SCENARIO_ID = "A";

/**
 * Create a fresh, deeply-independent copy of a scenario by id.
 * @param {string} scenarioId
 * @returns {any} the scenario data (throws on unknown id)
 */
export function createScenario(scenarioId) {
  const entry = MOCK_SCENARIOS.find((s) => s.id === scenarioId);
  if (!entry) {
    throw new Error(`Unknown mock scenario: ${scenarioId}`);
  }
  return entry.create();
}

/** List scenario ids/labels for dev UIs. */
export function listScenarios() {
  return MOCK_SCENARIOS.map(({ id, label }) => ({ id, label }));
}

export { SELF_PLAYER, OTHER_PLAYER };
