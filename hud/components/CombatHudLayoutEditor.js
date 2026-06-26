// Combat HUD — Arrange-HUD editor (Phase 2.2).
//
// A fullscreen editor (its own OBR popover) that may temporarily block the map
// while the player arranges the interface. All seven modules render as live
// preview cards at their draft rects; each card has a six-dot grip; dragging
// moves ONLY that card (CSS, no popover re-open), with 8px snap, alignment
// guides and viewport clamping. Save applies the draft to all module popovers;
// Cancel discards; Reset restores the exact designer default.
//
// Pure layout math is delegated to hud/overlay/hudLayout.js. No OBR import here.

import { createMockCombatHudAdapter } from "../adapters/mockCombatHudAdapter.js";
import { createCombatHudStore } from "../core/combatHudStore.js";
import { normalizeHudUiState } from "../overlay/overlayConstants.js";
import {
  HUD_MODULE_IDS,
  resolveModuleRect,
  pixelsToNormalized,
  clampRect,
  snapToGrid,
  computeAlignmentGuides,
  defaultLayoutState,
  normalizeLayoutState,
  setModulePlacement,
} from "../overlay/hudLayout.js";

import { renderPlayerBlock } from "./PlayerBlock.js";
import { renderGunBlock } from "./GunBlock.js";
import { renderSkillBlock } from "./SkillBlock.js";
import { renderTargetBlock } from "./TargetBlock.js";
import { renderModifierModule } from "./ModifierBlock.js";
import { renderActionModule } from "./ActionBlock.js";
import { renderBattleLogPanel } from "./BattleLogBlock.js";
import { ICON_GRIP } from "./hudIcons.js";
import { esc } from "./hudDom.js";

const BLOCK_RENDERERS = {
  player: renderPlayerBlock,
  gun: renderGunBlock,
  skills: renderSkillBlock,
  target: renderTargetBlock,
  modifiers: renderModifierModule,
  action: renderActionModule,
  log: renderBattleLogPanel,
};
const MODULE_LABEL = {
  player: "Player", gun: "Gun", skills: "Skills", target: "Target",
  modifiers: "Modifiers", action: "Action", log: "Log",
};

