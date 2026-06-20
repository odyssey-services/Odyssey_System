import { hasSupabaseSettings } from "../bridge/settingsBridge.js";
import { toErrorMessage } from "../utils/errors.js";
import { escapeHtml, prettyJson, safeJsonParse } from "../utils/json.js";

const CREATOR_TABS = Object.freeze([
  { id: "skills", label: "Skills" },
  { id: "equipment", label: "Equipment Models" },
]);

const RELOAD_MODES = Object.freeze([
  { value: "", label: "No reload item" },
  { value: "reset", label: "Reset" },
  { value: "per_charge", label: "Per Charge" },
]);

const MODIFIER_TARGET_OPTIONS = Object.freeze([
  { value: "attack_accuracy", label: "Attack Accuracy" },
  { value: "defense", label: "Defense" },
  { value: "damage", label: "Damage" },
  { value: "armor", label: "Armor" },
  { value: "action_count", label: "Action Count" },
  { value: "concentration_slots", label: "Concentration Slots" },
  { value: "movement_m", label: "Movement (m)" },
  { value: "aim_difficulty", label: "Aim Difficulty" },
  { value: "range", label: "Range" },
  { value: "attribute", label: "Attribute" },
  { value: "skill", label: "Skill" },
  { value: "custom", label: "Custom Target" },
]);

function createEmptySkillDraft() {
  return {
    id: "",
    name: "",
    category: "combat",
    maxLevel: "5",
    mainAttributeId: "",
    secondaryAttributeId: "",
    description: "",
  };
}

function createEmptyAbilityLinkDraft() {
  return {
    abilityDefId: "",
    grantMode: "activated",
    durationRoundsMode: "none",
    durationRounds: "",
    chargesMode: "none",
    charges: "",
    cooldownRoundsMode: "none",
    cooldownRounds: "",
    reloadMode: "",
    reloadItemCode: "",
  };
}

function createEmptyEquipmentDraft() {
  return {
    id: "",
    name: "",
    itemType: "armor",
    description: "",
    armorValue: "0",
    armorMaxCritical: "0",
    defaultBodyPartCode: "",
    allowedBodyPartCodes: [],
    protectsHelplessExecution: false,
    reservedForFuture: false,
    notes: "",
    modifiers: [],
    flagsExtraData: {},
    effectDataExtraData: {},
    abilityLinks: [],
  };
}

function createEmptyModifierDraft() {
  return {
    target: "attack_accuracy",
    customTarget: "",
    attributeCode: "",
    skillCode: "",
    value: "0",
  };
}

function createInitialState() {
  return {
    activeTab: "skills",
    loading: false,
    loadingLabel: "",
    error: "",
    info: "",
    lastLoadedSettingsKey: "",
    references: null,
    loadedTabs: {
      skills: false,
      equipment: false,
    },
    filters: {
      skills: {
        search: "",
        category: "",
      },
      equipment: {
        search: "",
        itemType: "",
      },
    },
    lists: {
      skills: [],
      equipment: [],
    },
    selectedIds: {
      skills: "",
      equipment: "",
    },
    bundles: {
      skills: null,
      equipment: null,
    },
    drafts: {
      skills: createEmptySkillDraft(),
      equipment: createEmptyEquipmentDraft(),
    },
    dirty: {
      skills: false,
      equipment: false,
    },
    collapsed: {
      skillsCatalog: true,
      equipmentCatalog: true,
      skillsPayload: true,
      equipmentPayload: true,
      equipmentDataModifiers: true,
    },
    requestNonce: 0,
  };
}

function cloneJson(value) {
  return safeJsonParse(JSON.stringify(value), value);
}

