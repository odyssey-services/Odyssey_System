import { FEATURE_RPC_NAMES } from "../constants/rpcNames.js";
import { callSupabaseRpc } from "../bridge/supabaseBridge.js";

export function reloadFeatureResource(payload, settings) {
  return callSupabaseRpc(
    FEATURE_RPC_NAMES.reloadFeatureResource,
    { p_payload: payload },
    settings,
  );
}
