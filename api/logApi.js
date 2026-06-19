import { fetchSupabaseRows } from "../bridge/supabaseBridge.js";

export function getCombatLogEntries(
  { roomId = "", encounterId = "", limit = 50 } = {},
  settings,
) {
  const safeLimit = Math.max(1, Math.min(Number(limit) || 50, 200));
  const params = [
    "select=id,created_at,event_type,message,data,actor_character_id,target_character_id,room_id,scene_id,encounter_id",
    "order=created_at.desc",
    `limit=${safeLimit}`,
  ];
  if (roomId) {
    params.push(`room_id=eq.${encodeURIComponent(String(roomId).trim())}`);
  }
  if (encounterId) {
    params.push(`encounter_id=eq.${encodeURIComponent(String(encounterId).trim())}`);
  }
  return fetchSupabaseRows(
    `odyssey_combat_log?${params.join("&")}`,
    settings,
    "Unable to load combat log rows.",
  );
}
