import { EFFECT_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

export function getCharacterEffectSummary(characterId, settings) {
  return callSupabaseRpc(
    EFFECT_RPC_NAMES.getCharacterEffectSummary,
    { p_character_id: characterId },
    settings,
  );
}

export function getEffectiveCharacterStats(characterId, settings) {
  return callSupabaseRpc(
    EFFECT_RPC_NAMES.getEffectiveCharacterStats,
    { p_character_id: characterId },
    settings,
  );
}

export function addCharacterEffect(payload, settings) {
  return callSupabaseRpc(
    EFFECT_RPC_NAMES.addCharacterEffect,
    { p_payload: payload },
    settings,
  );
}

export function removeCharacterEffect(effectId, settings) {
  return callSupabaseRpc(
    EFFECT_RPC_NAMES.removeCharacterEffect,
    { p_effect_id: effectId },
    settings,
  );
}

export function advanceCharacterEffects(characterId, settings) {
  return callSupabaseRpc(
    EFFECT_RPC_NAMES.advanceCharacterEffects,
    { p_character_id: characterId },
    settings,
  );
}
