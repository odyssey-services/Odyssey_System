import { cellToScene } from "./gridMath.js";

export const DRAWING_OBSTACLE_TOLERANCE_PX = 4;
export const MOVEMENT_COLLISION_EPSILON = 0.001;

function toNumber(value, fallback = 0) {
  const normalized = Number(value);
  return Number.isFinite(normalized) ? normalized : fallback;
}

function normalizePoint(raw) {
  if (!raw || typeof raw !== "object") return null;
  const x = toNumber(raw.x, NaN);
  const y = toNumber(raw.y, NaN);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
  return { x, y };
}

function normalizeScale(scale) {
  return {
    x: Math.abs(toNumber(scale?.x, 1)) || 1,
    y: Math.abs(toNumber(scale?.y, 1)) || 1,
  };
}

function getStrokeWidth(item) {
  return Math.max(
    0,
    toNumber(
      item?.style?.strokeWidth
      ?? item?.strokeWidth
      ?? item?.style?.lineWidth
      ?? item?.lineWidth,
      0,
    ),
  );
}

function getMovementMetadata(item, metadataKey) {
  const raw = item?.metadata?.[metadataKey];
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : null;
}

function normalizeShapeType(item) {
  return String(item?.shapeType ?? item?.shape_type ?? "").trim().toUpperCase();
}

function normalizeItemType(item) {
  return String(item?.type ?? "").trim().toUpperCase();
}

function isHidden(item) {
  return item?.visible === false;
}

function rotatePoint(point, center, rotationRadians = 0) {
  if (!rotationRadians) return { x: point.x, y: point.y };
  const cos = Math.cos(rotationRadians);
  const sin = Math.sin(rotationRadians);
  const dx = point.x - center.x;
  const dy = point.y - center.y;
  return {
    x: center.x + dx * cos - dy * sin,
    y: center.y + dx * sin + dy * cos,
  };
}

function getBoundsCenter(bounds) {
  return {
    x: bounds.x + bounds.width / 2,
    y: bounds.y + bounds.height / 2,
  };
}

function transformPolygon(points, { center, rotationRadians = 0, scale = { x: 1, y: 1 } }) {
  return points.map((point) => {
    const scaled = {
      x: center.x + (point.x - center.x) * scale.x,
      y: center.y + (point.y - center.y) * scale.y,
    };
    return rotatePoint(scaled, center, rotationRadians);
  });
}

function getRectBoundsFromItem(item) {
  const width = Math.abs(toNumber(item?.width, 0) * Math.abs(toNumber(item?.scale?.x, 1) || 1));
  const height = Math.abs(toNumber(item?.height, 0) * Math.abs(toNumber(item?.scale?.y, 1) || 1));
  const position = normalizePoint(item?.position);
  if (!position || width <= 0 || height <= 0) return null;
  return {
    x: position.x,
    y: position.y,
    width,
    height,
  };
}

export function rectToPolygon(bounds, rotationDegrees = 0) {
  if (!bounds) return [];
  const points = [
    { x: bounds.x, y: bounds.y },
    { x: bounds.x + bounds.width, y: bounds.y },
    { x: bounds.x + bounds.width, y: bounds.y + bounds.height },
    { x: bounds.x, y: bounds.y + bounds.height },
  ];
  const center = getBoundsCenter(bounds);
  return transformPolygon(points, {
    center,
    rotationRadians: (toNumber(rotationDegrees, 0) * Math.PI) / 180,
  });
}

function regularPolygonPoints({ center, radiusX, radiusY, sides, rotationRadians = 0 }) {
  const pointCount = Math.max(3, Math.round(toNumber(sides, 3)));
  const points = [];
  for (let index = 0; index < pointCount; index += 1) {
    const angle = rotationRadians + (Math.PI * 2 * index) / pointCount - Math.PI / 2;
    points.push({
      x: center.x + Math.cos(angle) * radiusX,
      y: center.y + Math.sin(angle) * radiusY,
    });
  }
  return points;
}

export function ellipseToPolygon(center, radiusX, radiusY, segments = 32, rotationDegrees = 0) {
  if (!center || !(radiusX > 0) || !(radiusY > 0)) return [];
  const base = regularPolygonPoints({
    center,
    radiusX,
    radiusY,
    sides: Math.max(12, Math.round(toNumber(segments, 32))),
  });
  return transformPolygon(base, {
    center,
    rotationRadians: (toNumber(rotationDegrees, 0) * Math.PI) / 180,
  });
}

