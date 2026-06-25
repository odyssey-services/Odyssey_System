import { createCombatHudAdapter } from "./combatHudAdapter.js";
import {
  ACTION_COSTS,
  COLOR_SEMANTICS,
  LOG_ENTRY_KINDS,
  MODIFIER_KINDS,
  MODIFIER_POLARITY,
  SKILL_SOURCES,
  SKILL_TYPES,
  TARGETING_MODES,
  TOKEN_KINDS,
  VIEWER_ROLES,
  ZONE_STATES,
  createInactiveCombatSession,
} from "../models/combatHudContracts.js";
import {
  hasUsableSettings,
  resolveEffectiveSettings,
} from "../../screens/resolveAttack/resolveAttackSettings.js";
import { getRealtimeClient } from "../../bridge/realtimeClient.js";

const BODY_PART_LABELS = Object.freeze({
  head: "Head",
  torso: "Torso",
  l_arm: "L.Arm",
  r_arm: "R.Arm",
  l_leg: "L.Leg",
  r_leg: "R.Leg",
});

const BODY_PART_ALIASES = Object.freeze({
  arm_l: "l_arm",
  arm_r: "r_arm",
  leg_l: "l_leg",
  leg_r: "r_leg",
  left_arm: "l_arm",
  right_arm: "r_arm",
  left_leg: "l_leg",
  right_leg: "r_leg",
  larm: "l_arm",
  rarm: "r_arm",
  lleg: "l_leg",
  rleg: "r_leg",
});

const CHARACTER_TABLES = [
  "odyssey_character_body_parts",
  "odyssey_character_effects",
  "odyssey_character_resource_pools",
  "odyssey_character_abilities",
  "odyssey_character_equipment_items",
  "odyssey_character_weapons",
  "odyssey_character_magazines",
  "odyssey_character_perks",
  "odyssey_character_skills",
  "odyssey_character_quickbar_slots",
  "odyssey_character_combat_state",
];

const COMBAT_TABLES = [
  { table: "odyssey_combat_encounters", filter: "id" },
  { table: "odyssey_initiative_entries", filter: "encounter_id" },
  { table: "odyssey_combat_log", filter: "encounter_id" },
];

function arr(value) {
  return Array.isArray(value) ? value : [];
}

function safeInt(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function signed(value) {
  const number = safeInt(value, 0);
  return `${number >= 0 ? "+" : ""}${number}`;
}

function normalizeViewerRole(role) {
  return String(role || "").trim().toUpperCase() === "GM"
    ? VIEWER_ROLES.gm
    : VIEWER_ROLES.player;
}

function normalizeTokenKind(bucket) {
  const normalized = String(bucket || "").trim().toLowerCase();
  if (normalized === "player") return TOKEN_KINDS.player;
  if (normalized === "npc_template" || normalized === "npc_active") return TOKEN_KINDS.npc;
  return TOKEN_KINDS.other;
}

function normalizeBodyPartCode(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[\s.-]+/g, "_")
    .replace(/__+/g, "_");
  return BODY_PART_ALIASES[normalized] || normalized;
}

function normalizeActionCost(value) {
  const normalized = String(value || "").trim().toUpperCase();
  if (normalized === ACTION_COSTS.free) return ACTION_COSTS.free;
  if (normalized === ACTION_COSTS.move) return ACTION_COSTS.move;
  if (normalized === ACTION_COSTS.turn) return ACTION_COSTS.turn;
  return ACTION_COSTS.main;
}

function normalizeTargeting(value, maxDistance) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized === "point") return TARGETING_MODES.point;
  if (normalized === "multiple" || normalized === "multiple_tokens") return TARGETING_MODES.multipleTokens;
  if (normalized === "token" || safeInt(maxDistance, 0) > 0) return TARGETING_MODES.token;
  return TARGETING_MODES.none;
}

