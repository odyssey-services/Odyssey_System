import assert from "node:assert/strict";
import { createTestSuite } from "./_tinyTestRunner.mjs";
import {
  DRAWING_OBSTACLE_TOLERANCE_PX,
  collectOwlbearDrawingObstacles,
  findBlockingDrawingObstacleForPath,
  pointInPolygon,
  rectToPolygon,
  segmentsIntersect,
} from "../../movement/drawingObstacles.js";

const { test, run } = createTestSuite("Unit — Combat Drawing Obstacles");

const TEST_GRID = {
  gridType: "square",
  distanceMode: "chebyshev",
  gridDpi: 100,
  metersPerCell: 1,
  anchor: { x: 0, y: 0 },
};

function buildRoute(fromQ, fromR, toQ, toR) {
  const path = [];
  let q = fromQ;
  let r = fromR;
  path.push({ q, r });
  while (q !== toQ || r !== toR) {
    if (q < toQ) q += 1;
    else if (q > toQ) q -= 1;

    if (r < toR) r += 1;
    else if (r > toR) r -= 1;

    path.push({ q, r });
  }
  return path;
}

test("segmentsIntersect detects crossing lines", () => {
  assert.equal(
    segmentsIntersect(
      { x: 0, y: 0 },
      { x: 10, y: 10 },
      { x: 0, y: 10 },
      { x: 10, y: 0 },
    ),
    true,
  );
});

test("pointInPolygon detects interior point", () => {
  const polygon = rectToPolygon({ x: 20, y: 20, width: 60, height: 40 });
  assert.equal(pointInPolygon({ x: 50, y: 40 }, polygon), true);
  assert.equal(pointInPolygon({ x: 5, y: 5 }, polygon), false);
});

test("visible line blocks movement across route", () => {
  const { obstacles } = collectOwlbearDrawingObstacles([
    {
      id: "wall-line",
      type: "LINE",
      visible: true,
      startPosition: { x: 100, y: 0 },
      endPosition: { x: 100, y: 100 },
      style: { strokeWidth: 2 },
    },
  ]);

  const block = findBlockingDrawingObstacleForPath({
    path: buildRoute(0, 0, 2, 0),
    grid: TEST_GRID,
    obstacles,
  });

  assert.equal(block?.blockReason, "MOVEMENT_BLOCKED_BY_DRAWING_OBSTACLE");
  assert.equal(block?.obstacleId, "wall-line");
  assert.equal(block?.obstacleSource, "owlbear-drawing");
});

test("parallel movement outside tolerance stays allowed", () => {
  const { obstacles } = collectOwlbearDrawingObstacles([
    {
      id: "far-line",
      type: "LINE",
      visible: true,
      startPosition: { x: 100, y: 0 },
      endPosition: { x: 100, y: 100 },
      style: { strokeWidth: DRAWING_OBSTACLE_TOLERANCE_PX },
    },
  ]);

  const block = findBlockingDrawingObstacleForPath({
    path: buildRoute(0, 2, 2, 2),
    grid: TEST_GRID,
    obstacles,
  });

  assert.equal(block, null);
});

test("visible rectangle blocks route crossing", () => {
  const { obstacles } = collectOwlbearDrawingObstacles([
    {
      id: "wall-rect",
      type: "SHAPE",
      shapeType: "RECTANGLE",
      visible: true,
      position: { x: 90, y: 10 },
      width: 120,
      height: 80,
      style: { strokeWidth: 2 },
    },
  ]);

  const block = findBlockingDrawingObstacleForPath({
    path: buildRoute(0, 0, 2, 0),
    grid: TEST_GRID,
    obstacles,
  });

  assert.equal(block?.obstacleId, "wall-rect");
  assert.equal(block?.obstacleKind, "rect");
});

test("visible rectangle blocks target point inside obstacle", () => {
  const { obstacles } = collectOwlbearDrawingObstacles([
    {
      id: "solid-rect",
      type: "SHAPE",
      shapeType: "RECTANGLE",
      visible: true,
      position: { x: 110, y: 110 },
      width: 80,
      height: 80,
    },
  ]);

  const block = findBlockingDrawingObstacleForPath({
    path: buildRoute(0, 1, 1, 1),
    grid: TEST_GRID,
    obstacles,
  });

  assert.equal(block?.obstacleId, "solid-rect");
});

test("visible circle blocks movement", () => {
  const { obstacles } = collectOwlbearDrawingObstacles([
    {
      id: "circle-1",
      type: "SHAPE",
      shapeType: "CIRCLE",
      visible: true,
      position: { x: 150, y: 50 },
      width: 100,
      height: 100,
    },
  ]);

  const block = findBlockingDrawingObstacleForPath({
    path: buildRoute(0, 0, 2, 0),
    grid: TEST_GRID,
    obstacles,
  });

  assert.equal(block?.obstacleId, "circle-1");
  assert.equal(block?.obstacleKind, "circle");
});

test("visible polygon path blocks movement", () => {
  const { obstacles } = collectOwlbearDrawingObstacles([
    {
      id: "poly-1",
      type: "PATH",
      visible: true,
      closed: true,
      points: [
        { x: 120, y: 20 },
        { x: 190, y: 20 },
        { x: 160, y: 90 },
      ],
      style: { strokeWidth: 2 },
    },
  ]);

  const block = findBlockingDrawingObstacleForPath({
    path: buildRoute(0, 0, 2, 0),
    grid: TEST_GRID,
    obstacles,
  });

  assert.equal(block?.obstacleId, "poly-1");
  assert.equal(block?.obstacleKind, "polygon");
});

test("hidden drawing does not block movement", () => {
  const { obstacles, skipped } = collectOwlbearDrawingObstacles([
    {
      id: "hidden-wall",
      type: "LINE",
      visible: false,
      startPosition: { x: 100, y: 0 },
      endPosition: { x: 100, y: 100 },
    },
  ]);

  assert.equal(obstacles.length, 0);
  assert.equal(skipped[0]?.reason, "hidden");
});

test("blocksMovement false metadata opt-out is respected", () => {
  const { obstacles, skipped } = collectOwlbearDrawingObstacles(
    [
      {
        id: "soft-line",
        type: "LINE",
        visible: true,
        startPosition: { x: 100, y: 0 },
        endPosition: { x: 100, y: 100 },
        metadata: {
          "com.odyssey.movement": {
            blocksMovement: false,
          },
        },
      },
    ],
    { metadataKey: "com.odyssey.movement" },
  );

  assert.equal(obstacles.length, 0);
  assert.equal(skipped[0]?.reason, "blocks-movement-false");
});

test("moving token itself can be excluded from drawing obstacles", () => {
  const { obstacles, skipped } = collectOwlbearDrawingObstacles(
    [
      {
        id: "selected-token-preview",
        type: "LINE",
        visible: true,
        startPosition: { x: 100, y: 0 },
        endPosition: { x: 100, y: 100 },
      },
    ],
    { excludeItemIds: ["selected-token-preview"] },
  );

  assert.equal(obstacles.length, 0);
  assert.equal(skipped[0]?.reason, "excluded-item");
});

test("movement around obstacle remains allowed", () => {
  const { obstacles } = collectOwlbearDrawingObstacles([
    {
      id: "center-rect",
      type: "SHAPE",
      shapeType: "RECTANGLE",
      visible: true,
      position: { x: 110, y: 110 },
      width: 80,
      height: 80,
    },
  ]);

  const block = findBlockingDrawingObstacleForPath({
    path: buildRoute(0, 0, 0, 2),
    grid: TEST_GRID,
    obstacles,
  });

  assert.equal(block, null);
});

await run();
