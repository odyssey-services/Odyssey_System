import { PERK_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

export function getCharacterPerks(payload, settings) {
  return callSupabaseRpc(
    PERK_RPC_NAMES.getCharacterPerks,
    { p_payload: payload },
    settings,
  );
}

export function getCharacterAvailablePerks(payload, settings) {
  return callSupabaseRpc(
    PERK_RPC_NAMES.getCharacterAvailablePerks,
    { p_payload: payload },
    settings,
  );
}

export function grantCharacterPerk(payload, settings) {
  return callSupabaseRpc(
    PERK_RPC_NAMES.grantCharacterPerk,
    { p_payload: payload },
    settings,
  );
}

export function useCharacterPerk(payload, settings) {
  return callSupabaseRpc(
    PERK_RPC_NAMES.useCharacterPerk,
    { p_payload: payload },
    settings,
  );
}