function mapSkillSource(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized.includes("psionic")) return SKILL_SOURCES.psionic;
  if (normalized.includes("implant") || normalized.includes("prosthetic")) return SKILL_SOURCES.implant;
  if (normalized.includes("technical") || normalized.includes("item")) return SKILL_SOURCES.item;
  return SKILL_SOURCES.perk;
}

function deriveZoneState(part) {
  if (!part) return ZONE_STATES.healthy;
  if (part.destroyed || part.disabled) return ZONE_STATES.disabled;
  if (safeInt(part.critical, 0) > 0) return ZONE_STATES.critical;
  if (safeInt(part.serious, 0) > 0) return ZONE_STATES.serious;
  if (safeInt(part.minor, 0) > 0) return ZONE_STATES.wounded;
  return ZONE_STATES.healthy;
}

function dedupeBodyParts(parts) {
  const seen = new Map();
  for (const part of arr(parts)) {
    const code = normalizeBodyPartCode(part?.code || part?.part_key || part?.name || "");
    if (!code || code === "shield" || code === "special") continue;
    if (!seen.has(code)) {
      seen.set(code, part);
      continue;
    }
    const current = seen.get(code);
    if (current?.can_be_targeted === false && part?.can_be_targeted !== false) {
      seen.set(code, part);
    }
  }
  return Array.from(seen.entries()).map(([code, part]) => ({ code, part }));
}

function mapResourcePool(pools) {
  const match = arr(pools).find((pool) => {
    const code = String(pool?.code || pool?.name || "").trim().toLowerCase();
    return code.includes("psi") || code.includes("psionic") || code.includes("energy");
  });
  return {
    current: safeInt(match?.current_amount ?? match?.current ?? 0, 0),
    max: safeInt(match?.max_amount ?? match?.max ?? 0, 0),
  };
}

function mapShield(parts) {
  const shield = arr(parts).find((part) => normalizeBodyPartCode(part?.code || part?.part_key) === "shield");
  if (!shield) return { current: 0, max: 0 };
  const max = safeInt(shield?.armor_max_critical ?? shield?.max_critical, 0);
  const spent = safeInt(shield?.armor_critical ?? shield?.critical, 0);
  return {
    current: Math.max(max - spent, 0),
    max,
  };
}

function mapStatuses(effectSummary) {
  const effects = arr(effectSummary?.active_effects);
  const mapped = effects.map((effect, index) => ({
    id: String(effect?.id || effect?.effect_key || effect?.code || `effect-${index}`),
    name: String(effect?.name || effect?.code || "Effect"),
    polarity: effect?.is_negative ? MODIFIER_POLARITY.negative : MODIFIER_POLARITY.positive,
    durationTurns: effect?.rounds_left == null ? null : safeInt(effect.rounds_left, null),
    description: String(effect?.description || effect?.source || effect?.category || "").trim(),
  }));
  return {
    statuses: mapped.filter((entry) => entry.polarity === MODIFIER_POLARITY.negative),
    effects: mapped.filter((entry) => entry.polarity !== MODIFIER_POLARITY.negative),
  };
}

function mapModifiers(effectSummary) {
  return arr(effectSummary?.modifier_rows).map((row, index) => {
    const value = safeInt(row?.value, 0);
    const target = String(row?.target || "modifier").replaceAll("_", " ");
    return {
      id: `${row?.target || "modifier"}:${row?.attribute || row?.skill_code || index}`,
      name: target.replace(/\b\w/g, (letter) => letter.toUpperCase()),
      value,
      source: arr(row?.effect_codes).join(", ") || arr(row?.effect_keys).join(", ") || "effect",
      polarity:
        value > 0 ? MODIFIER_POLARITY.positive : value < 0 ? MODIFIER_POLARITY.negative : MODIFIER_POLARITY.neutral,
      selected: false,
      alwaysActive: true,
      requiresGMApproval: false,
      consumesOnAction: false,
      kind: arr(row?.effect_keys).some((key) => String(key).startsWith("equipment:"))
        ? MODIFIER_KINDS.passive
        : MODIFIER_KINDS.active,
      description: `${target.replace(/\b\w/g, (letter) => letter.toUpperCase())} ${signed(value)}`,
    };
  });
}