function normalizeRawPoints(rawPoints) {
  if (!Array.isArray(rawPoints)) return [];
  const points = [];
  for (const entry of rawPoints) {
    if (Array.isArray(entry) && entry.length >= 2) {
      const x = toNumber(entry[0], NaN);
      const y = toNumber(entry[1], NaN);
      if (Number.isFinite(x) && Number.isFinite(y)) points.push({ x, y });
      continue;
    }
    const point = normalizePoint(entry);
    if (point) points.push(point);
  }
  return points;
}

function rawPointsFromItem(item) {
  const arrays = [
    item?.points,
    item?.path,
    item?.vertices,
    Array.isArray(item?.commands)
      ? item.commands.map((command) => normalizePoint(command)).filter(Boolean)
      : null,
  ];
  for (const candidate of arrays) {
    const points = normalizeRawPoints(candidate);
    if (points.length >= 2) return points;
  }
  return [];
}

function maybeOffsetLocalPoints(points, item) {
  if (!points.length) return points;
  const position = normalizePoint(item?.position);
  if (!position) return points;

  const width = Math.abs(toNumber(item?.width, 0));
  const height = Math.abs(toNumber(item?.height, 0));
  const xs = points.map((point) => point.x);
  const ys = points.map((point) => point.y);
  const spanX = Math.max(...xs) - Math.min(...xs);
  const spanY = Math.max(...ys) - Math.min(...ys);
  const localLike = width > 0 && height > 0
    ? spanX <= width * 1.5 + MOVEMENT_COLLISION_EPSILON
      && spanY <= height * 1.5 + MOVEMENT_COLLISION_EPSILON
    : Math.max(...xs.map((value) => Math.abs(value)), 0) < 500
      && Math.max(...ys.map((value) => Math.abs(value)), 0) < 500;

  if (!localLike) return points;
  return points.map((point) => ({
    x: point.x + position.x,
    y: point.y + position.y,
  }));
}

function normalizePathPoints(item) {
  return maybeOffsetLocalPoints(rawPointsFromItem(item), item);
}

function closePolygon(points) {
  if (points.length < 3) return points;
  const first = points[0];
  const last = points[points.length - 1];
  if (
    Math.abs(first.x - last.x) <= MOVEMENT_COLLISION_EPSILON
    && Math.abs(first.y - last.y) <= MOVEMENT_COLLISION_EPSILON
  ) {
    return points.slice(0, -1);
  }
  return points;
}

function obstacleFromLineItem(item, metadataKey) {
  const start = normalizePoint(item?.startPosition);
  const end = normalizePoint(item?.endPosition);
  if (!start || !end) return null;
  return {
    id: String(item?.id ?? "").trim(),
    source: "owlbear-drawing",
    sourceType: "LINE",
    obstacleKind: "line",
    kind: "segment",
    points: [start, end],
    strokeWidth: getStrokeWidth(item),
    tolerance: Math.max(getStrokeWidth(item) / 2, DRAWING_OBSTACLE_TOLERANCE_PX),
    metadata: getMovementMetadata(item, metadataKey),
    blocksMovement: true,
  };
}

function obstacleFromRectItem(item, metadataKey) {
  const bounds = getRectBoundsFromItem(item);
  if (!bounds) return null;
  const points = rectToPolygon(bounds, toNumber(item?.rotation, 0));
  if (points.length < 4) return null;
  return {
    id: String(item?.id ?? "").trim(),
    source: "owlbear-drawing",
    sourceType: "SHAPE",
    obstacleKind: "rect",
    kind: "polygon",
    points,
    strokeWidth: getStrokeWidth(item),
    tolerance: Math.max(getStrokeWidth(item) / 2, DRAWING_OBSTACLE_TOLERANCE_PX),
    metadata: getMovementMetadata(item, metadataKey),
    blocksMovement: true,
  };
}