export function mountCombatHudLayoutEditor(options) {
  const { root } = options;
  const integration = options.integration ?? {};
  const restored = normalizeHudUiState(options.uiState);

  // Live preview store (mock, deterministic — same scenario as the modules).
  const adapter = createMockCombatHudAdapter({ scenarioId: restored.mockScenarioId });
  adapter.setViewerRole(restored.viewerRole);
  if (restored.selectedTokenId) adapter.selectToken(restored.selectedTokenId);
  const store = createCombatHudStore({ adapter });
  store.initialize();
  const state = store.getState();

  let draft = normalizeLayoutState(options.layout ?? defaultLayoutState());

  const el = document.createElement("div");
  el.className = "odyssey-hud ohud-editor-root";
  root.appendChild(el);

  function vw() { return window.innerWidth; }
  function vh() { return window.innerHeight; }

  /** Build the (static-ish) editor DOM; cards positioned from the draft. */
  function renderShell() {
    el.innerHTML = `
      <div class="ohud-editor">
        <div class="ohud-editor-toolbar">
          <span class="ohud-editor-title">Arrange HUD</span>
          <span class="ohud-editor-hint">Drag a module by its grip · snaps to 8px</span>
          <span class="ohud-editor-actions">
            <button type="button" class="ohud-editor-btn" data-editor="reset">Reset layout</button>
            <button type="button" class="ohud-editor-btn" data-editor="cancel">Cancel</button>
            <button type="button" class="ohud-editor-btn is-primary" data-editor="save">Save layout</button>
          </span>
        </div>
        <div class="ohud-editor-canvas">
          <div class="ohud-guide ohud-guide--v" hidden></div>
          <div class="ohud-guide ohud-guide--h" hidden></div>
          ${HUD_MODULE_IDS.map(cardHtml).join("")}
        </div>
      </div>`;
    for (const id of HUD_MODULE_IDS) positionCard(id);
  }

  function cardHtml(moduleId) {
    const fn = BLOCK_RENDERERS[moduleId];
    return `<div class="ohud-card ohud-module" data-module="${moduleId}" data-body="ready">
      <div class="ohud-card-bar" data-card-grip="${moduleId}">
        <span class="ohud-card-grip">${ICON_GRIP}</span>
        <span class="ohud-card-name">${esc(MODULE_LABEL[moduleId])}</span>
      </div>
      <div class="ohud-card-body">${fn ? fn(state) : ""}</div>
    </div>`;
  }

  function rectFor(moduleId) {
    return clampRect(resolveModuleRect(moduleId, draft.modules[moduleId], vw(), vh()), vw(), vh());
  }

  function positionCard(moduleId) {
    const card = el.querySelector(`.ohud-card[data-module="${moduleId}"]`);
    if (!card) return;
    const r = rectFor(moduleId);
    card.style.left = `${r.left}px`;
    card.style.top = `${r.top}px`;
    card.style.width = `${r.width}px`;
    card.style.height = `${r.height}px`;
    card.style.zIndex = String(r.zIndex);
  }

  /* ----- drag ----- */
  let drag = null;
  const guideV = () => el.querySelector(".ohud-guide--v");
  const guideH = () => el.querySelector(".ohud-guide--h");

  function otherRects(exceptId) {
    return HUD_MODULE_IDS.filter((id) => id !== exceptId).map(rectFor);
  }

  function onPointerDown(e) {
    const bar = e.target.closest("[data-card-grip]");
    if (!bar || e.button !== 0) return;
    const moduleId = bar.getAttribute("data-card-grip");
    const card = el.querySelector(`.ohud-card[data-module="${moduleId}"]`);
    e.preventDefault();
    try { bar.setPointerCapture(e.pointerId); } catch (_e) { /* ignore */ }
    const r = rectFor(moduleId);
    drag = { id: e.pointerId, moduleId, startX: e.clientX, startY: e.clientY, startLeft: r.left, startTop: r.top, w: r.width, h: r.height };
    card.classList.add("is-dragging");
  }

  function onPointerMove(e) {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.startX;
    const dy = e.clientY - drag.startY;
    let left = snapToGrid(drag.startLeft + dx);
    let top = snapToGrid(drag.startTop + dy);
    const clamped = clampRect({ left, top, width: drag.w, height: drag.h }, vw(), vh());
    left = clamped.left; top = clamped.top;

    const card = el.querySelector(`.ohud-card[data-module="${drag.moduleId}"]`);
    card.style.left = `${left}px`;
    card.style.top = `${top}px`;

    // live draft update (normalised)
    const norm = pixelsToNormalized(drag.moduleId, left, top, vw(), vh());
    draft = setModulePlacement(draft, drag.moduleId, { mode: "custom", x: norm.x, y: norm.y });

    // alignment guides vs other modules
    const guides = computeAlignmentGuides({ left, top, width: drag.w, height: drag.h }, otherRects(drag.moduleId));
    const gv = guideV(), gh = guideH();
    if (guides.vertical.length) { gv.hidden = false; gv.style.left = `${guides.vertical[0]}px`; } else gv.hidden = true;
    if (guides.horizontal.length) { gh.hidden = false; gh.style.top = `${guides.horizontal[0]}px`; } else gh.hidden = true;
  }

  function onPointerUp(e) {
    if (!drag || e.pointerId !== drag.id) return;
    const card = el.querySelector(`.ohud-card[data-module="${drag.moduleId}"]`);
    if (card) card.classList.remove("is-dragging");
    guideV().hidden = true; guideH().hidden = true;
    drag = null;
  }

  function onClick(e) {
    const t = e.target.closest("[data-editor]");
    if (!t) return;
    switch (t.getAttribute("data-editor")) {
      case "save": integration.onSave && integration.onSave(normalizeLayoutState(draft)); break;
      case "cancel": integration.onCancel && integration.onCancel(); break;
      case "reset":
        draft = defaultLayoutState();
        renderShell();
        break;
      default: break;
    }
  }

  function onResize() {
    for (const id of HUD_MODULE_IDS) positionCard(id);
  }

  el.addEventListener("pointerdown", onPointerDown);
  el.addEventListener("pointermove", onPointerMove);
  el.addEventListener("pointerup", onPointerUp);
  el.addEventListener("pointercancel", onPointerUp);
  el.addEventListener("click", onClick);
  window.addEventListener("resize", onResize);

  renderShell();

  return {
    el,
    unmount() {
      el.removeEventListener("pointerdown", onPointerDown);
      el.removeEventListener("pointermove", onPointerMove);
      el.removeEventListener("pointerup", onPointerUp);
      el.removeEventListener("pointercancel", onPointerUp);
      el.removeEventListener("click", onClick);
      window.removeEventListener("resize", onResize);
      store.dispose();
      el.remove();
    },
  };
}