function mapZones(parts) {
  return dedupeBodyParts(parts).map(({ code, part }) => ({
    id: code,
    label: BODY_PART_LABELS[code] || String(part?.name || code),
    state: deriveZoneState(part),
    canBeTargeted: part?.can_be_targeted !== false,
  }));
}

function mapArmorByZone(parts) {
  return dedupeBodyParts(parts).map(({ code, part }) => ({
    zoneId: code,
    type: "armor",
    protection: safeInt(part?.armor_value, 0),
    durability: Math.max(safeInt(part?.armor_max_critical, 0) - safeInt(part?.armor_critical, 0), 0),
    maxDurability: safeInt(part?.armor_max_critical, 0),
  }));
}

function mapAbilityType(ability) {
  if (String(ability?.attack_type || "").trim()) return SKILL_TYPES.attackTechnique;
  if (String(ability?.activation_type || "").trim().toLowerCase() === "toggle") return SKILL_TYPES.toggleAbility;
  if (safeInt(ability?.max_distance_m ?? ability?.max_distance, 0) > 0) return SKILL_TYPES.targetedAbility;
  return SKILL_TYPES.instantAbility;
}

function mapAbility(ability) {
  const maxDistance = safeInt(ability?.max_distance_m ?? ability?.max_distance, 0);
  const resourceCost = safeInt(ability?.resource_cost ?? ability?.base_resource_cost, 0);
  return {
    id: `ability:${ability.id}`,
    name: String(ability?.name || ability?.code || "Ability"),
    type: mapAbilityType(ability),
    source: mapSkillSource(ability?.source_type),
    icon: String(ability?.name || ability?.code || "A").slice(0, 1).toUpperCase(),
    color:
      mapSkillSource(ability?.source_type) === SKILL_SOURCES.psionic
        ? COLOR_SEMANTICS.psionic
        : mapSkillSource(ability?.source_type) === SKILL_SOURCES.implant
          ? COLOR_SEMANTICS.implant
          : String(ability?.attack_type || "").trim()
            ? COLOR_SEMANTICS.attack
            : COLOR_SEMANTICS.neutral,
    actionCost: normalizeActionCost(ability?.action_cost),
    resourceCost: resourceCost > 0 ? { type: "resource", amount: resourceCost } : null,
    cooldownTurns: safeInt(ability?.cooldown_turns ?? ability?.base_cooldown_turns, 0),
    weaponRequirements: [],
    targeting: normalizeTargeting(ability?.targeting_mode || ability?.attack_type, maxDistance),
    allowsMultipleTargets: false,
    usesPoint: false,
    radius: safeInt(ability?.radius_m, 0) || null,
    isToggled: false,
    disabledReason: ability?.is_enabled === false ? "Disabled" : null,
    tooltip: String(ability?.description || ability?.name || ability?.code || "").trim(),
  };
}

function mapPerk(perk) {
  const passive = String(perk?.activation_type || perk?.perk_type || "").trim().toLowerCase() === "passive";
  return {
    id: `perk:${perk.id}`,
    name: String(perk?.name || perk?.code || "Perk"),
    type: passive ? SKILL_TYPES.toggleAbility : SKILL_TYPES.instantAbility,
    source: SKILL_SOURCES.perk,
    icon: String(perk?.name || perk?.code || "P").slice(0, 1).toUpperCase(),
    color: COLOR_SEMANTICS.neutral,
    actionCost: ACTION_COSTS.main,
    resourceCost: null,
    cooldownTurns: 0,
    weaponRequirements: [],
    targeting: TARGETING_MODES.none,
    allowsMultipleTargets: false,
    usesPoint: false,
    radius: null,
    isToggled: passive,
    disabledReason: passive ? "Passive" : null,
    tooltip: String(perk?.description || perk?.name || perk?.code || "").trim(),
  };
}

