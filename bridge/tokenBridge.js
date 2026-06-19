import { TOKEN_LINK_KEY, normalizeTokenCharacterLink } from "../constants/metadataKeys.js";
import { OBR, getSelectedOwlbearTokens, waitForObrReady } from "./obrBridge.js";

function resolveTokenId(tokenOrId) {
  if (typeof tokenOrId === "string") {
    return tokenOrId.trim();
  }
  return String(tokenOrId?.id ?? "").trim();
}

export function getTokenCharacterLink(token) {
  return normalizeTokenCharacterLink(token?.metadata?.[TOKEN_LINK_KEY]);
}

export async function setTokenCharacterLink(tokenOrId, characterId, fields = {}) {
  await waitForObrReady();
  const tokenId = resolveTokenId(tokenOrId);
  const normalized = normalizeTokenCharacterLink({
    characterId,
    ...fields,
    updatedAt: fields.updatedAt ?? new Date().toISOString(),
  });
  await OBR.scene.items.updateItems([tokenId], (items) => {
    for (const item of items) {
      item.metadata ??= {};
      item.metadata[TOKEN_LINK_KEY] = normalized;
    }
  });
  return normalized;
}

export async function clearTokenCharacterLink(tokenOrId) {
  await waitForObrReady();
  const tokenId = resolveTokenId(tokenOrId);
  await OBR.scene.items.updateItems([tokenId], (items) => {
    for (const item of items) {
      item.metadata ??= {};
      delete item.metadata[TOKEN_LINK_KEY];
    }
  });
}

export async function getSelectedTokenCharacterLinks() {
  const tokens = await getSelectedOwlbearTokens();
  return tokens.map((token) => ({
    token,
    link: getTokenCharacterLink(token),
  }));
}
