import { createClient } from "@supabase/supabase-js";

let _client = null;
let _url = "";
let _key = "";

// Returns a Supabase client configured for Real-Time only.
// Re-creates the client if url/key changed (e.g. settings updated).
export function getRealtimeClient(settings) {
  const url = settings?.url ?? "";
  const key = settings?.apiKey ?? settings?.key ?? "";
  if (!url || !key) return null;
  if (_client && url === _url && key === _key) return _client;
  if (_client) {
    _client.removeAllChannels();
    _client = null;
  }
  _url = url;
  _key = key;
  _client = createClient(url, key, {
    realtime: { params: { eventsPerSecond: 10 } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return _client;
}
