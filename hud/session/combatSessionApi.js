// Combat HUD — Phase 3E.0 combat-session API adapter (thin, no state).
//
// Payload builders + RPC calls over the EXISTING encounter RPC suite
// (api/combatApi.js → combat_start_encounter / combat_end_turn /
// combat_skip_turn / combat_force_next_turn / combat_end_encounter /
// combat_get_active_runtime — all shipped by supabase migrations 64/79/80/90).
// No new RPC names are invented here.

import {
  getActiveRuntime,
  startEncounter,
  endTurn,
  skipTurn,
  forceNextTurn,
  endEncounter,
} from "../../api/combatApi.js";
import { getSceneTokenLinks } from "../../api/characterPlacementApi.js";

function actorFields(context, viewer) {
  return {
    campaign_id: context?.campaignId ?? "",
    room_id: context?.roomId ?? "",
    scene_id: context?.sceneId ?? "",
    actor_player_id: viewer?.playerId ?? "",
    actor_is_gm: String(viewer?.role ?? "").toUpperCase() === "GM",
  };
}

export function fetchActiveSessionRuntime({ context, viewer, settings }) {
  return getActiveRuntime(actorFields(context, viewer), settings);
}

export function fetchSceneLinkCandidates({ context, viewer, settings }) {
  return getSceneTokenLinks(
    { ...actorFields(context, viewer), include_inactive: false },
    settings,
  );
}

export function startSession({ context, viewer, settings, excludedCharacterIds = [], hiddenTokenIds = [] }) {
  return startEncounter(
    {
      ...actorFields(context, viewer),
      excluded_character_ids: excludedCharacterIds,
      hidden_token_ids: hiddenTokenIds,
    },
    settings,
  );
}

function mutationFields({ context, viewer, sessionId, expectedVersion }) {
  return {
    ...actorFields(context, viewer),
    encounter_id: sessionId,
    ...(Number.isFinite(Number(expectedVersion)) ? { expected_encounter_version: Number(expectedVersion) } : {}),
  };
}

export function endSessionTurn(args) {
  return endTurn(mutationFields(args), args.settings);
}

export function gmSkipTurn(args) {
  return skipTurn(mutationFields(args), args.settings);
}

export function gmForceNextTurn(args) {
  return forceNextTurn(mutationFields(args), args.settings);
}

export function endSession(args) {
  return endEncounter(mutationFields(args), args.settings);
}
