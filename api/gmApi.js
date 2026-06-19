import { GM_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

// GM tools. NOTE: these functions exist in the live database but are not yet present
// in the repo SQL migrations — flagged for the backend owner to commit a migration.

// Full-character heal: clears damage on all body parts (revives head/torso).
// payload: { character_id }
export function gmHealCharacter(characterId, settings) {
  return callSupabaseRpc(
    GM_RPC_NAMES.healCharacter,
    { p_payload: { character_id: characterId } },
    settings,
  );
}

// Repair all armor sections of a character.
// payload: { character_id }
export function gmRepairCharacterArmor(characterId, settings) {
  return callSupabaseRpc(
    GM_RPC_NAMES.repairCharacterArmor,
    { p_payload: { character_id: characterId } },
    settings,
  );
}

// GM set/adjust a character attribute value (progression).
// payload: { character_id, attribute_code|attribute_def_id, operation:'set'|'adjust', value, reason }
export function gmUpdateCharacterAttribute(payload, settings) {
  return callSupabaseRpc(
    GM_RPC_NAMES.updateCharacterAttribute,
    { p_payload: payload },
    settings,
  );
}
