// Combat HUD — panel frame (Phase 2).
//
// Pure string builder for a module panel: a small muted top-left label plus a
// body. Used by every block so spacing, borders and the header treatment stay
// consistent. No DOM, no store.

import { esc, cls } from "./hudDom.js";

/**
 * @param {{
 *   key:string,            // data-block id (player|gun|skills|target|action|log)
 *   label?:string,         // small header caption
 *   accent?:string,        // accent class suffix for the label (attack|psionic|…)
 *   bodyHtml:string,       // inner markup
 *   className?:string,     // extra classes on the panel
 *   headerRightHtml?:string,
 * }} cfg
 * @returns {string}
 */
export function panel(cfg) {
  const { key, label, accent, bodyHtml, className, headerRightHtml } = cfg;
  const header = (label || headerRightHtml)
    ? `<div class="ohud-panel-head">
         ${label ? `<span class="ohud-panel-label ${accent ? `ohud-accent--${accent}` : ""}">${esc(label)}</span>` : "<span></span>"}
         ${headerRightHtml ?? ""}
       </div>`
    : "";
  return `<section class="${cls("ohud-panel", `ohud-panel--${key}`, className)}" data-block="${esc(key)}">
    ${header}
    <div class="ohud-panel-body">${bodyHtml}</div>
  </section>`;
}