function obstacleFromEllipseItem(item, metadataKey, obstacleKind = "ellipse") {
  const position = normalizePoint(item?.position);
  const width = Math.abs(toNumber(item?.width, 0));
  const height = Math.abs(toNumber(item?.height, 0));
  const scale = normalizeScale(item?.scale);
  if (!position || width <= 0 || height <= 0) return null;
  const points = ellipseToPolygon(
    position,
    (width * scale.x) / 2,
    (height * scale.y) / 2,
    32,
    toNumber(item?.rotation, 0),
  );
  if (points.length < 3) return null;
  return {
    id: String(item?.id ?? "").trim(),
    source: "owlbear-drawing",
    sourceType: "SHAPE",
    obstacleKind,
    kind: "polygon",
    points,
    strokeWidth: getStrokeWidth(item),
    tolerance: Math.max(getStrokeWidth(item) / 2, DRAWING_OBSTACLE_TOLERANCE_PX),
    metadata: getMovementMetadata(item, metadataKey),
    blocksMovement: true,
  };
}

function obstacleFromRegularPolygonItem(item, metadataKey, sides, obstacleKind = "polygon") {
  const position = normalizePoint(item?.position);
  const width = Math.abs(toNumber(item?.width, 0));
  const height = Math.abs(toNumber(item?.height, 0));
  const scale = normalizeScale(item?.scale);
  if (!position || width <= 0 || height <= 0) return null;
  const center = {
    x: position.x + (width * scale.x) / 2,
    y: position.y + (height * scale.y) / 2,
  };
  const points = regularPolygonPoints({
    center,
    radiusX: (width * scale.x) / 2,
    radiusY: (height * scale.y) / 2,
    sides,
    rotationRadians: (toNumber(item?.rotation, 0) * Math.PI) / 180,
  });
  if (points.length < 3) return null;
  return {
    id: String(item?.id ?? "").trim(),
    source: "owlbear-drawing",
    sourceType: "SHAPE",
    obstacleKind,
    kind: "polygon",
    points,
    strokeWidth: getStrokeWidth(item),
    tolerance: Math.max(getStrokeWidth(item) / 2, DRAWING_OBSTACLE_TOLERANCE_PX),
    metadata: getMovementMetadata(item, metadataKey),
    blocksMovement: true,
  };
}

function obstacleFromPathItem(item, metadataKey) {
  const points = normalizePathPoints(item);
  if (points.length < 2) return null;
  const closed = item?.closed === true || item?.isClosed === true;
  return {
    id: String(item?.id ?? "").trim(),
    source: "owlbear-drawing",
    sourceType: normalizeItemType(item),
    obstacleKind: closed ? "polygon" : "polyline",
    kind: closed ? "polygon" : "polyline",
    points: closed ? closePolygon(points) : points,
    strokeWidth: getStrokeWidth(item),
    tolerance: Math.max(getStrokeWidth(item) / 2, DRAWING_OBSTACLE_TOLERANCE_PX),
    metadata: getMovementMetadata(item, metadataKey),
    blocksMovement: true,
  };
}

function obstacleFromPolygonShapeItem(item, metadataKey) {
  const points = closePolygon(normalizePathPoints(item));
  if (points.length >= 3) {
    return {
      id: String(item?.id ?? "").trim(),
      source: "owlbear-drawing",
      sourceType: "SHAPE",
      obstacleKind: "polygon",
      kind: "polygon",
      points,
      strokeWidth: getStrokeWidth(item),
      tolerance: Math.max(getStrokeWidth(item) / 2, DRAWING_OBSTACLE_TOLERANCE_PX),
      metadata: getMovementMetadata(item, metadataKey),
      blocksMovement: true,
    };
  }
  return obstacleFromRegularPolygonItem(item, metadataKey, 6, "polygon");
}

function shouldTreatAsDrawingObstacle(item, metadataKey, excludeItemIds) {
  const itemId = String(item?.id ?? "").trim();
  if (!itemId) return { ok: false, reason: "missing-id" };
  if (excludeItemIds.has(itemId)) return { ok: false, reason: "excluded-item" };
  if (isHidden(item)) return { ok: false, reason: "hidden" };
  const type = normalizeItemType(item);
  if (!["LINE", "SHAPE", "PATH"].includes(type)) return { ok: false, reason: "unsupported-type" };
  const metadata = getMovementMetadata(item, metadataKey);
  if (metadata?.blocksMovement === false) return { ok: false, reason: "blocks-movement-false" };
  return { ok: true, type };
}

