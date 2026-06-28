// Combat HUD — Phase 3A.1: runtime bundle mapper (PURE, no OBR/Supabase/DOM).
//
// Maps the raw `get_character_runtime_bundle` Supabase RPC response to the
// CombatHudSnapshot shape that the existing block renderers consume. Every field
// access is defensive (optional chaining / null-coalescing) so a missing section
// produces an honest empty/null value and never throws.
//
// ─── Expected bundle top-level shape ────────────────────────────────────────
//
//  bundle.character   { id, display_name, character_key,
//                       owner_player_id, owner_player_name }
//
//  bundle.state       { is_alive, is_conscious, status_summary,
//                       combat_flags?: { main_action_spent, move_action_spent },
//                       shield_current?, shield_max?,
//                       psi_current?,   psi_max? }
//
//  bundle.combat      { body_parts: [{ zone_id, minor, serious, critical,
//                                      disabled, destroyed,
//                                      armor_value, armor_critical }],
//                       armor_summary: [...],
//                       combat_flags:  { main_action_spent, move_action_spent },
//                       shield_current?, shield_max?,
//                       psi_current?,   psi_max?,
//                       is_alive, is_conscious, state_version, status_summary }
//
//  bundle.armory      CANONICAL shape (same payload as get_character_armory, the
//                     RPC the existing Combat / Resolve-Attack menu renders from —
//                     see screens/resolveAttack/resolveAttackScreen.js):
//                     { weapons: [{
//                         id, name,
//                         model: { weapon_class_name, weapon_class, caliber },
//                         active_profile_id,
//                         active_profile: { id, name, code, loaded_magazine,
//                                           selected_fire_mode, available_fire_modes },
//                         loaded_magazine: { id, current_rounds, capacity,
//                                            ammo_type_name, ammo_type:{name},
//                                            magazine_def:{ capacity, caliber, caliber_name } },
//                         selected_fire_mode: { id, name, code },
//                         available_fire_modes: [{ id, name, code }],
//                         features: [...]
//                       }],
//                       magazines: [{ ...magazine shape... }] }
//                     The active weapon is weapons[0] (the menu uses weapons[0];
//                     weapons carry NO is_equipped flag — that flag belongs to
//                     equipment/armor). We still honour an explicit equipped/active
//                     flag if the backend ever adds one, and tolerate a single
//                     armory.equipped_weapon object as a fallback projection.
//
//  bundle.abilities   { quick_actions: [{
//                         id, ability_name, ability_type, source_type,
//                         icon_key, color_key, action_cost,
//                         cooldown_remaining_turns, is_toggled,
//                         disabled_reason, tooltip,
//                         targeting_mode?, allows_multiple_targets?,
//                         uses_point?, radius?,
//                         weapon_requirements?: string[]
//                       }],
//                       quickbar_slots: [{ slot_index, ability_id }] }
//
//  bundle.effects     [{ id, effect_name, polarity,
//                        remaining_turns, description }]
//
// IMPORTANT: These field names are inferred from DB/RPC conventions and the
// characterPlacementApi.js section list. Verify against the actual RPC
// implementation before assuming they are correct. The mapper degrades
// gracefully if any field is absent.
// ────────────────────────────────────────────────────────────────────────────

import {
  ZONE_STATES,
  MODIFIER_POLARITY,
  SKILL_TYPES,
  SKILL_SOURCES,
  COLOR_SEMANTICS,
  TARGETING_MODES,
  ACTION_COSTS,
  createInactiveCombatSession,
} from "../models/combatHudContracts.js";

// ─── Tiny coerce helpers ────────────────────────────────────────────────────

function str(v) {
  const s = String(v ?? "").trim();
  return s || null;
}

