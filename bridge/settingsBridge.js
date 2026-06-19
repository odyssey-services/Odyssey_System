import { ROOM_SUPABASE_SETTINGS_KEY } from "../constants/metadataKeys.js";
import { getRoomMetadata, setRoomMetadata } from "./obrBridge.js";

export function normalizeSupabaseSettings(raw) {
  return {
    url: String(raw?.url ?? "").trim().replace(/\/+$/, ""),
    apiKey: String(raw?.apiKey ?? raw?.anonKey ?? "").trim(),
  };
}

export function hasSupabaseSettings(settings) {
  const normalized = normalizeSupabaseSettings(settings);
  return Boolean(normalized.url && normalized.apiKey);
}

export function maskSupabaseApiKey(value) {
  const normalized = String(value ?? "").trim();
  if (normalized.length <= 10) {
    return normalized ? "********" : "";
  }
  return `${normalized.slice(0, 6)}...${normalized.slice(-4)}`;
}

export async function loadRoomSupabaseSettings() {
  const metadata = await getRoomMetadata();
  return normalizeSupabaseSettings(metadata?.[ROOM_SUPABASE_SETTINGS_KEY]);
}

export async function saveRoomSupabaseSettings(settings) {
  const normalized = normalizeSupabaseSettings(settings);
  await setRoomMetadata({
    [ROOM_SUPABASE_SETTINGS_KEY]: normalized,
  });
  return normalized;
}

export async function clearRoomSupabaseSettings() {
  return saveRoomSupabaseSettings({
    url: "",
    apiKey: "",
  });
}