function createFallbackQuickbarSkill(slot) {
  const label = String(slot?.action_code || slot?.action_type || `Slot ${safeInt(slot?.slot_index, 0) + 1}`);
  return {
    id: `quickbar:${slot?.action_type || "item"}:${slot?.action_id || slot?.action_code || slot?.slot_index}`,
    name: label,
    type: SKILL_TYPES.instantAbility,
    source: SKILL_SOURCES.item,
    icon: label.slice(0, 1).toUpperCase(),
    color: COLOR_SEMANTICS.neutral,
    actionCost: ACTION_COSTS.main,
    resourceCost: null,
    cooldownTurns: 0,
    weaponRequirements: [],
    targeting: TARGETING_MODES.none,
    allowsMultipleTargets: false,
    usesPoint: false,
    radius: null,
    isToggled: false,
    disabledReason: "Preview only",
    tooltip: label,
  };
}

function mapSkills(bundle, quickbar) {
  const library = [];
  const registry = new Map();

  for (const ability of arr(bundle?.sections?.abilities?.abilities)) {
    const mapped = mapAbility(ability);
    library.push(mapped);
    registry.set(mapped.id, mapped);
  }

  for (const perk of arr(bundle?.sections?.perks)) {
    const mapped = mapPerk(perk);
    library.push(mapped);
    registry.set(mapped.id, mapped);
  }

  const quickSlots = arr(quickbar?.slots)
    .sort((left, right) => safeInt(left?.slot_index, 0) - safeInt(right?.slot_index, 0))
    .map((slot) => {
      let skillId = null;
      if (slot?.action_type === "ability" && slot?.action_id) {
        skillId = `ability:${slot.action_id}`;
      } else if (slot?.action_type === "perk" && slot?.action_id) {
        skillId = `perk:${slot.action_id}`;
      } else {
        const fallback = createFallbackQuickbarSkill(slot);
        skillId = fallback.id;
        if (!registry.has(skillId)) {
          library.push(fallback);
          registry.set(skillId, fallback);
        }
      }
      return {
        index: safeInt(slot?.slot_index, 0),
        skillId,
      };
    });

  return { library, quickSlots };
}

function mapMagazine(magazine) {
  if (!magazine) return null;
  return {
    id: String(magazine?.id || ""),
    ammoType: String(magazine?.ammo_type_name || magazine?.ammo_type?.name || magazine?.ammo_type?.code || "Ammo"),
    description: String(magazine?.name || magazine?.magazine_def?.name || magazine?.display_name || ""),
    current: safeInt(magazine?.current_rounds ?? magazine?.current, 0),
    max: safeInt(magazine?.capacity ?? magazine?.magazine_def?.capacity ?? magazine?.max, 0),
    caliber: String(
      magazine?.caliber_code ||
      magazine?.magazine_def?.caliber_code ||
      magazine?.caliber?.code ||
      "",
    ),
  };
}

function resolveWeaponCaliber(weapon, loadedMagazine) {
  return String(
    weapon?.active_profile?.caliber_code ||
    weapon?.model?.caliber_code ||
    loadedMagazine?.caliber ||
    "",
  ).trim();
}