function coerceInteger(value, fallback = 0) {
  const parsed = Number.parseInt(String(value ?? "").trim(), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseJsonField(text, label, expectedType) {
  const parsed = safeJsonParse(String(text ?? "").trim(), undefined);
  if (parsed === undefined) {
    throw new Error(`${label} must contain valid JSON.`);
  }
  if (expectedType === "array" && !Array.isArray(parsed)) {
    throw new Error(`${label} must be a JSON array.`);
  }
  if (
    expectedType === "object"
    && (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
  ) {
    throw new Error(`${label} must be a JSON object.`);
  }
  return parsed;
}

function formatCreatorError(result, fallback) {
  if (!result || result.ok !== false) {
    return fallback;
  }
  const details = Array.isArray(result.details)
    ? result.details
        .map((entry) => String(entry?.message ?? entry?.field ?? "").trim())
        .filter(Boolean)
    : [];
  const message = String(result.message ?? result.error ?? fallback).trim() || fallback;
  return details.length ? `${message} ${details.join(" | ")}` : message;
}

function slugifyName(value) {
  return String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .replace(/_{2,}/g, "_");
}

function uniqueGeneratedCode(baseCode, existingCodes) {
  const safeBase = baseCode || "entity";
  const used = new Set((existingCodes ?? []).map((value) => String(value ?? "").trim()).filter(Boolean));
  if (!used.has(safeBase)) {
    return safeBase;
  }
  let index = 2;
  while (used.has(`${safeBase}_${index}`)) {
    index += 1;
  }
  return `${safeBase}_${index}`;
}

function nextFreeSortOrder(items) {
  const used = new Set(
    (items ?? [])
      .map((item) => Number.parseInt(String(item?.sort_order ?? item?.sortOrder ?? ""), 10))
      .filter((value) => Number.isFinite(value) && value >= 0),
  );
  let value = 0;
  while (used.has(value)) {
    value += 1;
  }
  return value;
}

function buildSkillAutoTags(draft, references) {
  const tags = new Set();
  if (draft.category) tags.add(String(draft.category).trim());
  const attributes = Array.isArray(references?.attributes) ? references.attributes : [];
  const main = attributes.find((entry) => entry.id === draft.mainAttributeId);
  const secondary = attributes.find((entry) => entry.id === draft.secondaryAttributeId);
  if (main?.code) tags.add(String(main.code));
  if (secondary?.code) tags.add(String(secondary.code));
  return Array.from(tags);
}

function buildEquipmentAutoTags(draft) {
  const tags = new Set();
  const allowedCodes = getEffectiveAllowedBodyPartCodes(draft);
  const primaryBodyPartCode = getPrimaryBodyPartCode(allowedCodes, draft.defaultBodyPartCode);
  if (draft.itemType) tags.add(String(draft.itemType).trim());
  if (primaryBodyPartCode) tags.add(primaryBodyPartCode);
  tags.add("equipable");
  if (shouldEquipToBodyPart(draft.itemType, allowedCodes, draft.defaultBodyPartCode)) tags.add("body_part");
  return Array.from(tags);
}

function toPlainObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function normalizeBodyPartCodeArray(value) {
  return Array.isArray(value)
    ? Array.from(new Set(value.map((entry) => String(entry ?? "").trim()).filter(Boolean)))
    : [];
}

function suggestAllowedBodyPartCodes(defaultBodyPartCode) {
  const code = String(defaultBodyPartCode ?? "").trim().toLowerCase();
  switch (code) {
    case "head":
    case "torso":
    case "special":
      return code ? [code] : [];
    case "l_arm":
    case "r_arm":
      return ["l_arm", "r_arm", "extra_l_arm", "extra_r_arm"];
    case "l_leg":
    case "r_leg":
      return ["l_leg", "r_leg"];
    default:
      return code ? [code] : [];
  }
}

function getPrimaryBodyPartCode(allowedBodyPartCodes, fallbackCode = "") {
  const normalized = normalizeBodyPartCodeArray(allowedBodyPartCodes);
  const fallback = String(fallbackCode ?? "").trim().toLowerCase();
  if (fallback && normalized.includes(fallback)) {
    return fallback;
  }
  const preferredOrder = ["head", "torso", "l_arm", "r_arm", "l_leg", "r_leg", "special", "extra_l_arm", "extra_r_arm"];
  for (const code of preferredOrder) {
    if (normalized.includes(code)) {
      return code;
    }
  }
  return normalized[0] ?? "";
}

function getEffectiveAllowedBodyPartCodes(draft) {
  const selectedCodes = normalizeBodyPartCodeArray(draft?.allowedBodyPartCodes);
  return selectedCodes.length
    ? selectedCodes
    : suggestAllowedBodyPartCodes(draft?.defaultBodyPartCode);
}

function shouldShowProtectionSlots(itemType) {
  const type = String(itemType ?? "").trim();
  return type !== "exoskeleton" && type !== "closed_suit";
}

function shouldEquipToBodyPart(itemType, allowedBodyPartCodes = [], defaultBodyPartCode = "") {
  const type = String(itemType ?? "").trim();
  if (type === "armor" || type === "shield") {
    return true;
  }
  if (type === "implant" || type === "prosthetic") {
    return normalizeBodyPartCodeArray(allowedBodyPartCodes).length > 0 || Boolean(String(defaultBodyPartCode ?? "").trim());
  }
  return false;
}

function getEquipmentUiTypes(references) {
  return (Array.isArray(references?.equipment_item_types) ? references.equipment_item_types : [])
    .filter((itemType) => String(itemType ?? "") !== "device");
}

function normalizeSkillDraft(bundle) {
  const skill = bundle?.skill ?? {};
  return {
    id: String(skill.id ?? ""),
    name: String(skill.name ?? ""),
    category: String(skill.category ?? "combat"),
    maxLevel: String(skill.max_level ?? 5),
    mainAttributeId: String(skill.main_attribute_id ?? ""),
    secondaryAttributeId: String(skill.secondary_attribute_id ?? ""),
    description: String(skill.description ?? ""),
  };
}

function normalizeAbilityLinkDraft(entry) {
  const data = entry?.data && typeof entry.data === "object" && !Array.isArray(entry.data)
    ? entry.data
    : {};
  const reload = data?.reload && typeof data.reload === "object" && !Array.isArray(data.reload)
    ? data.reload
    : {};
  const charges = data.default_max_charges ?? data.default_current_charges ?? data.max_charges ?? data.current_charges ?? "";
  const durationValue = data.duration_rounds;
  const cooldownValue = data.cooldown_rounds ?? data.default_cooldown_rounds;
  return {
    abilityDefId: String(entry?.ability_def_id ?? ""),
    grantMode: String(entry?.grant_mode ?? "activated"),
    durationRoundsMode: durationValue === null || durationValue === undefined || durationValue === "" ? "none" : "set",
    durationRounds: String(durationValue ?? ""),
    chargesMode: charges === null || charges === undefined || charges === "" ? "none" : "set",
    charges: charges === null || charges === undefined ? "" : String(charges),
    cooldownRoundsMode: cooldownValue === null || cooldownValue === undefined || cooldownValue === "" ? "none" : "set",
    cooldownRounds: String(cooldownValue ?? ""),
    reloadMode: String(reload.mode ?? data.reload_mode ?? ""),
    reloadItemCode: String(reload.item_code ?? data.reload_item_code ?? data.requires_reload_item_code ?? ""),
  };
}

function normalizeEquipmentDraft(bundle) {
  const model = bundle?.equipment_model ?? {};
  const flags = toPlainObject(model.flags);
  const effectData = toPlainObject(model.effect_data);
  const {
    allowed_body_part_codes: allowedBodyPartCodesRaw,
    protects_helpless_execution: protectsHelplessExecutionRaw,
    ...flagsExtraData
  } = flags;
  const {
    reserved_for_future: reservedForFutureRaw,
    notes: notesRaw,
    modifiers: modifiersRaw,
    ...effectDataExtraData
  } = effectData;
  const normalizedAllowedBodyPartCodes = normalizeBodyPartCodeArray(allowedBodyPartCodesRaw);
  return {
    id: String(model.id ?? ""),
    name: String(model.name ?? ""),
    itemType: String(model.item_type ?? "armor"),
    description: String(model.description ?? ""),
    armorValue: String(model.armor_value ?? 0),
    armorMaxCritical: String(model.armor_max_critical ?? 0),
    defaultBodyPartCode: String(model.default_body_part_code ?? ""),
    allowedBodyPartCodes: normalizedAllowedBodyPartCodes.length
      ? normalizedAllowedBodyPartCodes
      : suggestAllowedBodyPartCodes(model.default_body_part_code),
    protectsHelplessExecution: Boolean(protectsHelplessExecutionRaw),
    reservedForFuture: Boolean(reservedForFutureRaw),
    notes: String(notesRaw ?? ""),
    modifiers: Array.isArray(modifiersRaw)
      ? modifiersRaw.map(normalizeModifierDraft)
      : [],
    flagsExtraData,
    effectDataExtraData,
    abilityLinks: Array.isArray(bundle?.ability_links)
      ? bundle.ability_links.map(normalizeAbilityLinkDraft)
      : [],
  };
}

function normalizeModifierDraft(entry) {
  const rawTarget = String(entry?.target ?? "").trim();
  const knownTarget = MODIFIER_TARGET_OPTIONS.some((option) => option.value === rawTarget && option.value !== "custom")
    ? rawTarget
    : "custom";
  return {
    target: knownTarget,
    customTarget: knownTarget === "custom" ? rawTarget : "",
    attributeCode: String(entry?.attribute ?? ""),
    skillCode: String(entry?.skill_code ?? ""),
    value: String(entry?.value ?? 0),
  };
}

function makeSkillDuplicateDraft(source) {
  const name = String(source.name ?? "").trim();
  return {
    ...cloneJson(source),
    id: "",
    name: name ? `${name} Copy` : "",
  };
}

function makeEquipmentDuplicateDraft(source) {
  const name = String(source.name ?? "").trim();
  return {
    ...cloneJson(source),
    id: "",
    name: name ? `${name} Copy` : "",
    flagsExtraData: cloneJson(source.flagsExtraData ?? {}),
    effectDataExtraData: cloneJson(source.effectDataExtraData ?? {}),
    modifiers: Array.isArray(source.modifiers)
      ? source.modifiers.map((entry) => ({
          ...cloneJson(entry),
        }))
      : [],
    abilityLinks: Array.isArray(source.abilityLinks)
      ? source.abilityLinks.map((entry) => ({
          ...cloneJson(entry),
        }))
      : [],
  };
}

function generatedSkillPreview(draft, references, state) {
  const list = Array.isArray(state?.lists?.skills) ? state.lists.skills : [];
  const existingCodes = list.map((item) => item?.code);
  const code = uniqueGeneratedCode(slugifyName(draft.name), existingCodes);
  const tags = buildSkillAutoTags(draft, references);
  const sortOrder = draft.id
    ? Number.parseInt(String(state?.bundles?.skills?.skill?.sort_order ?? 0), 10) || 0
    : nextFreeSortOrder(list);
  return { code, tags, sortOrder };
}

function generatedEquipmentPreview(draft, state) {
  const list = Array.isArray(state?.lists?.equipment) ? state.lists.equipment : [];
  const existingCodes = list.map((item) => item?.code);
  const code = uniqueGeneratedCode(slugifyName(draft.name), existingCodes);
  const tags = buildEquipmentAutoTags(draft);
  const sortOrder = draft.id
    ? Number.parseInt(String(state?.bundles?.equipment?.equipment_model?.sort_order ?? 0), 10) || 0
    : nextFreeSortOrder(list);
  return { code, tags, sortOrder };
}

function buildAbilityLinkPayload(link, index) {
  const grantMode = String(link.grantMode ?? "activated").trim() || "activated";
  const isPassive = grantMode === "passive";
  const durationMode = String(link.durationRoundsMode ?? "").trim() || "none";
  const chargesMode = String(link.chargesMode ?? "").trim() || "none";
  const cooldownMode = String(link.cooldownRoundsMode ?? "").trim() || "none";
  const charges = String(link.charges ?? "").trim();
  const cooldown = String(link.cooldownRounds ?? "").trim();
  const duration = String(link.durationRounds ?? "").trim();
  const reloadMode = String(link.reloadMode ?? "").trim();
  const reloadItemCode = String(link.reloadItemCode ?? "").trim();
  const data = {};
  if (durationMode === "set" && duration !== "") {
    data.duration_rounds = coerceInteger(duration, 0);
  }
  if (chargesMode === "set" && charges !== "") {
    const value = coerceInteger(charges, 0);
    data.default_current_charges = value;
    data.default_max_charges = value;
  }
  if (cooldownMode === "set" && cooldown !== "") {
    data.cooldown_rounds = coerceInteger(cooldown, 0);
  }
  if (reloadMode) {
    data.reload = { mode: reloadMode };
    if (reloadItemCode) {
      data.reload.item_code = reloadItemCode;
    }
  }
  return {
    ability_def_id: String(link.abilityDefId ?? "").trim(),
    grant_mode: grantMode,
    is_enabled: isPassive,
    sort_order: index,
    data,
  };
}

function buildSkillPayload(draft, auto) {
  return {
    id: draft.id || undefined,
    code: String(auto.code ?? "").trim(),
    name: String(draft.name ?? "").trim(),
    category: String(draft.category ?? "combat").trim() || "combat",
    max_level: coerceInteger(draft.maxLevel, 5),
    main_attribute_id: String(draft.mainAttributeId ?? "").trim() || null,
    secondary_attribute_id: String(draft.secondaryAttributeId ?? "").trim() || null,
    sort_order: auto.sortOrder,
    description: String(draft.description ?? ""),
    tags: auto.tags,
  };
}

function buildEquipmentPayload(draft, auto) {
  const showProtectionSlots = shouldShowProtectionSlots(draft.itemType);
  const selectedAllowedCodes = normalizeBodyPartCodeArray(draft.allowedBodyPartCodes);
  const suggestedAllowedCodes = suggestAllowedBodyPartCodes(draft.defaultBodyPartCode);
  const effectiveAllowedCodes = selectedAllowedCodes.length ? selectedAllowedCodes : suggestedAllowedCodes;
  const canEquipToBodyPart = shouldEquipToBodyPart(draft.itemType, effectiveAllowedCodes, draft.defaultBodyPartCode);
  const primaryBodyPartCode = showProtectionSlots ? getPrimaryBodyPartCode(effectiveAllowedCodes, draft.defaultBodyPartCode) : "";
  const flags = toPlainObject(cloneJson(draft.flagsExtraData));
  const effectData = toPlainObject(cloneJson(draft.effectDataExtraData));
  const finalAllowedCodes = canEquipToBodyPart
    ? effectiveAllowedCodes
    : [];
  if (canEquipToBodyPart && finalAllowedCodes.length) {
    flags.allowed_body_part_codes = finalAllowedCodes;
  } else {
    delete flags.allowed_body_part_codes;
  }
  if (draft.protectsHelplessExecution) {
    flags.protects_helpless_execution = true;
  } else {
    delete flags.protects_helpless_execution;
  }
  if (draft.reservedForFuture) {
    effectData.reserved_for_future = true;
  } else {
    delete effectData.reserved_for_future;
  }
  if (String(draft.notes ?? "").trim()) {
    effectData.notes = String(draft.notes ?? "").trim();
  } else {
    delete effectData.notes;
  }
  const modifiers = (Array.isArray(draft.modifiers) ? draft.modifiers : [])
    .map(buildModifierPayload)
    .filter(Boolean);
  if (modifiers.length) {
    effectData.modifiers = modifiers;
  } else {
    delete effectData.modifiers;
  }
  return {
    id: draft.id || undefined,
    code: String(auto.code ?? "").trim(),
    name: String(draft.name ?? "").trim(),
    item_type: String(draft.itemType ?? "armor").trim() || "armor",
    description: String(draft.description ?? ""),
    armor_value: coerceInteger(draft.armorValue, 0),
    armor_max_minor: 0,
    armor_max_serious: 0,
    armor_max_critical: coerceInteger(draft.armorMaxCritical, 0),
    default_body_part_code: primaryBodyPartCode || null,
    can_equip: true,
    can_equip_to_body_part: canEquipToBodyPart,
    sort_order: auto.sortOrder,
    tags: auto.tags,
    flags,
    effect_data: effectData,
    ability_links: (Array.isArray(draft.abilityLinks) ? draft.abilityLinks : [])
      .filter((entry) => String(entry?.abilityDefId ?? "").trim())
      .map((entry, index) => buildAbilityLinkPayload(entry, index)),
  };
}

function buildModifierPayload(entry) {
  const target = String(entry?.target ?? "").trim() || "attack_accuracy";
  const resolvedTarget = target === "custom"
    ? String(entry?.customTarget ?? "").trim()
    : target;
  if (!resolvedTarget) {
    return null;
  }
  const payload = {
    target: resolvedTarget,
    value: coerceInteger(entry?.value, 0),
  };
  if (resolvedTarget === "attribute") {
    const attributeCode = String(entry?.attributeCode ?? "").trim();
    if (!attributeCode) {
      return null;
    }
    payload.attribute = attributeCode;
  }
  if (resolvedTarget === "skill") {
    const skillCode = String(entry?.skillCode ?? "").trim();
    if (!skillCode) {
      return null;
    }
    payload.skill_code = skillCode;
  }
  return payload;
}

function extractEntityBundle(result) {
  if (result?.entity?.ok) {
    return result.entity;
  }
  if (result?.ok) {
    return result;
  }
  return null;
}

function buildTabButtons(activeTab) {
  return CREATOR_TABS
    .map(
      (tab) => `
        <button
          type="button"
          class="creator-tab${activeTab === tab.id ? " active" : ""}"
          data-creator-tab="${tab.id}"
        >${escapeHtml(tab.label)}</button>
      `,
    )
    .join("");
}

function buildSkillFilterMarkup(state, references) {
  const selected = state.filters.skills.category;
  const categories = Array.isArray(references?.skill_categories) ? references.skill_categories : [];
  const options = [
    '<option value="">All categories</option>',
    ...categories.map(
      (category) => `<option value="${escapeHtml(category)}"${selected === category ? " selected" : ""}>${escapeHtml(category)}</option>`,
    ),
  ];
  return `
    <div class="creator-toolbar">
      <label class="field-stack">
        <span>Search</span>
        <input data-creator-filter-search="skills" type="text" value="${escapeHtml(state.filters.skills.search)}" placeholder="code, name, tags">
      </label>
      <label class="field-stack">
        <span>Category</span>
        <select data-creator-filter-category="skills">
          ${options.join("")}
        </select>
      </label>
      <div class="creator-filter-actions">
        <button type="button" class="secondary" data-creator-action="applyFilters">Apply Filters</button>
        <button type="button" class="secondary" data-creator-action="refreshList">Refresh</button>
      </div>
    </div>
  `;
}

function buildEquipmentFilterMarkup(state, references) {
  const selected = state.filters.equipment.itemType;
  const types = getEquipmentUiTypes(references);
  const options = [
    '<option value="">All item types</option>',
    ...types.map(
      (itemType) => `<option value="${escapeHtml(itemType)}"${selected === itemType ? " selected" : ""}>${escapeHtml(itemType)}</option>`,
    ),
  ];
  return `
    <div class="creator-toolbar">
      <label class="field-stack">
        <span>Search</span>
        <input data-creator-filter-search="equipment" type="text" value="${escapeHtml(state.filters.equipment.search)}" placeholder="code, name, tags">
      </label>
      <label class="field-stack">
        <span>Item Type</span>
        <select data-creator-filter-item-type="equipment">
          ${options.join("")}
        </select>
      </label>
      <div class="creator-filter-actions">
        <button type="button" class="secondary" data-creator-action="applyFilters">Apply Filters</button>
        <button type="button" class="secondary" data-creator-action="refreshList">Refresh</button>
      </div>
    </div>
  `;
}

function buildListMarkup(kind, items, selectedId) {
  if (!items.length) {
    return `<div class="creator-empty">No ${kind === "skills" ? "skills" : "equipment models"} found for the current filter.</div>`;
  }
  return items
    .map((item) => {
      const isActive = selectedId && selectedId === item.id;
      const meta = kind === "skills"
        ? [
            item.category || "unknown",
            item.main_attribute_name || item.main_attribute_code || "no main attribute",
            item.secondary_attribute_name || item.secondary_attribute_code || "no secondary attribute",
          ]
        : [
            item.item_type || "unknown",
            item.default_body_part_code || "no body part",
            `armor ${item.armor_value ?? 0}`,
          ];
      return `
        <button
          type="button"
          class="creator-list-item${isActive ? " active" : ""}"
          data-creator-open="${escapeHtml(kind)}:${escapeHtml(item.id)}"
        >
          <span class="creator-list-title">${escapeHtml(item.name || item.code || "Unnamed")}</span>
          <span class="creator-list-code">${escapeHtml(item.code || "")}</span>
          <span class="creator-list-meta">${escapeHtml(meta.join(" | "))}</span>
        </button>
      `;
    })
    .join("");
}

function buildAttributeOptions(references, selectedValue) {
  const attributes = Array.isArray(references?.attributes) ? references.attributes : [];
  const options = ['<option value="">None</option>'];
  for (const attribute of attributes) {
    options.push(
      `<option value="${escapeHtml(attribute.id)}"${selectedValue === attribute.id ? " selected" : ""}>${escapeHtml(attribute.name || attribute.code || attribute.id)}</option>`,
    );
  }
  return options.join("");
}

function buildBodyPartCheckboxMarkup(references, selectedCodes) {
  const selectedSet = new Set(normalizeBodyPartCodeArray(selectedCodes));
  const bodyParts = Array.isArray(references?.body_part_definitions) ? references.body_part_definitions : [];
  if (!bodyParts.length) {
    return `<div class="creator-empty">No body part definitions found.</div>`;
  }
  return bodyParts
    .map((part) => `
      <label class="creator-check-pill">
        <input data-creator-body-part-code="${escapeHtml(part.code)}" type="checkbox"${selectedSet.has(part.code) ? " checked" : ""}>
        <span>${escapeHtml(part.name || part.code)}</span>
      </label>
    `)
    .join("");
}

function buildAbilityOptions(references, selectedValue, selectedIds = []) {
  const abilities = Array.isArray(references?.abilities) ? references.abilities : [];
  const selectedSet = new Set((selectedIds ?? []).filter(Boolean));
  const options = ['<option value="">Select ability</option>'];
  for (const ability of abilities) {
    const disabled = selectedSet.has(ability.id) && selectedValue !== ability.id;
    options.push(
      `<option value="${escapeHtml(ability.id)}"${selectedValue === ability.id ? " selected" : ""}${disabled ? " disabled" : ""}>${escapeHtml(ability.name || ability.code)}${ability.ability_kind ? ` | ${escapeHtml(ability.ability_kind)}` : ""}</option>`,
    );
  }
  return options.join("");
}

function buildItemOptions(references, selectedValue) {
  const items = Array.isArray(references?.itemDefinitions) ? references.itemDefinitions : [];
  const options = ['<option value="">No reload item</option>'];
  for (const item of items) {
    options.push(
      `<option value="${escapeHtml(item.code)}"${selectedValue === item.code ? " selected" : ""}>${escapeHtml(item.name || item.code)}${item.item_type ? ` | ${escapeHtml(item.item_type)}` : ""}</option>`,
    );
  }
  return options.join("");
}

function buildModifierTargetOptions(selectedValue) {
  return MODIFIER_TARGET_OPTIONS
    .map((option) => `<option value="${escapeHtml(option.value)}"${selectedValue === option.value ? " selected" : ""}>${escapeHtml(option.label)}</option>`)
    .join("");
}

function buildSkillCodeOptions(references, selectedValue) {
  const skills = Array.isArray(references?.skills) ? references.skills : [];
  const options = ['<option value="">Select skill</option>'];
  for (const skill of skills) {
    options.push(
      `<option value="${escapeHtml(skill.code)}"${selectedValue === skill.code ? " selected" : ""}>${escapeHtml(skill.name || skill.code)}${skill.category ? ` | ${escapeHtml(skill.category)}` : ""}</option>`,
    );
  }
  return options.join("");
}

function buildCatalogSection({
  title,
  count,
  collapsed,
  action,
  bodyMarkup,
}) {
  return `
    <aside class="creator-sidebar">
      <button type="button" class="creator-collapse-toggle" data-creator-action="${escapeHtml(action)}" aria-expanded="${collapsed ? "false" : "true"}">
        <span>${escapeHtml(title)}</span>
        <span class="creator-inline-compact">
          <span class="creator-count">${escapeHtml(String(count))}</span>
          <span class="creator-collapse-icon">${collapsed ? "+" : "-"}</span>
        </span>
      </button>
      ${collapsed ? "" : `<div class="creator-list">${bodyMarkup}</div>`}
    </aside>
  `;
}

function buildDisclosureSection({
  title,
  collapsed,
  action,
  summary = "",
  actionsMarkup = "",
  bodyMarkup = "",
}) {
  return `
    <div class="creator-section-card">
      <div class="creator-section-head">
        <button type="button" class="creator-section-toggle" data-creator-action="${escapeHtml(action)}" aria-expanded="${collapsed ? "false" : "true"}">
          <span>${escapeHtml(title)}</span>
          ${summary ? `<span class="muted">${escapeHtml(summary)}</span>` : ""}
          <span class="creator-collapse-icon">${collapsed ? "+" : "-"}</span>
        </button>
        ${actionsMarkup}
      </div>
      ${collapsed ? "" : bodyMarkup}
    </div>
  `;
}

function buildOptionalNumberField({
  label,
  field,
  index,
  value,
  mode,
}) {
  const selectedMode = String(mode ?? "").trim() || "none";
  return `
    <div class="creator-small-stack">
      <span>${escapeHtml(label)}</span>
      <div class="creator-mini-grid">
        <select data-creator-link-input="${field}Mode" data-link-index="${index}">
          <option value="none"${selectedMode === "none" ? " selected" : ""}>None</option>
          <option value="set"${selectedMode === "set" ? " selected" : ""}>Set</option>
        </select>
        <input data-creator-link-input="${field}" data-link-index="${index}" type="number" min="0" value="${escapeHtml(value)}"${selectedMode === "set" ? "" : " disabled"}>
      </div>
    </div>
  `;
}

function buildModifierEditorMarkup(draft, references) {
  const modifiers = Array.isArray(draft.modifiers) ? draft.modifiers : [];
  if (!modifiers.length) {
    return `<div class="creator-empty">No modifiers yet. Add one if this model should grant a passive or active numeric effect.</div>`;
  }
  return modifiers
    .map((modifier, index) => {
      const resolvedTarget = String(modifier.target ?? "attack_accuracy");
      return `
        <div class="creator-link-card" data-creator-modifier-row="${index}">
          <div class="creator-link-head">
            <strong>Modifier ${index + 1}</strong>
            <button type="button" class="secondary" data-creator-modifier-remove="${index}">Remove</button>
          </div>
          <div class="field-grid creator-grid-3">
            <label class="field-stack">
              <span>Target</span>
              <select data-creator-modifier-input="target" data-modifier-index="${index}">
                ${buildModifierTargetOptions(resolvedTarget)}
              </select>
            </label>
            ${resolvedTarget === "attribute" ? `
              <label class="field-stack">
                <span>Attribute</span>
                <select data-creator-modifier-input="attributeCode" data-modifier-index="${index}">
                  ${buildAttributeOptions(references, modifier.attributeCode)}
                </select>
              </label>
            ` : resolvedTarget === "skill" ? `
              <label class="field-stack">
                <span>Skill</span>
                <select data-creator-modifier-input="skillCode" data-modifier-index="${index}">
                  ${buildSkillCodeOptions(references, modifier.skillCode)}
                </select>
              </label>
            ` : resolvedTarget === "custom" ? `
              <label class="field-stack">
                <span>Custom Target</span>
                <input data-creator-modifier-input="customTarget" data-modifier-index="${index}" type="text" value="${escapeHtml(modifier.customTarget)}" placeholder="custom_target">
              </label>
            ` : `
              <div class="creator-auto-meta creator-small-meta">
                <div><strong>Resolved Target:</strong> ${escapeHtml(resolvedTarget)}</div>
              </div>
            `}
            <label class="field-stack">
              <span>Value</span>
              <input data-creator-modifier-input="value" data-modifier-index="${index}" type="number" value="${escapeHtml(modifier.value)}">
            </label>
          </div>
        </div>
      `;
    })
    .join("");
}

function buildSkillEditorMarkup(state, references) {
  const draft = state.drafts.skills;
  const bundle = state.bundles.skills;
  const auto = generatedSkillPreview(draft, references, state);
  const categories = Array.isArray(references?.skill_categories) ? references.skill_categories : [];
  const categoryOptions = categories
    .map((category) => `<option value="${escapeHtml(category)}"${draft.category === category ? " selected" : ""}>${escapeHtml(category)}</option>`)
    .join("");
  const levelPreview = bundle?.level_requirements?.length
    ? prettyJson(bundle.level_requirements)
    : "[]";

  return `
    <div class="creator-editor-head">
      <div>
        <div class="creator-editor-title">${escapeHtml(draft.name || "New Skill Draft")}</div>
        <div class="muted">${draft.id ? "Editing saved definition." : "Draft is local until Save."}</div>
      </div>
      <div class="creator-pill${state.dirty.skills ? " dirty" : ""}" data-creator-dirty-pill="skills">${state.dirty.skills ? "Unsaved" : "Saved / clean"}</div>
    </div>
    <div class="button-row">
      <button type="button" data-creator-action="newDraft">Create New</button>
      <button type="button" class="secondary" data-creator-action="duplicateDraft">Duplicate</button>
      <button type="button" data-creator-action="saveDraft">Save</button>
      <button type="button" class="secondary" data-creator-action="reloadSelected"${draft.id ? "" : " disabled"}>Reload</button>
      <button type="button" class="secondary" data-creator-action="deleteSelected"${draft.id ? "" : " disabled"}>Delete</button>
    </div>
    <form class="creator-form" data-creator-form="skills">
      <label class="field-stack">
        <span>Name</span>
        <input data-creator-input="name" type="text" value="${escapeHtml(draft.name)}" placeholder="Frontier Melee">
      </label>
      <div class="field-grid creator-grid-4">
        <label class="field-stack">
          <span>Category</span>
          <select data-creator-input="category">${categoryOptions}</select>
        </label>
        <label class="field-stack">
          <span>Max Level</span>
          <select data-creator-input="maxLevel">
            <option value="1"${draft.maxLevel === "1" ? " selected" : ""}>1</option>
            <option value="3"${draft.maxLevel === "3" ? " selected" : ""}>3</option>
            <option value="5"${draft.maxLevel === "5" ? " selected" : ""}>5</option>
          </select>
        </label>
        <label class="field-stack">
          <span>Main Attribute</span>
          <select data-creator-input="mainAttributeId">${buildAttributeOptions(references, draft.mainAttributeId)}</select>
        </label>
        <label class="field-stack">
          <span>Secondary Attribute</span>
          <select data-creator-input="secondaryAttributeId">${buildAttributeOptions(references, draft.secondaryAttributeId)}</select>
        </label>
      </div>
      <label class="field-stack">
        <span>Description</span>
        <textarea data-creator-input="description" rows="4" placeholder="Short GM-facing description">${escapeHtml(draft.description)}</textarea>
      </label>
      <div class="creator-auto-meta">
        <div><strong>Auto code:</strong> ${escapeHtml(auto.code || "will be generated from name")}</div>
        <div><strong>Auto sort:</strong> ${escapeHtml(String(auto.sortOrder))}</div>
        <div><strong>Auto tags:</strong> ${escapeHtml(auto.tags.join(", ") || "none")}</div>
      </div>
      <label class="field-stack">
        <span>Level Requirements Preview</span>
        <textarea rows="8" readonly>${escapeHtml(levelPreview)}</textarea>
      </label>
      <p class="muted">Skill level requirements are preview-only in this V1 UI because the current backend upsert path does not persist edits for that nested block yet.</p>
      ${buildDisclosureSection({
        title: "Payload Preview",
        collapsed: Boolean(state.collapsed.skillsPayload),
        action: "toggleSkillsPayload",
        bodyMarkup: `
          <label class="field-stack">
            <textarea rows="10" readonly>${escapeHtml(prettyJson(buildSkillPayload(draft, auto)))}</textarea>
          </label>
        `,
      })}
    </form>
  `;
}

function buildAbilityLinksEditorMarkup(draft, references) {
  const links = Array.isArray(draft.abilityLinks) ? draft.abilityLinks : [];
  const selectedIds = links.map((entry) => entry.abilityDefId).filter(Boolean);
  if (!links.length) {
    return `<div class="creator-empty">No ability links yet. Add one to connect an existing ability to this equipment model.</div>`;
  }

  return links
    .map((link, index) => {
      const passive = link.grantMode === "passive";
      const reloadMode = String(link.reloadMode ?? "");
      return `
        <div class="creator-link-card" data-creator-link-row="${index}">
          <div class="creator-link-head">
            <strong>Ability Link ${index + 1}</strong>
            <button type="button" class="secondary" data-creator-link-remove="${index}">Remove</button>
          </div>
          <div class="field-grid creator-grid-2">
            <label class="field-stack">
              <span>Ability</span>
              <select data-creator-link-input="abilityDefId" data-link-index="${index}">
                ${buildAbilityOptions(references, link.abilityDefId, selectedIds)}
              </select>
            </label>
            <label class="field-stack">
              <span>Grant Mode</span>
              <select data-creator-link-input="grantMode" data-link-index="${index}">
                <option value="activated"${link.grantMode === "activated" ? " selected" : ""}>Active</option>
                <option value="passive"${passive ? " selected" : ""}>Passive</option>
              </select>
            </label>
          </div>
          ${passive ? `
            <div class="creator-auto-meta creator-small-meta">
              <div><strong>Passive:</strong> always active while the equipment is equipped.</div>
            </div>
          ` : `
            <div class="field-grid creator-grid-2">
              ${buildOptionalNumberField({
                label: "Duration",
                field: "durationRounds",
                index,
                value: link.durationRounds,
                mode: link.durationRoundsMode,
              })}
              ${buildOptionalNumberField({
                label: "Charges",
                field: "charges",
                index,
                value: link.charges,
                mode: link.chargesMode,
              })}
              ${buildOptionalNumberField({
                label: "Cooldown",
                field: "cooldownRounds",
                index,
                value: link.cooldownRounds,
                mode: link.cooldownRoundsMode,
              })}
              <div class="creator-small-stack">
                <span>Reload</span>
                <div class="creator-mini-grid creator-mini-grid-wide">
                  <select data-creator-link-input="reloadMode" data-link-index="${index}">
                    ${RELOAD_MODES.map((mode) => `<option value="${escapeHtml(mode.value)}"${reloadMode === mode.value ? " selected" : ""}>${escapeHtml(mode.label)}</option>`).join("")}
                  </select>
                  <select data-creator-link-input="reloadItemCode" data-link-index="${index}"${reloadMode ? "" : " disabled"}>
                    ${buildItemOptions(references, link.reloadItemCode)}
                  </select>
                </div>
              </div>
            </div>
          `}
        </div>
      `;
    })
    .join("");
}

function buildEquipmentEditorMarkup(state, references) {
  const draft = state.drafts.equipment;
  const types = getEquipmentUiTypes(references);
  const showProtectionSlots = shouldShowProtectionSlots(draft.itemType);
  const allowedBodyPartCodes = getEffectiveAllowedBodyPartCodes(draft);
  const advancedFlagsCount = Object.keys(toPlainObject(draft.flagsExtraData)).length;
  const advancedEffectDataCount = Object.keys(toPlainObject(draft.effectDataExtraData)).length;
  const payloadCollapsed = Boolean(state.collapsed.equipmentPayload);
  const dataModifiersCollapsed = Boolean(state.collapsed.equipmentDataModifiers);
  const typeOptions = types
    .map((itemType) => `<option value="${escapeHtml(itemType)}"${draft.itemType === itemType ? " selected" : ""}>${escapeHtml(itemType)}</option>`)
    .join("");
  const payloadPreview = (() => {
    try {
      return prettyJson(buildEquipmentPayload(draft, auto));
    } catch (_error) {
      return prettyJson({ draft });
    }
  })();

  return `
    <div class="creator-editor-head">
      <div>
        <div class="creator-editor-title">${escapeHtml(draft.name || "New Equipment Draft")}</div>
        <div class="muted">${draft.id ? "Editing saved definition." : "Draft is local until Save."}</div>
      </div>
      <div class="creator-pill${state.dirty.equipment ? " dirty" : ""}" data-creator-dirty-pill="equipment">${state.dirty.equipment ? "Unsaved" : "Saved / clean"}</div>
    </div>
    <div class="button-row">
      <button type="button" data-creator-action="newDraft">Create New</button>
      <button type="button" class="secondary" data-creator-action="duplicateDraft">Duplicate</button>
      <button type="button" data-creator-action="saveDraft">Save</button>
      <button type="button" class="secondary" data-creator-action="reloadSelected"${draft.id ? "" : " disabled"}>Reload</button>
      <button type="button" class="secondary" data-creator-action="deleteSelected"${draft.id ? "" : " disabled"}>Delete</button>
    </div>
    <form class="creator-form" data-creator-form="equipment">
      <label class="field-stack">
        <span>Name</span>
        <input data-creator-input="name" type="text" value="${escapeHtml(draft.name)}" placeholder="Frontier Plate">
      </label>
      <div class="field-grid creator-grid-3">
        <label class="field-stack">
          <span>Item Type</span>
          <select data-creator-input="itemType">${typeOptions}</select>
        </label>
        <label class="field-stack">
          <span>Armor Value</span>
          <input data-creator-input="armorValue" type="number" value="${escapeHtml(draft.armorValue)}">
        </label>
        <label class="field-stack">
          <span>Armor Max Critical</span>
          <input data-creator-input="armorMaxCritical" type="number" value="${escapeHtml(draft.armorMaxCritical)}">
        </label>
      </div>
      <label class="field-stack">
        <span>Description</span>
        <textarea data-creator-input="description" rows="4" placeholder="Short GM-facing description">${escapeHtml(draft.description)}</textarea>
      </label>
      ${showProtectionSlots ? `
      <div class="creator-section-card">
        <div class="creator-section-head">
          <strong>Protection Slots</strong>
          <span class="muted">Structured creator fields instead of raw JSON.</span>
        </div>
        <div class="field-grid creator-grid-2">
          <label class="toggle-inline creator-toggle-card">
            <input data-creator-input="protectsHelplessExecution" type="checkbox"${draft.protectsHelplessExecution ? " checked" : ""}>
            <span>Protects helpless execution</span>
          </label>
        </div>
        <div class="field-stack">
          <span>Allowed Body Parts</span>
          <div class="creator-check-grid">
            ${buildBodyPartCheckboxMarkup(references, allowedBodyPartCodes)}
          </div>
        </div>
        ${(advancedFlagsCount || advancedEffectDataCount) ? `
          <div class="creator-auto-meta creator-small-meta">
            ${advancedFlagsCount ? `<div><strong>Preserved extra flags:</strong> ${escapeHtml(String(advancedFlagsCount))}</div>` : ""}
            ${advancedEffectDataCount ? `<div><strong>Preserved extra data keys:</strong> ${escapeHtml(String(advancedEffectDataCount))}</div>` : ""}
          </div>
        ` : ""}
      </div>
      ` : ""}
      ${buildDisclosureSection({
        title: "Data & Modifiers",
        collapsed: dataModifiersCollapsed,
        action: "toggleEquipmentDataModifiers",
        summary: draft.modifiers?.length
          ? `${draft.modifiers.length} modifier(s)`
          : (draft.notes || draft.reservedForFuture ? "configured" : ""),
        actionsMarkup: `<button type="button" data-creator-action="addModifier">Add Modifier</button>`,
        bodyMarkup: `
          <div class="field-grid creator-grid-2">
            <label class="toggle-inline creator-toggle-card">
              <input data-creator-input="reservedForFuture" type="checkbox"${draft.reservedForFuture ? " checked" : ""}>
              <span>Reserved for future logic</span>
            </label>
          </div>
          <label class="field-stack">
            <span>Notes</span>
            <textarea data-creator-input="notes" rows="4" placeholder="Optional backend note for GM / future implementation">${escapeHtml(draft.notes)}</textarea>
          </label>
          <div class="creator-links-block">
            ${buildModifierEditorMarkup(draft, references)}
          </div>
        `,
      })}
      <div class="creator-links-block">
        <div class="creator-links-head">
          <span>Ability Links</span>
          <button type="button" data-creator-action="addAbilityLink">Add Ability Link</button>
        </div>
        ${buildAbilityLinksEditorMarkup(draft, references)}
      </div>
      ${buildDisclosureSection({
        title: "Payload Preview",
        collapsed: payloadCollapsed,
        action: "toggleEquipmentPayload",
        bodyMarkup: `
          <label class="field-stack">
            <textarea rows="12" readonly>${escapeHtml(payloadPreview)}</textarea>
          </label>
        `,
      })}
    </form>
  `;
}

function buildPanelMarkup(state, access) {
  if (!access.isGm) {
    return `
      <section class="panel">
        <div class="panel-title">Creator Menu</div>
        <p class="muted">Creator tools are GM-only. Players should not edit catalog definitions from this surface.</p>
      </section>
    `;
  }

  if (!access.configured) {
    return `
      <section class="panel">
        <div class="panel-title">Creator Menu</div>
        <p class="muted">Configure Supabase room settings above, then the creator tabs for Skills and Equipment Models will unlock here.</p>
      </section>
    `;
  }

  const references = state.references ?? {};
  const listMarkup = state.activeTab === "skills"
    ? buildListMarkup("skills", state.lists.skills, state.selectedIds.skills)
    : buildListMarkup("equipment", state.lists.equipment, state.selectedIds.equipment);
  const filtersMarkup = state.activeTab === "skills"
    ? buildSkillFilterMarkup(state, references)
    : buildEquipmentFilterMarkup(state, references);
  const editorMarkup = state.activeTab === "skills"
    ? buildSkillEditorMarkup(state, references)
    : buildEquipmentEditorMarkup(state, references);
  const catalogCollapsed = state.activeTab === "skills"
    ? Boolean(state.collapsed.skillsCatalog)
    : Boolean(state.collapsed.equipmentCatalog);
  const catalogMarkup = buildCatalogSection({
    title: state.activeTab === "skills" ? "Skill Catalog" : "Equipment Catalog",
    count: state.activeTab === "skills" ? state.lists.skills.length : state.lists.equipment.length,
    collapsed: catalogCollapsed,
    action: state.activeTab === "skills" ? "toggleSkillsCatalog" : "toggleEquipmentCatalog",
    bodyMarkup: listMarkup,
  });

  return `
    <section class="panel creator-panel">
      <div class="panel-title">Creator Menu</div>
      <p class="panel-note">Drafts stay local in the UI until you press Save. Code, tags, and sort order are generated automatically to keep catalog work fast for the GM.</p>
      <nav class="creator-tabs">${buildTabButtons(state.activeTab)}</nav>
      ${filtersMarkup}
      ${state.error ? `<div class="creator-banner error">${escapeHtml(state.error)}</div>` : ""}
      ${state.info ? `<div class="creator-banner info">${escapeHtml(state.info)}</div>` : ""}
      ${state.loading ? `<div class="creator-banner info">Loading: ${escapeHtml(state.loadingLabel || "working...")}</div>` : ""}
      <div class="creator-layout">
        ${catalogMarkup}
        <div class="creator-editor">
          ${editorMarkup}
        </div>
      </div>
    </section>
  `;
}

function readSkillDraftFromDom(root) {
  const form = root.querySelector('[data-creator-form="skills"]');
  if (!(form instanceof HTMLElement)) {
    return createEmptySkillDraft();
  }
  const query = (field) => form.querySelector(`[data-creator-input="${field}"]`);
  return {
    id: String(form.dataset.creatorEntityId ?? ""),
    name: String(query("name")?.value ?? ""),
    category: String(query("category")?.value ?? "combat"),
    maxLevel: String(query("maxLevel")?.value ?? "5"),
    mainAttributeId: String(query("mainAttributeId")?.value ?? ""),
    secondaryAttributeId: String(query("secondaryAttributeId")?.value ?? ""),
    description: String(query("description")?.value ?? ""),
  };
}

function readEquipmentDraftFromDom(root, fallbackDraft = createEmptyEquipmentDraft()) {
  const form = root.querySelector('[data-creator-form="equipment"]');
  if (!(form instanceof HTMLElement)) {
    return cloneJson(fallbackDraft);
  }
  const query = (field) => form.querySelector(`[data-creator-input="${field}"]`);
  const bodyPartCodes = Array.from(form.querySelectorAll("[data-creator-body-part-code]:checked"))
    .map((entry) => String(entry.getAttribute("data-creator-body-part-code") ?? "").trim())
    .filter(Boolean);
  const abilityLinks = Array.from(form.querySelectorAll("[data-creator-link-row]")).map((row) => {
    const index = String(row.getAttribute("data-creator-link-row") ?? "");
    const fallbackLink = Array.isArray(fallbackDraft.abilityLinks)
      ? fallbackDraft.abilityLinks[Number.parseInt(index, 10)] ?? createEmptyAbilityLinkDraft()
      : createEmptyAbilityLinkDraft();
    const linkQuery = (field) => form.querySelector(`[data-creator-link-input="${field}"][data-link-index="${index}"]`);
    const grantMode = String(linkQuery("grantMode")?.value ?? "activated");
    return {
      abilityDefId: String(linkQuery("abilityDefId")?.value ?? ""),
      grantMode,
      durationRoundsMode: String(linkQuery("durationRoundsMode")?.value ?? fallbackLink.durationRoundsMode ?? "none"),
      durationRounds: String(linkQuery("durationRounds")?.value ?? fallbackLink.durationRounds ?? ""),
      chargesMode: String(linkQuery("chargesMode")?.value ?? fallbackLink.chargesMode ?? "none"),
      charges: String(linkQuery("charges")?.value ?? fallbackLink.charges ?? ""),
      cooldownRoundsMode: String(linkQuery("cooldownRoundsMode")?.value ?? fallbackLink.cooldownRoundsMode ?? "none"),
      cooldownRounds: String(linkQuery("cooldownRounds")?.value ?? fallbackLink.cooldownRounds ?? ""),
      reloadMode: String(linkQuery("reloadMode")?.value ?? fallbackLink.reloadMode ?? ""),
      reloadItemCode: String(linkQuery("reloadItemCode")?.value ?? fallbackLink.reloadItemCode ?? ""),
    };
  });
  const modifierRows = Array.from(form.querySelectorAll("[data-creator-modifier-row]"));
  const modifiers = modifierRows.length
    ? modifierRows.map((row) => {
        const index = String(row.getAttribute("data-creator-modifier-row") ?? "");
        const fallbackModifier = Array.isArray(fallbackDraft.modifiers)
          ? fallbackDraft.modifiers[Number.parseInt(index, 10)] ?? createEmptyModifierDraft()
          : createEmptyModifierDraft();
        const modifierQuery = (field) => form.querySelector(`[data-creator-modifier-input="${field}"][data-modifier-index="${index}"]`);
        return {
          target: String(modifierQuery("target")?.value ?? fallbackModifier.target ?? "attack_accuracy"),
          customTarget: String(modifierQuery("customTarget")?.value ?? fallbackModifier.customTarget ?? ""),
          attributeCode: String(modifierQuery("attributeCode")?.value ?? fallbackModifier.attributeCode ?? ""),
          skillCode: String(modifierQuery("skillCode")?.value ?? fallbackModifier.skillCode ?? ""),
          value: String(modifierQuery("value")?.value ?? fallbackModifier.value ?? "0"),
        };
      })
    : cloneJson(fallbackDraft.modifiers ?? []);
  return {
    id: String(form.dataset.creatorEntityId ?? ""),
    name: String(query("name")?.value ?? ""),
    itemType: String(query("itemType")?.value ?? "armor"),
    description: String(query("description")?.value ?? ""),
    armorValue: String(query("armorValue")?.value ?? "0"),
    armorMaxCritical: String(query("armorMaxCritical")?.value ?? "0"),
    defaultBodyPartCode: getPrimaryBodyPartCode(bodyPartCodes, fallbackDraft.defaultBodyPartCode ?? ""),
    allowedBodyPartCodes: bodyPartCodes.length ? bodyPartCodes : cloneJson(fallbackDraft.allowedBodyPartCodes ?? []),
    protectsHelplessExecution: query("protectsHelplessExecution")
      ? Boolean(query("protectsHelplessExecution")?.checked)
      : Boolean(fallbackDraft.protectsHelplessExecution),
    reservedForFuture: query("reservedForFuture")
      ? Boolean(query("reservedForFuture")?.checked)
      : Boolean(fallbackDraft.reservedForFuture),
    notes: String(query("notes")?.value ?? fallbackDraft.notes ?? ""),
    modifiers,
    flagsExtraData: cloneJson(fallbackDraft.flagsExtraData ?? {}),
    effectDataExtraData: cloneJson(fallbackDraft.effectDataExtraData ?? {}),
    abilityLinks,
  };
}

function updateDirtyPill(root, kind, isDirty) {
  const pill = root.querySelector(`[data-creator-dirty-pill="${kind}"]`);
  if (!(pill instanceof HTMLElement)) {
    return;
  }
  pill.textContent = isDirty ? "Unsaved" : "Saved / clean";
  pill.classList.toggle("dirty", Boolean(isDirty));
}

export function mountCreatorMenu({
  root,
  runtime,
  getPlayer,
  getSettings,
  onDiagnostic = () => {},
}) {
  const state = createInitialState();

  function getAccess() {
    const player = getPlayer();
    const settings = getSettings();
    return {
      player,
      settings,
      isGm: player?.role === "GM",
      configured: hasSupabaseSettings(settings),
      settingsKey: hasSupabaseSettings(settings)
        ? `${settings.url}::${settings.apiKey}`
        : "",
    };
  }

  function captureActiveDraft() {
    if (state.activeTab === "skills") {
      state.drafts.skills = readSkillDraftFromDom(root);
    } else {
      state.drafts.equipment = readEquipmentDraftFromDom(root, state.drafts.equipment);
    }
  }

  function clearMessages() {
    state.error = "";
    state.info = "";
  }

  function resetLoadedData({ keepTab = true } = {}) {
    const activeTab = keepTab ? state.activeTab : "skills";
    state.references = null;
    state.loadedTabs = { skills: false, equipment: false };
    state.lists = { skills: [], equipment: [] };
    state.selectedIds = { skills: "", equipment: "" };
    state.bundles = { skills: null, equipment: null };
    state.drafts = {
      skills: createEmptySkillDraft(),
      equipment: createEmptyEquipmentDraft(),
    };
    state.dirty = { skills: false, equipment: false };
    state.activeTab = activeTab;
  }

  function render() {
    const access = getAccess();
    root.innerHTML = buildPanelMarkup(state, access);

    const form = root.querySelector(`[data-creator-form="${state.activeTab}"]`);
    if (form instanceof HTMLElement) {
      form.dataset.creatorEntityId = state.drafts[state.activeTab].id || "";
      form.addEventListener("input", () => {
        captureActiveDraft();
        state.dirty[state.activeTab] = true;
        clearMessages();
        updateDirtyPill(root, state.activeTab, true);
      });
      form.addEventListener("change", (event) => {
        captureActiveDraft();
        state.dirty[state.activeTab] = true;
        clearMessages();
        updateDirtyPill(root, state.activeTab, true);
        const target = event.target;
        if (
          target instanceof HTMLElement
          && (
            (
              target.hasAttribute("data-creator-link-input")
              && ["grantMode", "reloadMode", "durationRoundsMode", "chargesMode", "cooldownRoundsMode"].includes(String(target.getAttribute("data-creator-link-input")))
            )
            || (
              target.hasAttribute("data-creator-input")
              && ["itemType"].includes(String(target.getAttribute("data-creator-input")))
            )
            || target.hasAttribute("data-creator-modifier-input")
          )
        ) {
          render();
        }
      });
    }

    root.querySelectorAll("[data-creator-tab]").forEach((button) => {
      button.addEventListener("click", () => {
        captureActiveDraft();
        state.activeTab = button.dataset.creatorTab;
        clearMessages();
        render();
        void ensureReadyForActiveTab();
      });
    });

    root.querySelectorAll("[data-creator-open]").forEach((button) => {
      button.addEventListener("click", () => {
        const [kind, id] = String(button.dataset.creatorOpen ?? "").split(":");
        if (!kind || !id) return;
        captureActiveDraft();
        void openRecord(kind, id);
      });
    });

    root.querySelectorAll("[data-creator-link-remove]").forEach((button) => {
      button.addEventListener("click", () => {
        captureActiveDraft();
        const index = Number.parseInt(String(button.dataset.creatorLinkRemove ?? ""), 10);
        if (!Number.isFinite(index)) return;
        state.drafts.equipment.abilityLinks.splice(index, 1);
        state.dirty.equipment = true;
        clearMessages();
        render();
      });
    });

    root.querySelectorAll("[data-creator-modifier-remove]").forEach((button) => {
      button.addEventListener("click", () => {
        captureActiveDraft();
        const index = Number.parseInt(String(button.dataset.creatorModifierRemove ?? ""), 10);
        if (!Number.isFinite(index)) return;
        state.drafts.equipment.modifiers.splice(index, 1);
        state.dirty.equipment = true;
        clearMessages();
        render();
      });
    });

    root.querySelectorAll("[data-creator-action]").forEach((button) => {
      button.addEventListener("click", () => {
        const action = button.dataset.creatorAction;
        switch (action) {
          case "applyFilters":
            captureActiveDraft();
            applyFiltersFromDom();
            void refreshActiveList();
            break;
          case "refreshList":
            captureActiveDraft();
            void refreshActiveList({ forceRefs: true });
            break;
          case "toggleSkillsCatalog":
            captureActiveDraft();
            state.collapsed.skillsCatalog = !state.collapsed.skillsCatalog;
            render();
            break;
          case "toggleEquipmentCatalog":
            captureActiveDraft();
            state.collapsed.equipmentCatalog = !state.collapsed.equipmentCatalog;
            render();
            break;
          case "toggleSkillsPayload":
            captureActiveDraft();
            state.collapsed.skillsPayload = !state.collapsed.skillsPayload;
            render();
            break;
          case "toggleEquipmentPayload":
            captureActiveDraft();
            state.collapsed.equipmentPayload = !state.collapsed.equipmentPayload;
            render();
            break;
          case "toggleEquipmentDataModifiers":
            captureActiveDraft();
            state.collapsed.equipmentDataModifiers = !state.collapsed.equipmentDataModifiers;
            render();
            break;
          case "newDraft":
            captureActiveDraft();
            createNewDraft();
            break;
          case "duplicateDraft":
            captureActiveDraft();
            duplicateDraft();
            break;
          case "saveDraft":
            captureActiveDraft();
            void saveDraft();
            break;
          case "reloadSelected":
            captureActiveDraft();
            void reloadSelected();
            break;
          case "deleteSelected":
            captureActiveDraft();
            void deleteSelected();
            break;
          case "addAbilityLink":
            captureActiveDraft();
            state.drafts.equipment.abilityLinks.push(createEmptyAbilityLinkDraft());
            state.dirty.equipment = true;
            clearMessages();
            render();
            break;
          case "addModifier":
            captureActiveDraft();
            state.drafts.equipment.modifiers.push(createEmptyModifierDraft());
            state.dirty.equipment = true;
            state.collapsed.equipmentDataModifiers = false;
            clearMessages();
            render();
            break;
          default:
            break;
        }
      });
    });
  }

  function applyFiltersFromDom() {
    if (state.activeTab === "skills") {
      const search = root.querySelector('[data-creator-filter-search="skills"]');
      const category = root.querySelector('[data-creator-filter-category="skills"]');
      state.filters.skills.search = String(search?.value ?? "").trim();
      state.filters.skills.category = String(category?.value ?? "").trim();
    } else {
      const search = root.querySelector('[data-creator-filter-search="equipment"]');
      const itemType = root.querySelector('[data-creator-filter-item-type="equipment"]');
      state.filters.equipment.search = String(search?.value ?? "").trim();
      state.filters.equipment.itemType = String(itemType?.value ?? "").trim();
    }
  }

  async function loadReferenceData(settings) {
    const [referenceResult, itemDefinitions] = await Promise.all([
      runtime.api.creator.getCreatorReferenceData(settings),
      runtime.bridges.supabase.fetchSupabaseRows(
        "odyssey_item_defs?select=id,code,name,item_type&order=name.asc",
        settings,
        "Unable to load item definition reference data.",
      ).catch(() => []),
    ]);
    if (!referenceResult?.ok) {
      throw new Error(formatCreatorError(referenceResult, "Unable to load creator reference data."));
    }
    return {
      ...referenceResult,
      itemDefinitions: Array.isArray(itemDefinitions) ? itemDefinitions : [],
    };
  }

  async function ensureReadyForActiveTab({ forceRefs = false } = {}) {
    const access = getAccess();
    if (!access.isGm || !access.configured) {
      return;
    }

    if (state.lastLoadedSettingsKey && state.lastLoadedSettingsKey !== access.settingsKey) {
      resetLoadedData();
    }

    const shouldLoadRefs = forceRefs || !state.references || state.lastLoadedSettingsKey !== access.settingsKey;
    const shouldLoadList = shouldLoadRefs || !state.loadedTabs[state.activeTab];
    if (!shouldLoadRefs && !shouldLoadList) {
      return;
    }

    const requestId = ++state.requestNonce;
    state.loading = true;
    state.loadingLabel = shouldLoadRefs ? "reference data and catalog" : "catalog";
    clearMessages();
    render();

    try {
      if (shouldLoadRefs) {
        state.references = await loadReferenceData(access.settings);
        if (requestId !== state.requestNonce) return;
        state.lastLoadedSettingsKey = access.settingsKey;
      }
      await loadListForTab(state.activeTab, access.settings, requestId);
      if (requestId !== state.requestNonce) return;
      state.loading = false;
      render();
    } catch (error) {
      if (requestId !== state.requestNonce) return;
      state.loading = false;
      state.error = toErrorMessage(error, "Unable to load creator data.");
      onDiagnostic("error", "Creator load failed", state.error);
      render();
    }
  }

  async function loadListForTab(kind, settings, requestId = state.requestNonce) {
    let result = null;
    if (kind === "skills") {
      const filters = state.filters.skills;
      result = await runtime.api.creator.listSkills(
        {
          search: filters.search || null,
          categories: filters.category ? [filters.category] : [],
        },
        settings,
      );
    } else {
      const filters = state.filters.equipment;
      result = await runtime.api.creator.listEquipmentModels(
        {
          search: filters.search || null,
          itemTypes: filters.itemType ? [filters.itemType] : [],
        },
        settings,
      );
    }

    if (requestId !== state.requestNonce) return;
    if (!result?.ok) {
      throw new Error(formatCreatorError(result, "Unable to load catalog list."));
    }

    state.lists[kind] = kind === "equipment"
      ? (Array.isArray(result.items) ? result.items : []).filter((item) => String(item?.item_type ?? "") !== "device")
      : (Array.isArray(result.items) ? result.items : []);
    state.loadedTabs[kind] = true;

    if (
      state.selectedIds[kind]
      && !state.lists[kind].some((item) => item.id === state.selectedIds[kind])
    ) {
      state.selectedIds[kind] = "";
      state.bundles[kind] = null;
      state.drafts[kind] = kind === "skills" ? createEmptySkillDraft() : createEmptyEquipmentDraft();
      state.dirty[kind] = false;
    }
  }

  async function refreshActiveList({ forceRefs = false } = {}) {
    const access = getAccess();
    if (!access.isGm || !access.configured) {
      return;
    }
    const requestId = ++state.requestNonce;
    state.loading = true;
    state.loadingLabel = forceRefs ? "reference data and current list" : "current list";
    clearMessages();
    render();
    try {
      if (forceRefs) {
        state.references = await loadReferenceData(access.settings);
        state.lastLoadedSettingsKey = access.settingsKey;
      }
      await loadListForTab(state.activeTab, access.settings, requestId);
      state.loading = false;
      state.info = `${state.activeTab === "skills" ? "Skill" : "Equipment"} catalog refreshed.`;
      render();
    } catch (error) {
      state.loading = false;
      state.error = toErrorMessage(error, "Unable to refresh creator list.");
      onDiagnostic("error", "Creator refresh failed", state.error);
      render();
    }
  }

  async function openRecord(kind, id) {
    const access = getAccess();
    if (!access.isGm || !access.configured) {
      return;
    }
    const requestId = ++state.requestNonce;
    state.loading = true;
    state.loadingLabel = `loading ${kind === "skills" ? "skill" : "equipment model"}`;
    clearMessages();
    render();

    try {
      const result = kind === "skills"
        ? await runtime.api.creator.getSkill(id, access.settings)
        : await runtime.api.creator.getEquipmentModel(id, access.settings);
      if (requestId !== state.requestNonce) return;
      if (!result?.ok) {
        throw new Error(formatCreatorError(result, "Unable to load creator record."));
      }
      state.selectedIds[kind] = id;
      state.bundles[kind] = result;
      state.drafts[kind] = kind === "skills"
        ? normalizeSkillDraft(result)
        : normalizeEquipmentDraft(result);
      state.dirty[kind] = false;
      state.loading = false;
      state.info = `${kind === "skills" ? "Skill" : "Equipment model"} loaded into draft.`;
      render();
    } catch (error) {
      if (requestId !== state.requestNonce) return;
      state.loading = false;
      state.error = toErrorMessage(error, "Unable to open creator record.");
      onDiagnostic("error", "Creator open failed", state.error);
      render();
    }
  }

  function createNewDraft() {
    clearMessages();
    if (state.activeTab === "skills") {
      state.selectedIds.skills = "";
      state.bundles.skills = null;
      state.drafts.skills = createEmptySkillDraft();
      state.dirty.skills = false;
      state.info = "New skill draft created.";
    } else {
      state.selectedIds.equipment = "";
      state.bundles.equipment = null;
      state.drafts.equipment = createEmptyEquipmentDraft();
      state.dirty.equipment = false;
      state.info = "New equipment draft created.";
    }
    render();
  }

  function duplicateDraft() {
    clearMessages();
    if (state.activeTab === "skills") {
      state.selectedIds.skills = "";
      state.bundles.skills = null;
      state.drafts.skills = makeSkillDuplicateDraft(state.drafts.skills);
      state.dirty.skills = true;
      state.info = "Skill draft duplicated as a new record.";
    } else {
      state.selectedIds.equipment = "";
      state.bundles.equipment = null;
      state.drafts.equipment = makeEquipmentDuplicateDraft(state.drafts.equipment);
      state.dirty.equipment = true;
      state.info = "Equipment draft duplicated as a new record.";
    }
    render();
  }

  async function buildSavePayload(kind, draft, settings) {
    if (kind === "skills") {
      const allSkills = await runtime.api.creator.listSkills({ search: null, categories: [] }, settings);
      if (!allSkills?.ok) {
        throw new Error(formatCreatorError(allSkills, "Unable to calculate automatic skill fields."));
      }
      const referenceScope = state.references ?? {};
      const list = Array.isArray(allSkills.items) ? allSkills.items : [];
      const existingCodes = list
        .filter((item) => item.id !== draft.id)
        .map((item) => item.code);
      const auto = {
        code: uniqueGeneratedCode(slugifyName(draft.name), existingCodes),
        sortOrder: draft.id
          ? Number.parseInt(String(state.bundles.skills?.skill?.sort_order ?? 0), 10) || 0
          : nextFreeSortOrder(list),
        tags: buildSkillAutoTags(draft, referenceScope),
      };
      return buildSkillPayload(draft, auto);
    }

    const allEquipment = await runtime.api.creator.listEquipmentModels({ search: null, itemTypes: [] }, settings);
    if (!allEquipment?.ok) {
      throw new Error(formatCreatorError(allEquipment, "Unable to calculate automatic equipment fields."));
    }
    const list = Array.isArray(allEquipment.items) ? allEquipment.items : [];
    const existingCodes = list
      .filter((item) => item.id !== draft.id)
      .map((item) => item.code);
    const auto = {
      code: uniqueGeneratedCode(slugifyName(draft.name), existingCodes),
      sortOrder: draft.id
        ? Number.parseInt(String(state.bundles.equipment?.equipment_model?.sort_order ?? 0), 10) || 0
        : nextFreeSortOrder(list),
      tags: buildEquipmentAutoTags(draft),
    };
    return buildEquipmentPayload(draft, auto);
  }

  async function saveDraft() {
    const access = getAccess();
    if (!access.isGm || !access.configured) {
      return;
    }
    clearMessages();
    state.loading = true;
    state.loadingLabel = "saving draft";
    render();
    try {
      const draft = state.activeTab === "skills" ? state.drafts.skills : state.drafts.equipment;
      const payload = await buildSavePayload(state.activeTab, draft, access.settings);
      const result = state.activeTab === "skills"
        ? await runtime.api.creator.upsertSkill(payload, access.settings)
        : await runtime.api.creator.upsertEquipmentModel(payload, access.settings);
      if (!result?.ok) {
        throw new Error(formatCreatorError(result, "Unable to save draft."));
      }
      const bundle = extractEntityBundle(result);
      if (!bundle?.ok) {
        throw new Error("Save succeeded but the returned entity bundle was incomplete.");
      }
      if (state.activeTab === "skills") {
        state.selectedIds.skills = String(result.entity_id ?? "");
        state.bundles.skills = bundle;
        state.drafts.skills = normalizeSkillDraft(bundle);
        state.dirty.skills = false;
      } else {
        state.selectedIds.equipment = String(result.entity_id ?? "");
        state.bundles.equipment = bundle;
        state.drafts.equipment = normalizeEquipmentDraft(bundle);
        state.dirty.equipment = false;
      }
      await loadListForTab(state.activeTab, access.settings);
      state.loading = false;
      state.info = `${state.activeTab === "skills" ? "Skill" : "Equipment model"} saved to Supabase.`;
      onDiagnostic("info", "Creator save complete", state.info);
      render();
    } catch (error) {
      state.loading = false;
      state.error = toErrorMessage(error, "Unable to save draft.");
      onDiagnostic("error", "Creator save failed", state.error);
      render();
    }
  }

  async function reloadSelected() {
    const id = state.selectedIds[state.activeTab];
    if (!id) {
      return;
    }
    await openRecord(state.activeTab, id);
  }

  async function deleteSelected() {
    const access = getAccess();
    const id = state.selectedIds[state.activeTab];
    if (!access.isGm || !access.configured || !id) {
      return;
    }
    const label = state.activeTab === "skills" ? "skill" : "equipment model";
    if (!globalThis.confirm(`Delete this ${label} definition from the catalog?`)) {
      return;
    }

    clearMessages();
    state.loading = true;
    state.loadingLabel = `deleting ${label}`;
    render();
    try {
      const result = state.activeTab === "skills"
        ? await runtime.api.creator.deleteSkill(id, access.settings)
        : await runtime.api.creator.deleteEquipmentModel(id, access.settings);
      if (!result?.ok) {
        throw new Error(formatCreatorError(result, `Unable to delete ${label}.`));
      }
      if (state.activeTab === "skills") {
        state.selectedIds.skills = "";
        state.bundles.skills = null;
        state.drafts.skills = createEmptySkillDraft();
        state.dirty.skills = false;
      } else {
        state.selectedIds.equipment = "";
        state.bundles.equipment = null;
        state.drafts.equipment = createEmptyEquipmentDraft();
        state.dirty.equipment = false;
      }
      await loadListForTab(state.activeTab, access.settings);
      state.loading = false;
      state.info = `${label[0].toUpperCase()}${label.slice(1)} deleted from the catalog.`;
      onDiagnostic("info", "Creator delete complete", state.info);
      render();
    } catch (error) {
      state.loading = false;
      state.error = toErrorMessage(error, `Unable to delete ${label}.`);
      onDiagnostic("error", "Creator delete failed", state.error);
      render();
    }
  }

  const controller = {
    syncAccess() {
      const access = getAccess();
      if (state.lastLoadedSettingsKey && state.lastLoadedSettingsKey !== access.settingsKey) {
        resetLoadedData();
      }
      render();
      void ensureReadyForActiveTab();
    },
    refresh() {
      render();
      void ensureReadyForActiveTab({ forceRefs: true });
    },
  };

  render();
  void ensureReadyForActiveTab();
  return controller;
}
