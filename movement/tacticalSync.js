import {
  getPlayerInfo,
  getRoomSceneContext,
  getSceneGrid,
  getSceneItems,
  snapScenePosition,
} from "../bridge/obrBridge.js";
import { normalizeDistanceMode, normalizeObrGridType, sceneToCell } from "./gridMath.js";

function ensureArray(value) {
  return Array.isArray(value) ? value : [];
}

export async function buildOwlbearTacticalGridPayload() {
  const grid = await getSceneGrid();
  if (!grid) {
    throw new Error("Owlbear grid is not available.");
  }
  const gridType = normalizeObrGridType(grid.type);
  const distanceMode = normalizeDistanceMode(grid.type, grid.measurement);
  if (!gridType || !distanceMode || !(Number(grid.dpi) > 0)) {
    throw new Error("Only Square, Hex Vertical, and Hex Horizontal grids are supported for tactical movement.");
  }
  const anchor = await snapScenePosition({ x: 0, y: 0 }, 1);
  if (!anchor) {
    throw new Error("Unable to resolve tactical grid anchor from Owlbear.");
  }
  const metersPerCell = Math.max(1, Math.round(Number(grid?.scale?.parsed?.multiplier ?? 1) || 1));
  return {
    grid_type: gridType,
    distance_mode: distanceMode,
    meters_per_cell: metersPerCell,
    anchor_scene_x: Number(anchor.x) || 0,
    anchor_scene_y: Number(anchor.y) || 0,
    grid_dpi: Number(grid.dpi) || 0,
  };
}

export async function syncCombatScenePositions({
  combatApi,
  settings,
  runtimeResponse = null,
  onlyCharacterId = "",
}) {
  if (!combatApi?.syncPositionsFromOwlbear) {
    throw new Error("Combat sync API is unavailable.");
  }

  const [context, player] = await Promise.all([
    getRoomSceneContext(),
    getPlayerInfo(),
  ]);

  if (String(player?.role ?? "").toUpperCase() !== "GM") {
    throw new Error("Only the GM can sync tactical positions.");
  }

  if (!context?.campaignId || !context?.roomId || !context?.sceneId) {
    throw new Error("Unable to resolve Owlbear room or scene context.");
  }

  const runtimeRes = runtimeResponse ?? await combatApi.getActiveRuntime(
    {
      campaign_id: context.campaignId,
      room_id: context.roomId,
      scene_id: context.sceneId,
      actor_player_id: player?.id ?? "",
      actor_is_gm: true,
      include_hidden: true,
    },
    settings,
  );

  if (!runtimeRes?.encounter?.id) {
    throw new Error("Unable to resolve the active encounter context.");
  }

  const [sceneItems, gridPayload] = await Promise.all([
    getSceneItems(),
    buildOwlbearTacticalGridPayload(),
  ]);

  const sceneItemsById = new Map(
    ensureArray(sceneItems).map((item) => [String(item?.id ?? "").trim(), item]),
  );
  const filterCharacterId = String(onlyCharacterId ?? "").trim();
  const participants = ensureArray(runtimeRes.visible_participants).filter((participant) => {
    if (!participant?.token_id || !participant?.character_id) return false;
    if (!filterCharacterId) return true;
    return String(participant.character_id ?? "").trim() === filterCharacterId;
  });

  const positions = [];
  for (const participant of participants) {
    const item = sceneItemsById.get(String(participant.token_id ?? "").trim());
    if (!item?.position) continue;
    const snapped = await snapScenePosition(item.position, 1);
    if (!snapped) continue;
    const cell = sceneToCell(gridPayload, snapped);
    if (!cell) continue;
    positions.push({
      character_id: participant.character_id,
      token_id: participant.token_id,
      cell_q: cell.q,
      cell_r: cell.r,
      scene_x: Number(snapped.x) || 0,
      scene_y: Number(snapped.y) || 0,
    });
  }

  if (!positions.length) {
    throw new Error("No linked encounter tokens were available to sync.");
  }

  const result = await combatApi.syncPositionsFromOwlbear(
    {
      encounter_id: runtimeRes.encounter.id,
      campaign_id: context.campaignId,
      room_id: context.roomId,
      scene_id: context.sceneId,
      actor_player_id: player?.id ?? "",
      actor_is_gm: true,
      ...gridPayload,
      positions,
    },
    settings,
  );

  if (!result || result.ok === false) {
    throw new Error(result?.message || result?.error || "Unable to sync tactical positions.");
  }

  return {
    result,
    positions,
    gridPayload,
    runtimeResponse: runtimeRes,
  };
}