function buildObstacleFromItem(item, metadataKey) {
  const type = normalizeItemType(item);
  if (type === "LINE") return obstacleFromLineItem(item, metadataKey);
  if (type === "PATH") return obstacleFromPathItem(item, metadataKey);
  if (type === "SHAPE") {
    const shapeType = normalizeShapeType(item);
    if (shapeType === "RECTANGLE") return obstacleFromRectItem(item, metadataKey);
    if (shapeType === "CIRCLE") return obstacleFromEllipseItem(item, metadataKey, "circle");
    if (shapeType === "ELLIPSE") return obstacleFromEllipseItem(item, metadataKey, "ellipse");
    if (shapeType === "TRIANGLE") return obstacleFromRegularPolygonItem(item, metadataKey, 3, "polygon");
    if (shapeType === "HEXAGON") return obstacleFromRegularPolygonItem(item, metadataKey, 6, "polygon");
    if (shapeType === "PENTAGON") return obstacleFromRegularPolygonItem(item, metadataKey, 5, "polygon");
    if (shapeType === "OCTAGON") return obstacleFromRegularPolygonItem(item, metadataKey, 8, "polygon");
    return obstacleFromPolygonShapeItem(item, metadataKey);
  }
  return null;
}

export function collectOwlbearDrawingObstacles(sceneItems, options = {}) {
  const excludeItemIds = new Set(
    Array.isArray(options?.excludeItemIds)
      ? options.excludeItemIds.map((value) => String(value ?? "").trim()).filter(Boolean)
      : [],
  );
  const metadataKey = String(options?.metadataKey ?? "").trim();
  const obstacles = [];
  const skipped = [];

  for (const item of Array.isArray(sceneItems) ? sceneItems : []) {
    const eligibility = shouldTreatAsDrawingObstacle(item, metadataKey, excludeItemIds);
    if (!eligibility.ok) {
      skipped.push({
        itemId: String(item?.id ?? "").trim(),
        type: normalizeItemType(item),
        reason: eligibility.reason,
      });
      continue;
    }
    const obstacle = buildObstacleFromItem(item, metadataKey);
    if (!obstacle) {
      skipped.push({
        itemId: String(item?.id ?? "").trim(),
        type: eligibility.type,
        reason: "geometry-unresolved",
      });
      continue;
    }
    obstacles.push(obstacle);
  }

  return { obstacles, skipped };
}

export function distancePointToSegment(point, a, b) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  if (Math.abs(dx) <= MOVEMENT_COLLISION_EPSILON && Math.abs(dy) <= MOVEMENT_COLLISION_EPSILON) {
    return Math.hypot(point.x - a.x, point.y - a.y);
  }
  const t = Math.max(
    0,
    Math.min(
      1,
      ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy),
    ),
  );
  const projection = {
    x: a.x + dx * t,
    y: a.y + dy * t,
  };
  return Math.hypot(point.x - projection.x, point.y - projection.y);
}

function orientation(a, b, c) {
  const value = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y);
  if (Math.abs(value) <= MOVEMENT_COLLISION_EPSILON) return 0;
  return value > 0 ? 1 : 2;
}

function onSegment(a, b, c) {
  return b.x <= Math.max(a.x, c.x) + MOVEMENT_COLLISION_EPSILON
    && b.x + MOVEMENT_COLLISION_EPSILON >= Math.min(a.x, c.x)
    && b.y <= Math.max(a.y, c.y) + MOVEMENT_COLLISION_EPSILON
    && b.y + MOVEMENT_COLLISION_EPSILON >= Math.min(a.y, c.y);
}

export function segmentsIntersect(a1, a2, b1, b2) {
  const o1 = orientation(a1, a2, b1);
  const o2 = orientation(a1, a2, b2);
  const o3 = orientation(b1, b2, a1);
  const o4 = orientation(b1, b2, a2);

  if (o1 !== o2 && o3 !== o4) return true;
  if (o1 === 0 && onSegment(a1, b1, a2)) return true;
  if (o2 === 0 && onSegment(a1, b2, a2)) return true;
  if (o3 === 0 && onSegment(b1, a1, b2)) return true;
  if (o4 === 0 && onSegment(b1, a2, b2)) return true;
  return false;
}

export function segmentNearSegment(a1, a2, b1, b2, tolerance = 0) {
  if (segmentsIntersect(a1, a2, b1, b2)) return true;
  const limit = Math.max(0, toNumber(tolerance, 0));
  if (limit <= MOVEMENT_COLLISION_EPSILON) return false;
  return distancePointToSegment(a1, b1, b2) <= limit + MOVEMENT_COLLISION_EPSILON
    || distancePointToSegment(a2, b1, b2) <= limit + MOVEMENT_COLLISION_EPSILON
    || distancePointToSegment(b1, a1, a2) <= limit + MOVEMENT_COLLISION_EPSILON
    || distancePointToSegment(b2, a1, a2) <= limit + MOVEMENT_COLLISION_EPSILON;
}

