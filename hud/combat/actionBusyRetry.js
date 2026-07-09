// Combat HUD — ACTION_BUSY_RETRY handling (PURE).
//
// combat_execute_action returns { ok:false, error:"ACTION_BUSY_RETRY", message }
// as a normal (non-throwing) jsonb body on lock/statement-timeout contention
// (see supabase/104_ability_timeout_hotfix.sql). This is a transient,
// server-told-us-to-retry condition — never a real rejection — so it gets
// exactly ONE automatic retry after a short delay, not the generic error
// treatment every other failure code gets. Any other error/code (including a
// thrown exception) is returned as-is, untouched.

const ACTION_BUSY_RETRY_CODE = "ACTION_BUSY_RETRY";

/**
 * @param {() => Promise<object>} callFn  Performs ONE RPC call and resolves
 *   with its raw result (never throws for a normal { ok:false } rejection).
 * @param {{ retryDelayMs?: number }} [opts]
 * @returns {Promise<{ result: object, retried: boolean, firstError: (string|null) }>}
 */
export async function callWithBusyRetry(callFn, opts = {}) {
  const retryDelayMs = Number.isFinite(opts.retryDelayMs) ? opts.retryDelayMs : 250;
  const first = await callFn();
  if (first?.error !== ACTION_BUSY_RETRY_CODE) {
    return { result: first, retried: false, firstError: null };
  }
  await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
  const second = await callFn();
  return { result: second, retried: true, firstError: ACTION_BUSY_RETRY_CODE };
}
