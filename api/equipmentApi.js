import { EQUIPMENT_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

export function getCharacterArmorSummary(characterId, settings) {
  return callSupabaseRpc(
    EQUIPMENT_RPC_NAMES.getCharacterArmorSummary,
    { p_character_id: characterId },
    settings,
  );
}

export function getCharacterEquipment(characterId, settings) {
  return callSupabaseRpc(
    EQUIPMENT_RPC_NAMES.getCharacterEquipment,
    { p_character_id: characterId },
    settings,
  );
}

export function recomputeCharacterArmor(characterId, settings) {
  return callSupabaseRpc(
    EQUIPMENT_RPC_NAMES.recomputeCharacterArmor,
    { p_character_id: characterId },
    settings,
  );
}

export function createCharacterEquipmentItem(payload, settings) {
  return callSupabaseRpc(
    EQUIPMENT_RPC_NAMES.createCharacterEquipmentItem,
    { p_payload: payload },
    settings,
  );
}

export function equipCharacterEquipmentItem(equipmentItemId, bodyPartId, settings) {
  return callSupabaseRpc(
    EQUIPMENT_RPC_NAMES.equipCharacterEquipmentItem,
    {
      p_item_id: equipmentItemId,
      p_body_part_id: bodyPartId,
    },
    settings,
  );
}

export function unequipCharacterEquipmentItem(equipmentItemId, settings) {
  return callSupabaseRpc(
    EQUIPMENT_RPC_NAMES.unequipCharacterEquipmentItem,
    { p_item_id: equipmentItemId },
    settings,
  );
}

export function updateCharacterEquipmentItem(payload, settings) {
  return callSupabaseRpc(
    EQUIPMENT_RPC_NAMES.updateCharacterEquipmentItem,
    { p_payload: payload },
    settings,
  );
}
