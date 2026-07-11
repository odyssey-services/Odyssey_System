function normalizeTokens(rawTokens) {
  if (!Array.isArray(rawTokens)) return [];
  const seen = new Set();
  const tokens = [];
  for (const token of rawTokens) {
    const id = String(token?.id ?? "").trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    tokens.push({
      ...token,
      id,
      name: String(token?.name ?? "").trim(),
    });
  }
  return tokens;
}

function buildSelectionSignature(tokens) {
  return `${tokens.length}:${tokens.map((token) => token.id).sort().join("|")}`;
}

function firstText(...values) {
  for (const value of values) {
    const text = String(value ?? "").trim();
    if (text) return text;
  }
  return "";
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function defaultIsGm(player) {
  return String(player?.role ?? "").trim().toUpperCase() === "GM";
}

export function createStableOwlbearSelectionResolver({
  getSelectedOwlbearTokens,
  getRoomSceneContext,
  getPlayerInfo,
  getActiveCombatRuntime,
  getSceneTokenLinks,
  hasUsableSettings,
  getSettings,
  isGm = defaultIsGm,
  logDebugEvent = null,
  debounceMs = 100,
  onState,
} = {}) {
  let selectionTimer = null;
  let selectionRequestId = 0;
  let lastSelectionSignature = "";
  let disposed = false;
  let lastResolvedSelectionIds = [];

  function log(category, action, details = {}, ok = true, status = "ok") {
    if (typeof logDebugEvent !== "function") return;
    logDebugEvent(category, action, details, ok, status);
  }

  function isCurrentRequest(requestId) {
    return !disposed && requestId === selectionRequestId;
  }

  async function emit(state) {
    if (disposed || typeof onState !== "function") return;
    await onState(state);
  }

  function finishRequest(requestId, tokens, reason, timedOut = false) {
    log("selection", "selection-resolve-finished", {
      tokenIds: tokens.map((token) => token.id),
      reason,
      requestId,
      timedOut,
    }, !timedOut);
  }

  async function sync({ force = false, reason = "selection-changed" } = {}) {
    const requestId = ++selectionRequestId;
    let finished = false;
    const finish = (tokens = [], timedOut = false) => {
      if (finished) return;
      finished = true;
      finishRequest(requestId, tokens, reason, timedOut);
    };

    try {
      const selectedTokens = normalizeTokens(await getSelectedOwlbearTokens?.());
      if (!isCurrentRequest(requestId)) {
        finish(selectedTokens);
        return;
      }

      const selectionIds = selectedTokens.map((token) => token.id);
      const signature = buildSelectionSignature(selectedTokens);
      log("selection", "selection-live-read", {
        tokenIds: selectionIds,
        currentSelectionIds: lastResolvedSelectionIds,
        reason,
      });

      if (!force && signature === lastSelectionSignature) {
        log("selection", "selection-live-unchanged", {
          tokenIds: selectionIds,
          reason,
        });
        finish(selectedTokens);
        return;
      }
      lastSelectionSignature = signature;

      log("selection", "selection-resolve-start", {
        tokenIds: selectionIds,
        reason,
        requestId,
      }, true, "pending");

      if (selectedTokens.length === 0) {
        lastResolvedSelectionIds = [];
        const state = {
          status: "no-selection",
          tokenId: null,
          tokenName: "",
          characterId: null,
          characterName: "",
          source: "",
          requestId,
          reason,
          selectedTokens,
          error: "NO_TOKEN_SELECTED",
        };
        log("selection", "selection-resolve-result", {
          tokenIds: [],
          reason,
          requestId,
          status: state.status,
          selectedItemId: null,
          characterId: null,
        });
        await emit(state);
        finish(selectedTokens);
        return;
      }

      if (selectedTokens.length > 1) {
        lastResolvedSelectionIds = selectionIds.slice();
        const state = {
          status: "multiple-selection",
          tokenId: null,
          tokenName: "",
          characterId: null,
          characterName: "",
          source: "",
          requestId,
          reason,
          selectedTokens,
          error: "MULTIPLE_TOKENS_SELECTED",
        };
        log("selection", "selection-resolve-result", {
          tokenIds: selectionIds,
          reason,
          requestId,
          status: state.status,
          selectedItemId: null,
          characterId: null,
        });
        await emit(state);
        finish(selectedTokens);
        return;
      }

      const selectedToken = selectedTokens[0];
      const tokenId = selectedToken.id;
      const tokenName = selectedToken.name;
      lastResolvedSelectionIds = [tokenId];

      log("selection", "source-token-selected", {
        tokenIds: [tokenId],
        reason,
      });

      await emit({
        status: "loading",
        tokenId,
        tokenName,
        characterId: null,
        characterName: "",
        source: "",
        requestId,
        reason,
        selectedTokens,
      });
      if (!isCurrentRequest(requestId)) {
        finish(selectedTokens);
        return;
      }

      const [context, player] = await Promise.all([
        getRoomSceneContext?.(),
        getPlayerInfo?.(),
      ]);
      if (!isCurrentRequest(requestId)) {
        finish(selectedTokens);
        return;
      }

      const settings = typeof getSettings === "function" ? getSettings() : null;
      if (
        !context?.campaignId ||
        !context?.roomId ||
        !context?.sceneId ||
        (typeof hasUsableSettings === "function" && !hasUsableSettings(settings))
      ) {
        const state = {
          status: "error",
          tokenId,
          tokenName,
          characterId: null,
          characterName: "",
          source: "",
          requestId,
          reason,
          selectedTokens,
          error: "SCENE_CONTEXT_UNAVAILABLE",
          message: "Unable to resolve Owlbear scene context.",
        };
        log("selection", "selection-resolve-result", {
          tokenIds: [tokenId],
          reason,
          requestId,
          status: state.status,
          selectedItemId: tokenId,
          characterId: null,
          error: state.error,
        }, false);
        await emit(state);
        finish(selectedTokens);
        return;
      }

      const viewerIsGm = typeof isGm === "function" ? isGm(player) : defaultIsGm(player);
      let runtime = null;
      try {
        runtime = await getActiveCombatRuntime?.({
          context,
          player,
          viewerIsGm,
          settings,
        });
      } catch (_error) {
        runtime = null;
      }
      if (!isCurrentRequest(requestId)) {
        finish(selectedTokens);
        return;
      }

      const participant = asArray(runtime?.visible_participants).find(
        (row) => String(row?.token_id ?? "").trim() === tokenId,
      ) ?? null;

      if (participant) {
        const characterId = String(participant?.character_id ?? "").trim();
        const characterName = firstText(
          participant?.display_name,
          participant?.character_key,
        );
        const controlledIds = new Set(
          asArray(runtime?.viewer_controlled_character_ids)
            .map((id) => String(id ?? "").trim())
            .filter(Boolean),
        );
        const allowed = viewerIsGm || controlledIds.has(characterId);
        const state = allowed
          ? {
              status: "ready",
              tokenId,
              tokenName,
              characterId,
              characterName,
              source: "combat_runtime",
              requestId,
              reason,
              selectedTokens,
            }
          : {
              status: "not-owned",
              tokenId,
              tokenName,
              characterId,
              characterName: "",
              source: "combat_runtime",
              requestId,
              reason,
              selectedTokens,
              error: "CHARACTER_NOT_CONTROLLED",
              message: "You can only control characters assigned to you.",
            };
        log("selection", "selection-resolve-result", {
          tokenIds: [tokenId],
          reason,
          requestId,
          status: state.status,
          selectedItemId: tokenId,
          characterId,
          source: state.source,
        }, allowed);
        await emit(state);
        finish(selectedTokens);
        return;
      }

      let linkResult = null;
      try {
        linkResult = await getSceneTokenLinks?.({
          campaign_id: context.campaignId,
          room_id: context.roomId,
          scene_id: context.sceneId,
          token_id: tokenId,
          actor_player_id: player?.id ?? "",
          actor_is_gm: viewerIsGm,
        }, settings);
      } catch (error) {
        const state = {
          status: "error",
          tokenId,
          tokenName,
          characterId: null,
          characterName: "",
          source: "scene_link",
          requestId,
          reason,
          selectedTokens,
          error: "LINK_FETCH_FAILED",
          message: String(error?.message ?? error ?? "Unable to resolve scene token link."),
        };
        log("selection", "selection-resolve-result", {
          tokenIds: [tokenId],
          reason,
          requestId,
          status: state.status,
          selectedItemId: tokenId,
          characterId: null,
          error: state.error,
        }, false);
        await emit(state);
        finish(selectedTokens);
        return;
      }
      if (!isCurrentRequest(requestId)) {
        finish(selectedTokens);
        return;
      }

      const link = asArray(linkResult?.links).find(
        (row) => String(row?.token_id ?? "").trim() === tokenId && row?.is_active !== false,
      ) ?? null;
      const linkCharacterId = String(link?.character?.id ?? "").trim();
      if (!linkCharacterId) {
        const state = {
          status: "unlinked-token",
          tokenId,
          tokenName,
          characterId: null,
          characterName: "",
          source: "scene_link",
          requestId,
          reason,
          selectedTokens,
          error: "TOKEN_HAS_NO_CHARACTER",
          message: "Selected token is not linked to a character.",
        };
        log("selection", "selection-resolve-result", {
          tokenIds: [tokenId],
          reason,
          requestId,
          status: state.status,
          selectedItemId: tokenId,
          characterId: null,
          source: state.source,
        }, false);
        await emit(state);
        finish(selectedTokens);
        return;
      }

      const allowed = viewerIsGm
        || link?.character?.control?.allowed === true
        || link?.character?.can_control === true;
      const state = allowed
        ? {
            status: "ready",
            tokenId,
            tokenName,
            characterId: linkCharacterId,
            characterName: firstText(link?.character?.display_name, link?.character?.character_key),
            source: "scene_link",
            requestId,
            reason,
            selectedTokens,
          }
        : {
            status: "not-owned",
            tokenId,
            tokenName,
            characterId: linkCharacterId,
            characterName: "",
            source: "scene_link",
            requestId,
            reason,
            selectedTokens,
            error: "CHARACTER_NOT_CONTROLLED",
            message: "You can only control characters assigned to you.",
          };
      log("selection", "selection-resolve-result", {
        tokenIds: [tokenId],
        reason,
        requestId,
        status: state.status,
        selectedItemId: tokenId,
        characterId: linkCharacterId,
        source: state.source,
      }, allowed);
      await emit(state);
      finish(selectedTokens);
    } catch (error) {
      const requestId = selectionRequestId;
      const state = {
        status: "error",
        tokenId: null,
        tokenName: "",
        characterId: null,
        characterName: "",
        source: "",
        requestId,
        reason,
        selectedTokens: [],
        error: "SELECTION_RESOLVE_FAILED",
        message: String(error?.message ?? error ?? "Unable to resolve selected token."),
      };
      log("selection", "selection-resolve-result", {
        tokenIds: [],
        reason,
        requestId,
        status: state.status,
        selectedItemId: null,
        characterId: null,
        error: state.error,
      }, false);
      await emit(state);
      finish([], false);
    }
  }

  async function runSelectionSync({ force = false, reason = "selection-changed" } = {}) {
    if (disposed) return;
    if (selectionTimer) {
      clearTimeout(selectionTimer);
      selectionTimer = null;
    }
    await sync({ force, reason });
  }

  function scheduleSelectionSync({ force = false, reason = "selection-changed" } = {}) {
    if (disposed) return;
    if (selectionTimer) clearTimeout(selectionTimer);
    selectionTimer = setTimeout(() => {
      selectionTimer = null;
      void sync({ force, reason });
    }, Math.max(0, Number(debounceMs) || 0));
  }

  function dispose() {
    disposed = true;
    if (selectionTimer) {
      clearTimeout(selectionTimer);
      selectionTimer = null;
    }
  }

  return {
    runSelectionSync,
    scheduleSelectionSync,
    dispose,
    getCurrentRequestId() {
      return selectionRequestId;
    },
  };
}
