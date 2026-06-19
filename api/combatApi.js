import { COMBAT_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

export function performAttack(payload, settings) {
  return callSupabaseRpc(
    COMBAT_RPC_NAMES.performAttack,
    { p_payload: payload },
    settings,
  );
}