export function pointInPolygon(point, polygon) {
  if (!point || !Array.isArray(polygon) || polygon.length < 3) return false;
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const pi = polygon[i];
    const pj = polygon[j];
    if (distancePointToSegment(point, pj, pi) <= MOVEMENT_COLLISION_EPSILON) {
      return true;
    }
    const intersects = ((pi.y > point.y) !== (pj.y > point.y))
      && (
        point.x
        < ((pj.x - pi.x) * (point.y - pi.y)) / ((pj.y - pi.y) || MOVEMENT_COLLISION_EPSILON) + pi.x
      );
    if (intersects) inside = !inside;
  }
  return inside;
}

export function segmentIntersectsPolygon(segmentStart, segmentEnd, polygon, tolerance = 0) {
  if (!segmentStart || !segmentEnd || !Array.isArray(polygon) || polygon.length < 3) return false;
  for (let index = 0; index < polygon.length; index += 1) {
    const from = polygon[index];
    const to = polygon[(index + 1) % polygon.length];
    if (segmentNearSegment(segmentStart, segmentEnd, from, to, tolerance)) {
      return true;
    }
  }
  return pointInPolygon(segmentEnd, polygon);
}

export function segmentIntersectsCircle(segmentStart, segmentEnd, center, radius) {
  if (!segmentStart || !segmentEnd || !center || !(radius > 0)) return false;
  return distancePointToSegment(center, segmentStart, segmentEnd) <= radius + MOVEMENT_COLLISION_EPSILON;
}

function summarizeObstacleGeometry(obstacle) {
  if (!obstacle) return null;
  return {
    pointCount: Array.isArray(obstacle.points) ? obstacle.points.length : 0,
    tolerance: Math.max(0, toNumber(obstacle.tolerance, 0)),
  };
}

function buildRouteBlock(stepCell, obstacle, stepIndex) {
  return {
    blockedCell: {
      q: Number(stepCell?.q ?? stepCell?.cell_q ?? 0) || 0,
      r: Number(stepCell?.r ?? stepCell?.cell_r ?? 0) || 0,
    },
    blockReason: "MOVEMENT_BLOCKED_BY_DRAWING_OBSTACLE",
    obstacleId: String(obstacle?.id ?? "").trim(),
    obstacleKind: String(obstacle?.obstacleKind ?? obstacle?.kind ?? "").trim(),
    obstacleSource: "owlbear-drawing",
    obstacleGeometry: summarizeObstacleGeometry(obstacle),
    stepIndex: Number(stepIndex ?? 0) || 0,
  };
}

export function findBlockingDrawingObstacleForPath({ path, grid, obstacles }) {
  if (!Array.isArray(path) || path.length <= 1 || !grid || !Array.isArray(obstacles) || !obstacles.length) {
    return null;
  }

  for (let index = 1; index < path.length; index += 1) {
    const fromCell = path[index - 1];
    const toCell = path[index];
    const fromScene = cellToScene(grid, fromCell);
    const toScene = cellToScene(grid, toCell);
    if (!fromScene || !toScene) continue;

    for (const obstacle of obstacles) {
      if (!obstacle?.blocksMovement) continue;
      const points = Array.isArray(obstacle.points) ? obstacle.points : [];
      const tolerance = Math.max(0, toNumber(obstacle.tolerance, 0));
      if (obstacle.kind === "segment" && points.length >= 2) {
        if (segmentNearSegment(fromScene, toScene, points[0], points[1], tolerance)) {
          return buildRouteBlock(toCell, obstacle, index);
        }
        continue;
      }
      if (obstacle.kind === "polyline" && points.length >= 2) {
        for (let pointIndex = 1; pointIndex < points.length; pointIndex += 1) {
          if (segmentNearSegment(fromScene, toScene, points[pointIndex - 1], points[pointIndex], tolerance)) {
            return buildRouteBlock(toCell, obstacle, index);
          }
        }
        continue;
      }
      if (obstacle.kind === "polygon" && points.length >= 3) {
        if (segmentIntersectsPolygon(fromScene, toScene, points, tolerance)) {
          return buildRouteBlock(toCell, obstacle, index);
        }
      }
    }
  }

  return null;
}
