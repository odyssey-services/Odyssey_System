import { buildImage, buildLine, buildText } from "@owlbear-rodeo/sdk";

export const PREVIEW_LINE_ID = "com.odyssey-system/combat-movement-preview-line";
export const PREVIEW_LABEL_ID = "com.odyssey-system/combat-movement-preview-label";
export const PREVIEW_GHOST_ID = "com.odyssey-system/combat-movement-preview-ghost";

function ensureObject(value) {
  return value && typeof value === "object" ? value : {};
}

function isImageToken(item) {
  return String(item?.type ?? "").trim().toUpperCase() === "IMAGE"
    && item?.image
    && item?.grid;
}

export function buildPreviewLabel(preview) {
  if (!preview) return "";
  const top = `${preview.moveCostM} m / ${preview.moveLimitM} m`;
  if (preview.inRange) {
    return `${top}\nRemaining: ${preview.remainingMoveM} m`;
  }
  return `${top}\nToo far`;
}

export function buildPreviewItems({ preview, originScene, selectedToken }) {
  const lineColor = preview?.inRange ? "#71f79f" : "#ff7c6d";
  const textColor = preview?.inRange ? "#d5ffe0" : "#ffd9d3";

  const line = buildLine()
    .id(PREVIEW_LINE_ID)
    .name("Combat Movement Preview")
    .layer("POINTER")
    .locked(true)
    .disableHit(true)
    .startPosition(originScene)
    .endPosition(preview.scene)
    .strokeColor(lineColor)
    .strokeOpacity(0.98)
    .strokeWidth(6)
    .strokeDash([12, 8])
    .disableAutoZIndex(true)
    .build();

  const label = buildText()
    .id(PREVIEW_LABEL_ID)
    .name("Combat Movement Label")
    .layer("TEXT")
    .locked(true)
    .disableHit(true)
    .position({ x: preview.scene.x + 12, y: preview.scene.y - 22 })
    .plainText(buildPreviewLabel(preview))
    .fontSize(18)
    .fontWeight(700)
    .padding(10)
    .textAlign("LEFT")
    .textAlignVertical("MIDDLE")
    .fillColor(textColor)
    .fillOpacity(1)
    .strokeColor("#08111f")
    .strokeOpacity(0.92)
    .strokeWidth(5)
    .build();

  let ghost = null;
  if (isImageToken(selectedToken)) {
    const token = ensureObject(selectedToken);
    ghost = buildImage(token.image, token.grid)
      .id(PREVIEW_GHOST_ID)
      .name("Combat Movement Ghost")
      .layer("CHARACTER")
      .locked(true)
      .disableHit(true)
      .disableAutoZIndex(true)
      .position(preview.scene)
      .rotation(Number(token.rotation ?? 0) || 0)
      .scale(token.scale ?? { x: 1, y: 1 })
      .visible(true)
      .metadata({})
      .text(token.text ?? { plainText: "" })
      .textItemType(token.textItemType ?? "LABEL")
      .build();
  }

  return {
    line,
    label,
    ghost,
  };
}
