import { CHECK_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

export function rollCharacteristic(payload, settings) {
  return callSupabaseRpc(
    CHECK_RPC_NAMES.rollCharacteristic,
    { p_payload: payload },
    settings,
  );
}

export function rollSkill(payload, settings) {
  return callSupabaseRpc(
    CHECK_RPC_NAMES.rollSkill,
    { p_payload: payload },
    settings,
  );
}

export function rollDice(expression, reason = null, settings) {
  return callSupabaseRpc(
    CHECK_RPC_NAMES.rollDice,
    {
      p_payload: {
        expression,
        reason,
      },
    },
    settings,
  );
}
