import { INVENTORY_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

export function getCharacterInventory(characterId, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.getCharacterInventory,
    { p_character_id: characterId },
    settings,
  );
}

export function addCharacterItem(payload, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.addCharacterItem,
    { p_payload: payload },
    settings,
  );
}

export function removeCharacterItemQuantity(characterId, itemCode, quantity, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.removeCharacterItemQuantity,
    {
      p_character_id: characterId,
      p_item_code: itemCode,
      p_quantity: quantity,
    },
    settings,
  );
}

export function getCharacterItemQuantity(characterId, itemCode, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.getCharacterItemQuantity,
    {
      p_character_id: characterId,
      p_item_code: itemCode,
    },
    settings,
  );
}

export function addCharacterAmmoStock(payload, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.addCharacterAmmoStock,
    { p_payload: payload },
    settings,
  );
}

export function removeCharacterAmmoStock(ammoStockId, quantity, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.removeCharacterAmmoStock,
    {
      p_ammo_stock_id: ammoStockId,
      p_quantity: quantity,
    },
    settings,
  );
}

export function loadRoundsToMagazine(payload, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.loadRoundsToMagazine,
    { p_payload: payload },
    settings,
  );
}

export function unloadRoundsFromMagazine(payload, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.unloadRoundsFromMagazine,
    { p_payload: payload },
    settings,
  );
}

export function useCharacterItem(payload, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.useCharacterItem,
    { p_payload: payload },
    settings,
  );
}

export function reloadInventoryResource(payload, settings) {
  return callSupabaseRpc(
    INVENTORY_RPC_NAMES.reloadInventoryResource,
    { p_payload: payload },
    settings,
  );
}