function num(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function bool(v, fallback = false) {
  return v === null || v === undefined ? fallback : Boolean(v);
}

// ─── Zone state ─────────────────────────────────────────────────────────────
// body_part columns: minor, serious, critical, disabled, destroyed.
// Map to the internal ZONE_STATES enum (worsening severity).

function zoneStateFromBodyPart(bp) {
  if (bool(bp?.destroyed) || bool(bp?.disabled)) return ZONE_STATES.disabled;
  if (num(bp?.critical) > 0) return ZONE_STATES.critical;
  if (num(bp?.serious) > 0) return ZONE_STATES.serious;
  if (num(bp?.minor) > 0) return ZONE_STATES.wounded;
  return ZONE_STATES.healthy;
}

const ZONE_LABELS = Object.freeze({
  head: "Head", torso: "Torso",
  l_arm: "Left Arm", r_arm: "Right Arm",
  l_leg: "Left Leg", r_leg: "Right Leg",
});

function mapZones(bodyParts) {
  if (!Array.isArray(bodyParts) || bodyParts.length === 0) return [];
  return bodyParts.map((bp) => {
    const id = str(bp?.zone_id) ?? "unknown";
    return {
      id,
      label: ZONE_LABELS[id] ?? id,
      state: zoneStateFromBodyPart(bp),
      canBeTargeted: !bool(bp?.disabled) && !bool(bp?.destroyed),
    };
  });
}

// ─── Effects / statuses ──────────────────────────────────────────────────────

function normalizePolarity(p) {
  const v = String(p ?? "").toLowerCase();
  if (v === "positive") return MODIFIER_POLARITY.positive;
  if (v === "negative") return MODIFIER_POLARITY.negative;
  return MODIFIER_POLARITY.neutral;
}

function mapEffect(ef) {
  return {
    id: str(ef?.id) ?? `ef-${Math.random().toString(36).slice(2)}`,
    name: str(ef?.effect_name) ?? str(ef?.name) ?? "Unknown effect",
    polarity: normalizePolarity(ef?.polarity),
    durationTurns: ef?.remaining_turns != null ? num(ef.remaining_turns) : null,
    description: str(ef?.description) ?? "",
  };
}

// ─── Entity ─────────────────────────────────────────────────────────────────

export function mapEntity(bundle) {
  const char    = bundle?.character ?? {};
  const state   = bundle?.state ?? {};
  const combat  = bundle?.combat ?? {};

  // Action economy flags: prefer combat section (combat's flags are turn-specific),
  // fall back to state section.
  const flags = combat?.combat_flags ?? state?.combat_flags ?? {};

  // Resources: combat section is authoritative when present.
  const shieldCur = num(combat.shield_current ?? state.shield_current, 0);
  const shieldMax = num(combat.shield_max ?? state.shield_max, 0);
  const psiCur    = num(combat.psi_current ?? state.psi_current, 0);
  const psiMax    = num(combat.psi_max ?? state.psi_max, 0);

  const zones    = mapZones(combat.body_parts ?? []);
  const effects  = Array.isArray(bundle?.effects) ? bundle.effects.map(mapEffect) : [];

  return {
    summary: {
      id:              str(char.id) ?? str(char.character_key) ?? "unknown",
      name:            str(char.display_name) ?? str(char.character_key) ?? "Unknown",
      icon:            null,
      characterType:   "player",
      ownerPlayerId:   str(char.owner_player_id),
      svgRef:          "humanoid",
    },
    zones,
    shield:     { current: shieldCur, max: shieldMax },
    armorByZone: [],
    psi:        { current: psiCur, max: psiMax },
    actions: {
      main: !bool(flags?.main_action_spent, false),
      move: !bool(flags?.move_action_spent, false),
    },
    // All DB effects shown as status chips in the Player block.
    statuses: effects,
    effects:  [],
    flags: {
      alive:     bool(state.is_alive ?? combat.is_alive, true),
      conscious: bool(state.is_conscious ?? combat.is_conscious, true),
    },
    mech:  null,
    pilot: null,
  };
}

// ─── Weapon ─────────────────────────────────────────────────────────────────
// The canonical source of truth is the get_character_armory payload (the exact
// data the existing Combat / Resolve-Attack menu renders from). The bundle's
// "armory" section is that same shape. Field readers below mirror that menu's
// access paths so the HUD shows the *same* active weapon, name, ammo, capacity
// and fire mode — never guessed field names, never mock data.

/** Flags that, if present, mark an explicit active/equipped weapon. Weapons in
 *  the current backend have NONE of these (the menu falls back to array order);
 *  honoured here only so an explicit flag wins if the backend ever adds one. */
const EQUIPPED_FLAGS = ["is_equipped", "is_active", "is_primary", "equipped", "active"];

function hasEquippedFlag(w) {
  return !!w && EQUIPPED_FLAGS.some((k) => w[k] === true);
}

/**
 * Pick the active weapon from an armory section. Returns the RAW weapon object
 * (canonical getCharacterArmory shape) or null. PURE.
 *
 * Priority: explicit equipped/active flag → first weapon in weapons[] (mirrors
 * screens/resolveAttack/resolveAttackScreen.js `weapons[0]`). A single-object
 * `armory.equipped_weapon` projection is tolerated as a fallback.
 */
export function pickActiveWeapon(armory) {
  if (!armory || typeof armory !== "object") return null;
  if (armory.equipped_weapon && typeof armory.equipped_weapon === "object") {
    return armory.equipped_weapon;
  }
  const weapons = Array.isArray(armory.weapons) ? armory.weapons.filter(Boolean) : [];
  if (weapons.length === 0) return null;
  return weapons.find(hasEquippedFlag) ?? weapons[0];
}

/** Caliber CODE used for compatibility matching (mirrors the menu's
 *  magCaliberCode: magazine_def.caliber || caliber). */
function rawMagCaliberCode(m) {
  return str(m?.magazine_def?.caliber) ?? str(m?.caliber);
}

/** Normalize a raw magazine (canonical or legacy) to the HUD magazine shape. */
function readMagazine(mag) {
  if (!mag || typeof mag !== "object") return null;
  // Capacity: canonical magazine_def.capacity / capacity; legacy max_rounds/max.
  const max = num(mag.capacity ?? mag.magazine_def?.capacity ?? mag.max_rounds ?? mag.max, 0);
  const current = num(mag.current_rounds ?? mag.current, 0);
  const ammoType =
    str(mag.ammo_type_name) ??
    str(mag.ammo_type?.name) ??
    str(mag.ammo_type_key) ??
    str(typeof mag.ammo_type === "string" ? mag.ammo_type : null) ??
    "—";
  // Display caliber prefers the human name; matching uses the same field for
  // both loaded + reserve so the selector's caliber filter stays consistent.
  const caliber =
    str(mag.magazine_def?.caliber_name) ??
    str(mag.caliber_name) ??
    str(mag.magazine_def?.caliber) ??
    str(mag.caliber) ??
    "";
  return {
    id:          str(mag.id) ?? `mag-${Math.random().toString(36).slice(2)}`,
    ammoType,
    description: str(mag.ammo_type_name) ?? str(mag.name) ?? "",
    current,
    max,
    caliber,
  };
}

/** Available fire-mode names (canonical objects on weapon/active_profile, or a
 *  legacy string array). */
function readFireModes(w) {
  const objs =
    (Array.isArray(w.available_fire_modes) && w.available_fire_modes.length
      ? w.available_fire_modes
      : Array.isArray(w.active_profile?.available_fire_modes)
        ? w.active_profile.available_fire_modes
        : []);
  if (objs.length) {
    return objs.map((m) => str(m?.name) ?? str(m?.code) ?? str(m)).filter(Boolean);
  }
  if (Array.isArray(w.fire_modes)) return w.fire_modes.map((m) => str(m)).filter(Boolean);
  return [];
}

/** Currently selected fire mode (weapon or active_profile; legacy string). */
function readCurrentFireMode(w) {
  const fm = w.selected_fire_mode ?? w.active_profile?.selected_fire_mode ?? null;
  if (fm && typeof fm === "object") return str(fm.name) ?? str(fm.code);
  return str(w.current_fire_mode);
}

/** Map weapon class → one of weaponSvg()'s known silhouettes (pistol|rifle). */
function weaponSvgRef(w) {
  const cls = String(
    w.model?.weapon_class_name ?? w.model?.weapon_class ?? w.weapon_type_key ?? w.weapon_type ?? "",
  ).toLowerCase();
  if (/pistol|handgun|sidearm|revolver/.test(cls)) return "pistol";
  return "rifle";
}

/** Reserve magazines: weapon-carried (legacy) or the character's compatible
 *  magazines from armory.magazines (caliber match, excluding the loaded one) —
 *  mirrors the menu's compatibleMagazinesForWeapon(). */
function readReserveMagazines(armory, w, loadedMag) {
  if (Array.isArray(w.reserve_magazines) && w.reserve_magazines.length) {
    return w.reserve_magazines.map(readMagazine).filter(Boolean);
  }
  const mags = Array.isArray(armory?.magazines) ? armory.magazines : [];
  if (!mags.length) return [];
  const weaponCaliber = str(w.model?.caliber) ?? str(w.caliber);
  const loadedId = loadedMag?.id ?? null;
  return mags
    .filter((m) => m && (str(m.id) ?? null) !== loadedId)
    .filter((m) => !weaponCaliber || !rawMagCaliberCode(m) || rawMagCaliberCode(m) === weaponCaliber)
    .map(readMagazine)
    .filter(Boolean);
}

/**
 * Map an armory section to the HUD weapon view model, or null when no weapon is
 * equipped. Every field degrades to a neutral local value if absent — the weapon
 * never disappears just because one field (magazine / fire mode / caliber) is
 * missing. PURE.
 */
export function mapWeapon(armory) {
  const w = pickActiveWeapon(armory);
  if (!w) return null;

  const isMelee = !str(w.model?.caliber) && !str(w.caliber);
  const rawMag = w.loaded_magazine ?? w.active_profile?.loaded_magazine ?? null;
  const loadedMag = readMagazine(rawMag);

  const fireModes = readFireModes(w);
  const currentFireMode = readCurrentFireMode(w) ?? fireModes[0] ?? null;
  const reserve = readReserveMagazines(armory, w, loadedMag);

  // A weapon "uses a magazine" / "requires ammo" when it is not melee. Explicit
  // backend flags win if present.
  const usesMagazine   = w.uses_magazine   != null ? bool(w.uses_magazine)   : !isMelee;
  const requiresAmmo   = w.requires_ammo   != null ? bool(w.requires_ammo)   : !isMelee;
  const usesConsumable = bool(w.uses_consumable, false);
  const canReload =
    w.can_reload != null ? bool(w.can_reload) : (!isMelee && reserve.length > 0);

  return {
    id:             str(w.id) ?? "wpn-unknown",
    name:           str(w.name) ?? str(w.weapon_name) ?? "Unknown Weapon",
    svgRef:         weaponSvgRef(w),
    fireModes,
    currentFireMode,
    usesMagazine,
    usesConsumable,
    requiresAmmo,
    loadedMagazine: loadedMag,
    reserveMagazines: reserve,
    ammo: {
      current: loadedMag ? loadedMag.current : num(w.ammo_current, 0),
      max:     loadedMag ? loadedMag.max     : num(w.ammo_max,     0),
    },
    reloadCandidateId: reserve[0]?.id ?? null,
    canReload,
    disabledReason: str(w.disabled_reason),
  };
}

// ─── Skills ─────────────────────────────────────────────────────────────────

function normalizeEnum(v, validSet, fallback) {
  const s = String(v ?? "");
  return validSet.has(s) ? s : fallback;
}

const VALID_SKILL_TYPES   = new Set(Object.values(SKILL_TYPES));
const VALID_SKILL_SOURCES = new Set(Object.values(SKILL_SOURCES));
const VALID_COLORS        = new Set(Object.values(COLOR_SEMANTICS));
const VALID_TARGETING     = new Set(Object.values(TARGETING_MODES));
const VALID_COSTS         = new Set(Object.values(ACTION_COSTS));

function mapSkillAction(qa) {
  const rawCost = String(qa?.action_cost ?? "MAIN").toUpperCase();
  return {
    id:          str(qa?.id) ?? `sk-${Math.random().toString(36).slice(2)}`,
    name:        str(qa?.ability_name) ?? str(qa?.name) ?? "Unknown",
    type:        normalizeEnum(qa?.ability_type ?? qa?.type, VALID_SKILL_TYPES, SKILL_TYPES.instantAbility),
    source:      normalizeEnum(qa?.source_type ?? qa?.source, VALID_SKILL_SOURCES, SKILL_SOURCES.perk),
    icon:        str(qa?.icon_key) ?? str(qa?.icon) ?? "bolt",
    color:       normalizeEnum(qa?.color_key ?? qa?.color, VALID_COLORS, COLOR_SEMANTICS.neutral),
    actionCost:  normalizeEnum(rawCost, VALID_COSTS, ACTION_COSTS.main),
    resourceCost: null,
    cooldownTurns: num(qa?.cooldown_remaining_turns ?? qa?.cooldown_remaining, 0),
    weaponRequirements: Array.isArray(qa?.weapon_requirements) ? qa.weapon_requirements.map(String) : [],
    targeting:   normalizeEnum(qa?.targeting_mode ?? qa?.targeting, VALID_TARGETING, TARGETING_MODES.none),
    allowsMultipleTargets: bool(qa?.allows_multiple_targets, false),
    usesPoint:   bool(qa?.uses_point, false),
    radius:      qa?.radius != null ? num(qa.radius) : null,
    isToggled:   bool(qa?.is_toggled, false),
    disabledReason: str(qa?.disabled_reason),
    tooltip:     str(qa?.tooltip) ?? "",
  };
}

export function mapSkills(abilitiesSection) {
  if (!abilitiesSection || typeof abilitiesSection !== "object") {
    return { library: [], quickSlots: [] };
  }

  const rawActions = Array.isArray(abilitiesSection.quick_actions) ? abilitiesSection.quick_actions : [];
  const rawSlots   = Array.isArray(abilitiesSection.quickbar_slots ?? abilitiesSection.quickbar)
    ? (abilitiesSection.quickbar_slots ?? abilitiesSection.quickbar)
    : [];

  const library = rawActions.map(mapSkillAction);
  const idSet   = new Set(library.map((sk) => sk.id));

  const quickSlots = rawSlots
    .map((s) => {
      const sid = str(s?.ability_id ?? s?.skill_id);
      return {
        index:   num(s?.slot_index ?? s?.index, 0),
        skillId: (sid && idSet.has(sid)) ? sid : null,
      };
    })
    .sort((a, b) => a.index - b.index);

  return { library, quickSlots };
}

// ─── Modifiers ───────────────────────────────────────────────────────────────
// The runtime bundle currently has no dedicated "modifiers" section (it is not
// listed in the characterPlacementApi.js sections). If the backend adds
// bundle.modifiers in the future, wire it here. For now: empty groups → neutral
// "no active modifiers" display in the Combat Control block.
export function mapModifiers(_bundle) {
  return { passive: [], active: [], narrative: [] };
}

// ─── Combat session ──────────────────────────────────────────────────────────
// A full session requires combat_get_active_runtime (a separate RPC call not
// performed in Phase 3A). The inactive session ensures the Action button is
// always enabled (no "not your turn" block) when outside an active encounter.
function mapCombatSession() {
  return createInactiveCombatSession();
}

// ─── Dev-only diagnostics ─────────────────────────────────────────────────────
// Compact, SAFE summary of the weapon data path. Off by default; never logs the
// full bundle and never throws. Enable with localStorage["odyssey.debug"]="1"
// or a ?odysseyDebug=1 / ?debugHud=1 query param. Silent under Node (no DOM).

function isMapperDebugEnabled() {
  try {
    if (globalThis.localStorage?.getItem("odyssey.debug") === "1") return true;
  } catch (_e) { /* no storage access */ }
  try {
    return /[?&](odysseyDebug|debugHud)=1(?:&|$)/i.test(String(globalThis.location?.search ?? ""));
  } catch (_e) { return false; }
}

function logWeaponDiagnostics(bundle, weaponVM) {
  if (!isMapperDebugEnabled()) return;
  try {
    const armory = bundle?.armory ?? null;
    const raw = pickActiveWeapon(armory);
    const detectedActiveWeaponPath = !armory
      ? "no armory section"
      : armory.equipped_weapon
        ? "armory.equipped_weapon"
        : Array.isArray(armory.weapons) && armory.weapons.length
          ? (armory.weapons.some(hasEquippedFlag) ? "armory.weapons[explicit-flag]" : "armory.weapons[0]")
          : "armory.weapons empty";
    // eslint-disable-next-line no-console
    console.info("[combatHud/mapper] weapon diagnostics", {
      runtimeArmoryKeys: armory && typeof armory === "object" ? Object.keys(armory) : null,
      weaponsCount: Array.isArray(armory?.weapons) ? armory.weapons.length : null,
      detectedActiveWeaponPath,
      rawWeaponKeys: raw && typeof raw === "object" ? Object.keys(raw) : null,
      mappedWeapon: weaponVM
        ? {
            name: weaponVM.name,
            svgRef: weaponVM.svgRef,
            currentFireMode: weaponVM.currentFireMode,
            ammo: weaponVM.ammo,
            hasMagazine: !!weaponVM.loadedMagazine,
            reserve: weaponVM.reserveMagazines.length,
          }
        : null,
    });
  } catch (_e) { /* diagnostics must never throw */ }
}

// ─── Public ─────────────────────────────────────────────────────────────────

/**
 * Map a raw `get_character_runtime_bundle` result to a CombatHudSnapshot.
 * Missing or malformed sections produce safe empty/null values rather than errors.
 *
 * @param {object} bundle  Raw Supabase RPC response object.
 * @returns {import("../models/combatHudContracts.js").CombatHudSnapshot}
 */
export function mapBundleToHudSnapshot(bundle) {
  const empty = {
    entity:       null,
    weapon:       { primary: null, secondary: null },
    skills:       { library: [], quickSlots: [] },
    combatSession: createInactiveCombatSession(),
    modifiers:    { passive: [], active: [], narrative: [] },
    battleLog:    { entries: [] },
  };

  if (!bundle || typeof bundle !== "object") return empty;

  let entity = null;
  try { entity = mapEntity(bundle); } catch (_e) { entity = null; }

  let weaponPrimary = null;
  try { weaponPrimary = bundle.armory ? mapWeapon(bundle.armory) : null; } catch (_e) { weaponPrimary = null; }

  let skills = { library: [], quickSlots: [] };
  try { skills = mapSkills(bundle.abilities); } catch (_e) { skills = { library: [], quickSlots: [] }; }

  let modifiers = { passive: [], active: [], narrative: [] };
  try { modifiers = mapModifiers(bundle); } catch (_e) { modifiers = { passive: [], active: [], narrative: [] }; }

  logWeaponDiagnostics(bundle, weaponPrimary);

  return {
    entity,
    weapon:       { primary: weaponPrimary, secondary: null },
    skills,
    combatSession: mapCombatSession(),
    modifiers,
    battleLog:    { entries: [] },
  };
}