function mapWeaponEntry(weapon, magazines) {
  const loadedMagazine = mapMagazine(weapon?.loaded_magazine || weapon?.active_profile?.loaded_magazine);
  const caliber = resolveWeaponCaliber(weapon, loadedMagazine);
  const reserveMagazines = arr(magazines)
    .map((magazine) => mapMagazine(magazine))
    .filter((magazine) => {
      if (!magazine?.id) return false;
      if (loadedMagazine?.id && magazine.id === loadedMagazine.id) return false;
      if (magazine.current <= 0) return false;
      if (caliber && magazine.caliber && magazine.caliber !== caliber) return false;
      return true;
    });
  return {
    id: String(weapon?.id || ""),
    name: String(weapon?.name || weapon?.model?.name || "Weapon"),
    svgRef: String(weapon?.model?.code || weapon?.weapon_model_code || ""),
    fireModes: arr(
      weapon?.available_fire_modes?.length
        ? weapon.available_fire_modes
        : weapon?.active_profile?.available_fire_modes,
    )
      .map((entry) => String(entry?.name || entry?.code || "").trim())
      .filter(Boolean),
    currentFireMode: String(
      weapon?.selected_fire_mode?.name ||
      weapon?.selected_fire_mode?.code ||
      weapon?.active_profile?.selected_fire_mode?.name ||
      weapon?.active_profile?.selected_fire_mode?.code ||
      "",
    ) || null,
    usesMagazine: Boolean(caliber || loadedMagazine || reserveMagazines.length),
    usesConsumable: false,
    requiresAmmo: Boolean(caliber),
    loadedMagazine,
    reserveMagazines,
    ammo: {
      current: loadedMagazine?.current ?? 0,
      max: loadedMagazine?.max ?? 0,
    },
    reloadCandidateId: reserveMagazines[0]?.id ?? null,
    canReload: reserveMagazines.length > 0,
    disabledReason: reserveMagazines.length > 0 ? null : "No compatible reserve magazines",
  };
}

function mapWeaponState(armory) {
  const weapons = arr(armory?.weapons);
  const magazines = arr(armory?.magazines);
  return {
    primary: weapons[0] ? mapWeaponEntry(weapons[0], magazines) : null,
    secondary: weapons[1] ? mapWeaponEntry(weapons[1], magazines) : null,
  };
}

function mapCombatSession(runtimeData, selectedCharacterId) {
  if (!runtimeData?.encounter) {
    return createInactiveCombatSession();
  }
  return {
    id: String(runtimeData.encounter.id || ""),
    status: String(runtimeData.encounter.status || "active"),
    round: safeInt(runtimeData.encounter.current_round, 0),
    currentParticipantId: String(runtimeData.encounter.active_character_id || "") || null,
    participants: arr(runtimeData.visible_participants).map((participant) => ({
      id: String(participant?.character_id || ""),
      name: String(participant?.display_name || participant?.character_key || "Participant"),
      tokenId: null,
      isPlayer: String(participant?.character_bucket || "") === "player",
      initiative: safeInt(participant?.initiative_value, 0),
      initiativeRoll: safeInt(participant?.roll_value, 0),
      order: safeInt(participant?.order_index, 0),
      isCurrent: Boolean(participant?.is_current_turn),
      canAct: safeInt(participant?.action_current, 0) > 0 || safeInt(participant?.move_current, 0) > 0,
      condition:
        participant?.state?.is_alive === false
          ? "dead"
          : participant?.state?.is_conscious === false
            ? "unconscious"
            : "active",
    })),
    isViewerTurn: String(runtimeData.encounter.active_character_id || "") === String(selectedCharacterId || ""),
  };
}

function mapBattleLog(runtimeData) {
  return {
    entries: arr(runtimeData?.log).map((row, index) => ({
      id: String(row?.id || `${index}`),
      sequence: index,
      kind: String(row?.event_type || "").includes("system") ? LOG_ENTRY_KINDS.system : LOG_ENTRY_KINDS.action,
      actor: String(row?.actor_character_id || ""),
      action: String(row?.event_type || "action"),
      target: String(row?.target_character_id || ""),
      delta: "",
      summary: String(row?.message || row?.event_type || "Combat event"),
      detail:
        row?.public_data && typeof row.public_data === "object"
          ? JSON.stringify(row.public_data)
          : "",
    })),
  };
}

