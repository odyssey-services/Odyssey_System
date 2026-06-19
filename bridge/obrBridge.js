import OBR from "@owlbear-rodeo/sdk";

let readyPromise = null;

export { OBR };

function ensureArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizePlayer(player = {}) {
  return {
    id: String(player?.id ?? "").trim(),
    name: String(player?.name ?? "").trim(),
    role: String(player?.role ?? "PLAYER").trim().toUpperCase() || "PLAYER",
    color: String(player?.color ?? "").trim(),
    selection: ensureArray(player?.selection)
      .map((value) => String(value ?? "").trim())
      .filter(Boolean),
  };
}

export function waitForObrReady() {
  if (!readyPromise) {
    readyPromise = new Promise((resolve) => {
      OBR.onReady(() => resolve(OBR));
    });
  }
  return readyPromise;
}

export async function getPlayerInfo() {
  await waitForObrReady();
  const [role, id, name, selection] = await Promise.all([
    OBR.player.getRole().catch(() => "PLAYER"),
    OBR.player.getId().catch(() => ""),
    OBR.player.getName().catch(() => ""),
    OBR.player.getSelection().catch(() => []),
  ]);
  return normalizePlayer({ role, id, name, selection });
}

export async function getSelectedTokenIds() {
  await waitForObrReady();
  const selection = await OBR.player.getSelection().catch(() => []);
  return ensureArray(selection)
    .map((value) => String(value ?? "").trim())
    .filter(Boolean);
}

export async function getSceneItems() {
  await waitForObrReady();
  return ensureArray(await OBR.scene.items.getItems().catch(() => []));
}

export async function getSelectedOwlbearTokens() {
  const [selectionIds, items] = await Promise.all([
    getSelectedTokenIds(),
    getSceneItems(),
  ]);
  const selectedSet = new Set(selectionIds);
  return items.filter((item) => selectedSet.has(String(item?.id ?? "").trim()));
}

export async function getRoomMetadata() {
  await waitForObrReady();
  return (await OBR.room.getMetadata().catch(() => ({}))) ?? {};
}

export async function setRoomMetadata(patch) {
  await waitForObrReady();
  await OBR.room.setMetadata(patch ?? {});
  return getRoomMetadata();
}

export async function getRoomSceneContext() {
  await waitForObrReady();
  const roomId = String(OBR.room?.id ?? "").trim();
  const sceneId = String(OBR.scene?.id ?? "").trim();
  return {
    campaignId: roomId,
    roomId,
    sceneId,
  };
}

export async function subscribePlayerChanges(listener) {
  await waitForObrReady();
  let active = true;
  OBR.player.onChange((player) => {
    if (!active) return;
    listener(normalizePlayer(player));
  });
  return () => {
    active = false;
  };
}

export async function subscribeSceneItems(listener) {
  await waitForObrReady();
  let active = true;
  OBR.scene.items.onChange((items) => {
    if (!active) return;
    listener(ensureArray(items));
  });
  return () => {
    active = false;
  };
}
