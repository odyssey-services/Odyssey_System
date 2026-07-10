function normalizeVersion(value) {
  const version = Number(value);
  return Number.isFinite(version) ? version : null;
}

export function buildSwitchActiveWeaponPayload({
  characterId,
  weaponId,
  session,
}) {
  const payload = {
    character_id: String(characterId ?? "").trim(),
    character_weapon_id: String(weaponId ?? "").trim(),
  };
  if (session?.exists && session?.id) {
    payload.encounter_id = String(session.id).trim();
  }
  const version = normalizeVersion(session?.version ?? session?.stateVersion);
  if (version != null) {
    payload.expected_encounter_version = version;
  }
  return payload;
}

export function resolveWeaponSwitchErrorMessage(result) {
  if (result?.error === "COMBAT_CONTEXT_AMBIGUOUS") {
    return "This character is in multiple active encounters. End old combats or reselect the token.";
  }
  return result?.message || result?.error || "Weapon switch failed.";
}