function mapEntityRuntime(bundle, link, effectSummary, runtimeData) {
  const character = bundle?.character ?? {};
  const combat = bundle?.sections?.combat ?? {};
  const participant = bundle?.sections?.combat_session?.participant ?? {};
  const effectLists = mapStatuses(effectSummary);
  const bodyParts = arr(combat?.body_parts);
  return {
    summary: {
      id: String(character?.id || link?.character_id || ""),
      name: String(
        character?.display_name ||
        character?.name ||
        character?.resources?.name ||
        link?.character_name ||
        "Character",
      ),
      icon: "",
      characterType: normalizeTokenKind(character?.character_bucket || link?.character_bucket),
      ownerPlayerId: String(character?.owner_player_id || ""),
      svgRef: "humanoid",
    },
    zones: mapZones(bodyParts),
    shield: mapShield(bodyParts),
    armorByZone: mapArmorByZone(bodyParts),
    psi: mapResourcePool(bundle?.sections?.abilities?.resource_pools),
    actions: {
      main: safeInt(participant?.action_current, 0) > 0 || !runtimeData?.encounter,
      move: safeInt(participant?.move_current, 0) > 0 || !runtimeData?.encounter,
    },
    statuses: effectLists.statuses,
    effects: effectLists.effects,
    flags: {
      alive: combat?.is_alive !== false,
      conscious: combat?.is_conscious !== false,
    },
    mech: null,
    pilot: null,
  };
}

function buildSceneTokens(sceneItems, linksByTokenId) {
  return arr(sceneItems).map((item) => {
    const tokenId = String(item?.id || "").trim();
    const link = linksByTokenId.get(tokenId) ?? null;
    return {
      tokenId,
      name: String(item?.text?.plainText || item?.name || link?.token_name || link?.character_name || "Token"),
      characterId: String(link?.character_id || "") || null,
      kind: normalizeTokenKind(link?.character_bucket),
      position: item?.position && typeof item.position === "object"
        ? { x: safeInt(item.position.x, 0), y: safeInt(item.position.y, 0) }
        : undefined,
    };
  });
}

