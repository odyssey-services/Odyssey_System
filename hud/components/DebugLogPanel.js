// Combat HUD — temporary Debug Log companion popover (Phase 3D.1, ?debug=1 only).
//
// Pure render function for the `odyssey-hud-debug-log` companion popover.
// Not the user-facing Combat Log — see hud/debug/debugLogStore.js for what
// this shows and why it never persists.

import { esc, cls } from "./hudDom.js";
import { panel } from "./HudPanel.js";

function formatTime(ts) {
  try {
    const d = new Date(ts);
    return d.toLocaleTimeString(undefined, { hour12: false });
  } catch (_e) {
    return "";
  }
}

function formatDetails(details) {
  if (!details || typeof details !== "object") return "";
  const parts = Object.entries(details)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${typeof v === "object" ? JSON.stringify(v) : String(v)}`);
  return parts.join(" ");
}

function entryRow(e) {
  const details = formatDetails(e.details);
  return `<li class="${cls("ohud-debuglog-row", e.success === false ? "is-fail" : "is-ok")}">
    <span class="ohud-debuglog-time">${esc(formatTime(e.timestamp))}</span>
    <span class="ohud-debuglog-cat">${esc(e.category)}</span>
    <span class="ohud-debuglog-action">${esc(e.action)}</span>
    ${details ? `<span class="ohud-debuglog-details" title="${esc(details)}">${esc(details)}</span>` : ""}
  </li>`;
}

/** @param {Array<{timestamp:number, category:string, action:string, details:object, success:boolean}>} entries */
export function renderDebugLogPanel(entries) {
  const list = Array.isArray(entries) ? entries : [];
  const body = list.length
    ? `<ul class="ohud-debuglog-list">${list.map(entryRow).join("")}</ul>`
    : `<div class="ohud-debuglog-empty">No debug events yet.</div>`;
  return panel({
    key: "debug-log",
    label: "Debug Log",
    headerRightHtml: `<button type="button" class="ohud-debuglog-clear" data-action="clear-debug-log" aria-label="Clear debug log" title="Clear">Clear</button>`,
    bodyHtml: body,
  });
}
