// Combat HUD — per-character selected-weapon memory (PURE).
//
// Phase 3D.1 fix: the Gun HUD's `selectedWeaponId` used to be a single flat
// ephemeral field, reset to null on EVERY source-character change. Switching
// Token A (rifle selected) → Token B → back to Token A lost the rifle
// selection and silently fell back to the first weapon in armory sort order.
//
// This is a controller-local, session-scoped map (characterId -> weaponId),
// NOT persisted to localStorage/Supabase/OBR metadata — it lives only as long
// as the background controller instance does (one Owlbear session), per the
// spec's explicit "no cross-browser persistence, just correct in-session
// state" requirement.

/** @returns {{ get:(characterId:string|null)=>(string|null), set:(characterId:string|null, weaponId:string|null)=>void, forget:(characterId:string|null)=>void }} */
export function createSelectedWeaponMemory() {
  const map = new Map();
  return {
    get(characterId) {
      if (!characterId) return null;
      return map.get(characterId) ?? null;
    },
    set(characterId, weaponId) {
      if (!characterId) return;
      const id = weaponId ? String(weaponId) : null;
      if (id) map.set(characterId, id);
      else map.delete(characterId);
    },
    forget(characterId) {
      if (characterId) map.delete(characterId);
    },
  };
}

/**
 * Validate a remembered weapon id against the character's CURRENT armory
 * weapons list — the weapon may have been removed, transferred away, or never
 * existed on this armory snapshot. Returns the id only if it's still present,
 * otherwise null (caller should forget the stale entry and fall back to the
 * mapper's own default, mirrors mapWeapon's existing weapons[0] fallback).
 *
 * @param {string|null} storedWeaponId
 * @param {Array<{id?:string}>|null|undefined} armoryWeapons
 * @returns {string|null}
 */
export function resolveStoredWeaponId(storedWeaponId, armoryWeapons) {
  if (!storedWeaponId) return null;
  const weapons = Array.isArray(armoryWeapons) ? armoryWeapons : [];
  const stillValid = weapons.some((w) => String(w?.id ?? "") === String(storedWeaponId));
  return stillValid ? String(storedWeaponId) : null;
}