export function createSupabaseCombatHudAdapter({ runtime } = {}) {
  if (!runtime?.bridges || !runtime?.api) {
    throw new Error("createSupabaseCombatHudAdapter: runtime is required.");
  }

  const listeners = new Set();
  const cache = {
    settings: { url: "", apiKey: "" },
    viewer: { playerId: "", playerName: "", role: VIEWER_ROLES.player },
    selectedTokenId: null,
    sceneTokens: [],
    linksByTokenId: new Map(),
    runtimeByCharacterId: new Map(),
    weaponByCharacterId: new Map(),
    skillsByCharacterId: new Map(),
    modifiersByCharacterId: new Map(),
    combatSession: createInactiveCombatSession(),
    battleLog: { entries: [] },
  };

  let disposed = false;
  let selectedTokenOverride;
  let roleOverride;
  let refreshPromise = null;
  let queuedRefresh = false;
  let unsubscribePlayer = null;
  let unsubscribeSceneItems = null;
  let realtimeChannels = [];
  let realtimeKey = "";

  function emit() {
    if (disposed) return;
    for (const listener of Array.from(listeners)) {
      try {
        listener();
      } catch (error) {
        console.error("[combatHud/supabase] listener failed", error);
      }
    }
  }

  function clearRealtime() {
    const client = getRealtimeClient(cache.settings);
    if (client) {
      for (const channel of realtimeChannels) {
        client.removeChannel(channel);
      }
    }
    realtimeChannels = [];
    realtimeKey = "";
  }

  function bindRealtime(settings, characterId, encounterId) {
    if (!hasUsableSettings(settings)) {
      clearRealtime();
      return;
    }

    const key = `${characterId || ""}|${encounterId || ""}`;
    if (key === realtimeKey) return;

    clearRealtime();
    realtimeKey = key;

    const client = getRealtimeClient(settings);
    if (!client) return;

    if (characterId) {
      for (const table of CHARACTER_TABLES) {
        const channel = client
          .channel(`hud:${table}:${characterId}`)
          .on(
            "postgres_changes",
            { event: "*", schema: "public", table, filter: `character_id=eq.${characterId}` },
            () => {
              void refresh();
            },
          )
          .subscribe();
        realtimeChannels.push(channel);
      }
    }

    if (encounterId) {
      for (const entry of COMBAT_TABLES) {
        const channel = client
          .channel(`hud:${entry.table}:${encounterId}`)
          .on(
            "postgres_changes",
            {
              event: "*",
              schema: "public",
              table: entry.table,
              filter: `${entry.filter}=eq.${encounterId}`,
            },
            () => {
              void refresh();
            },
          )
          .subscribe();
        realtimeChannels.push(channel);
      }
    }
  }

  async function ensureSubscriptions() {
    if (!unsubscribePlayer) {
      unsubscribePlayer = await runtime.bridges.obr.subscribePlayerChanges(() => {
        void refresh();
      }).catch(() => null);
    }
    if (!unsubscribeSceneItems) {
      unsubscribeSceneItems = await runtime.bridges.obr.subscribeSceneItems(() => {
        void refresh();
      }).catch(() => null);
    }
  }

  async function refresh() {
    if (disposed) return;
    if (refreshPromise) {
      queuedRefresh = true;
      return refreshPromise;
    }

    refreshPromise = (async () => {
      const resolved = await resolveEffectiveSettings().catch(() => ({ settings: { url: "", apiKey: "" } }));
      cache.settings = resolved.settings;

      const player = await runtime.bridges.obr.getPlayerInfo().catch(() => ({
        id: "",
        name: "",
        role: "PLAYER",
        selection: [],
      }));
      cache.viewer = {
        playerId: String(player?.id || ""),
        playerName: String(player?.name || ""),
        role: roleOverride ?? normalizeViewerRole(player?.role),
      };

      const context = await runtime.bridges.obr.getRoomSceneContext().catch(() => ({
        campaignId: "",
        roomId: "",
        sceneId: "",
      }));
      const sceneItems = await runtime.bridges.obr.getSceneItems().catch(() => []);
      const fallbackSelection = arr(player?.selection).map((value) => String(value || "").trim()).filter(Boolean)[0] ?? null;
      cache.selectedTokenId = selectedTokenOverride !== undefined ? selectedTokenOverride : fallbackSelection;

      let links = [];
      if (hasUsableSettings(cache.settings) && context.roomId && context.sceneId) {
        const tokenLinks = await runtime.api.placement.getSceneTokenLinks({
          campaign_id: context.campaignId,
          room_id: context.roomId,
          scene_id: context.sceneId,
        }, cache.settings).catch(() => null);
        links = arr(tokenLinks?.links);
      }

      cache.linksByTokenId = new Map(links.map((link) => [String(link?.token_id || "").trim(), link]));
      cache.sceneTokens = buildSceneTokens(sceneItems, cache.linksByTokenId);

      let runtimeData = null;
      if (hasUsableSettings(cache.settings) && context.roomId && context.sceneId) {
        runtimeData = await runtime.api.combat.getActiveRuntime({
          campaign_id: context.campaignId,
          room_id: context.roomId,
          scene_id: context.sceneId,
          actor_player_id: cache.viewer.playerId,
          actor_is_gm: cache.viewer.role === VIEWER_ROLES.gm,
          log_limit: 8,
        }, cache.settings).catch(() => null);
      }

      const selectedLink = cache.selectedTokenId
        ? cache.linksByTokenId.get(String(cache.selectedTokenId).trim()) ?? null
        : null;
      const selectedCharacterId = String(selectedLink?.character_id || "").trim() || null;

      cache.combatSession = mapCombatSession(runtimeData, selectedCharacterId);
      cache.battleLog = mapBattleLog(runtimeData);

      if (!selectedCharacterId || !hasUsableSettings(cache.settings)) {
        bindRealtime(cache.settings, null, runtimeData?.encounter?.id ?? null);
        emit();
        return;
      }

      const bundle = await runtime.api.placement.getCharacterRuntimeBundle({
        character_id: selectedCharacterId,
        sections: ["summary", "combat", "skills", "abilities", "effects", "perks", "combat_session"],
        campaign_id: context.campaignId,
        room_id: context.roomId,
        scene_id: context.sceneId,
        actor_player_id: cache.viewer.playerId,
        actor_is_gm: cache.viewer.role === VIEWER_ROLES.gm,
      }, cache.settings).catch(() => null);

      const quickbar = await runtime.api.placement.getCharacterQuickbar({
        character_id: selectedCharacterId,
        actor_player_id: cache.viewer.playerId,
        actor_is_gm: cache.viewer.role === VIEWER_ROLES.gm,
      }, cache.settings).catch(() => null);

      const armory = await runtime.api.weapon.getCharacterArmory(selectedCharacterId, cache.settings).catch(() => null);
      const effectSummary = await runtime.api.effects.getCharacterEffectSummary(selectedCharacterId, cache.settings).catch(() => null);

      cache.runtimeByCharacterId.set(selectedCharacterId, mapEntityRuntime(bundle, selectedLink, effectSummary, runtimeData));
      cache.weaponByCharacterId.set(selectedCharacterId, mapWeaponState(armory));
      cache.skillsByCharacterId.set(selectedCharacterId, mapSkills(bundle, quickbar));
      cache.modifiersByCharacterId.set(selectedCharacterId, mapModifiers(effectSummary));

      bindRealtime(cache.settings, selectedCharacterId, runtimeData?.encounter?.id ?? null);
      emit();
    })().finally(() => {
      refreshPromise = null;
      if (queuedRefresh) {
        queuedRefresh = false;
        void refresh();
      }
    });

    return refreshPromise;
  }

  return createCombatHudAdapter({
    getViewer() {
      return cache.viewer;
    },
    getSelectedTokenId() {
      return cache.selectedTokenId ?? null;
    },
    getSceneTokens() {
      return cache.sceneTokens;
    },
    getCharacterForToken(tokenId) {
      if (!tokenId) return null;
      const token = cache.sceneTokens.find((entry) => entry.tokenId === tokenId) ?? null;
      const link = cache.linksByTokenId.get(String(tokenId).trim()) ?? null;
      if (!token || !link) return null;
      return {
        characterId: String(link.character_id || ""),
        token,
      };
    },
    getCharacterRuntime(characterId) {
      return cache.runtimeByCharacterId.get(String(characterId || "").trim()) ?? null;
    },
    getWeaponState(characterId) {
      return cache.weaponByCharacterId.get(String(characterId || "").trim()) ?? null;
    },
    getAvailableSkills(characterId) {
      return cache.skillsByCharacterId.get(String(characterId || "").trim()) ?? { library: [], quickSlots: [] };
    },
    getModifiers(characterId) {
      return cache.modifiersByCharacterId.get(String(characterId || "").trim()) ?? [];
    },
    getCombatSession() {
      return cache.combatSession;
    },
    getBattleLog() {
      return cache.battleLog;
    },
    selectToken(tokenId) {
      selectedTokenOverride = tokenId ?? null;
      void refresh();
    },
    setViewerRole(role) {
      roleOverride = normalizeViewerRole(role);
      void refresh();
    },
    setMockScenario() {
      return null;
    },
    subscribe(listener) {
      if (typeof listener !== "function") return () => {};
      listeners.add(listener);
      void ensureSubscriptions();
      void refresh();
      return () => {
        listeners.delete(listener);
      };
    },
    async refresh() {
      await refresh();
    },
    dispose() {
      disposed = true;
      clearRealtime();
      if (typeof unsubscribePlayer === "function") unsubscribePlayer();
      if (typeof unsubscribeSceneItems === "function") unsubscribeSceneItems();
      listeners.clear();
    },
  }, "supabase");
}
