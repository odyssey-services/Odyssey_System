// Combat HUD — reusable tooltip (Phase 2).
//
// One floating element per overlay. It reads `data-tip-title` / `data-tip-lines`
// from hovered descendants (event delegation) and positions itself near the
// pointer, clamped to the viewport. pointer-events:none so it never blocks
// hover/clicks. No dependencies.
//
// Note: inside the OBR popover iframe the "viewport" is the iframe rect, so the
// tooltip is clamped within the HUD bounds (documented limitation).

import { TIP_SEP } from "./hudDom.js";

const MARGIN = 8;

export function createTooltip(host) {
  const el = document.createElement("div");
  el.className = "ohud-tooltip";
  el.setAttribute("role", "tooltip");
  el.hidden = true;
  host.appendChild(el);

  let visible = false;

  function show(target) {
    const title = target.getAttribute("data-tip-title");
    if (!title) return;
    const lines = (target.getAttribute("data-tip-lines") || "")
      .split(TIP_SEP)
      .filter(Boolean);
    el.innerHTML =
      `<div class="ohud-tooltip-title">${title}</div>` +
      lines.map((l) => `<div class="ohud-tooltip-line">${l}</div>`).join("");
    el.hidden = false;
    visible = true;
  }

  function hide() {
    if (!visible) return;
    el.hidden = true;
    visible = false;
  }

  function place(x, y) {
    if (!visible) return;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const rect = el.getBoundingClientRect();
    let left = x + 14;
    let top = y - rect.height - 12; // prefer above the cursor
    if (top < MARGIN) top = y + 18;  // not enough room above → below
    left = Math.max(MARGIN, Math.min(left, vw - rect.width - MARGIN));
    top = Math.max(MARGIN, Math.min(top, vh - rect.height - MARGIN));
    el.style.left = `${Math.round(left)}px`;
    el.style.top = `${Math.round(top)}px`;
  }

  function onOver(e) {
    const target = e.target.closest("[data-tip-title]");
    if (!target || !host.contains(target)) return;
    show(target);
    place(e.clientX, e.clientY);
  }
  function onMove(e) {
    if (!visible) return;
    if (!e.target.closest("[data-tip-title]")) { hide(); return; }
    place(e.clientX, e.clientY);
  }
  function onOut(e) {
    const to = e.relatedTarget;
    if (to && to.closest && to.closest("[data-tip-title]")) return;
    hide();
  }

  host.addEventListener("mouseover", onOver);
  host.addEventListener("mousemove", onMove);
  host.addEventListener("mouseout", onOut);

  return {
    hide,
    destroy() {
      host.removeEventListener("mouseover", onOver);
      host.removeEventListener("mousemove", onMove);
      host.removeEventListener("mouseout", onOut);
      el.remove();
    },
  };
}
