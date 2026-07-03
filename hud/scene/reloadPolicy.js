// Combat HUD — weapon-profile magazine reload policy (PURE).
//
// Small, pure helpers extracted from sceneSelectionController's "reload"
// command handling so the decision logic (which magazine id to send, whether
// the RPC result counts as success) is independently unit-testable and has a
// single source of truth — no OBR, no DOM, no Supabase.

/**
 * The magazine id the Reload command should send to
 * `loadWeaponProfileMagazine`. The player's EXPLICIT selection
 * (`command.magazineId`, sourced from the magazine the player actually
 * clicked) always wins; the ephemeral selection and "first reserve magazine"
 * are fallbacks for a Reload click with no explicit id on the command itself.
 * The HUD must NEVER silently substitute a different magazine than the one
 * the player selected — that was the 1.8.22-era regression (an omitted
 * ephemeral field meant every reload silently used reserve[0]).
 *
 * @param {{ magazineId?: (string|null) }} command
 * @param {{ selectedReloadMagazineId?: (string|null) }} ephemeral
 * @param {{ reserveMagazines?: Array<{id:string}> } | null} weapon
 * @returns {string|null}
 */
export function resolveReloadMagazineId(command, ephemeral, weapon) {
  const raw = command?.magazineId ?? ephemeral?.selectedReloadMagazineId ?? weapon?.reserveMagazines?.[0]?.id ?? "";
  const trimmed = String(raw).trim();
  return trimmed || null;
}

/**
 * `loadWeaponProfileMagazine` returns a normal (HTTP 200) jsonb body of
 * `{ ok:false, error, message }` on validation failures — it does NOT throw.
 * A bare `try { await rpc() } catch {}` without reading `result.ok` reports
 * success on every non-throwing call, silently swallowing real backend
 * rejections. This is the single place that decides "did the reload actually
 * succeed" — never re-derive it inline.
 *
 * @param {{ ok?: boolean } | null | undefined} result
 * @returns {boolean}
 */
export function isReloadRpcOk(result) {
  return result?.ok !== false;
}

/**
 * Normalize a reload RPC result (or a pre-RPC validation failure) into the
 * compact `{ ok, error, message }` shape both the `?debug=1` diagnostics and
 * the user-facing commandStatus toast are built from.
 *
 * @param {{ ok?: boolean, error?: string, message?: string } | null | undefined} result
 * @returns {{ ok: boolean, error: (string|null), message: (string|null) }}
 */
export function normalizeReloadRpcResult(result) {
  const ok = isReloadRpcOk(result);
  return {
    ok,
    error: ok ? null : (result?.error ?? null),
    message: result?.message ?? null,
  };
}
