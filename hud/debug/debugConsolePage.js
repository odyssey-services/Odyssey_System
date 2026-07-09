// Odyssey Debug Console — popover iframe entry (TEMPORARY, isolated bundle).
//
// Loaded by debug-console.html, built as its own esbuild entry point
// (assets/debug-console.js) — completely separate from combat-hud-overlay.js.
// A `?variant=console|launcher` URL param (set by debugConsoleController.js)
// selects what to mount. This page never imports anything from hud/overlay/,
// hud/components/, or hud/scene/ — its only shared dependency is the
// debugLogStore's data SHAPE (delivered via its own broadcast channel), not
// the store module itself.

import OBR from "@owlbear-rodeo/sdk";
import debugConsoleStyles from "./debugConsole.css";
import { renderDebugConsolePanel, renderDebugLauncher, entryKey, buildEntryCopyText, buildVisibleCopyText } from "./DebugConsolePanel.js";
import { BC_DEBUG_CONSOLE_ENTRIES, BC_DEBUG_CONSOLE_REQUEST, BC_DEBUG_CONSOLE_COMMAND } from "./debugConsoleConstants.js";

const COPY_STATUS_MS = 1500;

/** Copy text to the clipboard. Falls back to the legacy execCommand path when
 *  the async Clipboard API is unavailable/denied — either way, the same text
 *  is already visible & selectable on screen (the detail area's <pre>, or the
 *  summary rows), so manual copy always remains possible regardless. */
async function copyToClipboard(text) {
  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch (_e) { /* fall through to legacy path */ }
  try {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(ta);
    return ok;
  } catch (_e) {
    return false;
  }
}

function injectStyles() {
  if (document.getElementById("odc-styles")) return;
  const el = document.createElement("style");
  el.id = "odc-styles";
  el.textContent = debugConsoleStyles;
  document.head.appendChild(el);
}

function send(channel, data) {
  try { OBR.broadcast.sendMessage(channel, data, { destination: "LOCAL" }); } catch (_e) { /* ignore */ }
}

function getVariant() {
  try { return new URLSearchParams(window.location.search).get("variant") || "console"; } catch { return "console"; }
}

function start() {
  injectStyles();
  document.documentElement.style.background = "transparent";
  document.body.style.background = "transparent";
  document.body.style.margin = "0";

  const root = document.getElementById("root") || document.body;
  const available = !!(OBR && OBR.isAvailable);
  const variant = getVariant();

  if (variant === "launcher") {
    root.innerHTML = renderDebugLauncher();
    root.addEventListener("click", (e) => {
      if (e.target.closest('[data-odc-action="reopen"]') && available) {
        send(BC_DEBUG_CONSOLE_COMMAND, { type: "reopen" });
      }
    });
    return;
  }

  let entries = [];
  let filter = "ALL";
  let collapsed = false;
  let selectedKey = null;
  let copyStatus = null; // "event" | "visible" | null
  let copyStatusTimer = null;

  function showCopyStatus(which) {
    copyStatus = which;
    render();
    if (copyStatusTimer) clearTimeout(copyStatusTimer);
    copyStatusTimer = setTimeout(() => { copyStatus = null; render(); }, COPY_STATUS_MS);
  }

  function render() {
    // A previously-selected entry can vanish (Clear, or it aged out past the
    // store's 200-entry cap) — in that case the detail area just closes.
    if (selectedKey && !entries.some((e) => entryKey(e) === selectedKey)) selectedKey = null;
    root.innerHTML = renderDebugConsolePanel(entries, { filter, collapsed, selectedKey, copyStatus });
    const list = root.querySelector(".odc-list");
    if (list) list.scrollTop = 0; // newest-first ordering: keep the newest entry visible
  }

  root.addEventListener("click", (e) => {
    const filterBtn = e.target.closest("[data-odc-filter]");
    if (filterBtn) {
      filter = filterBtn.getAttribute("data-odc-filter") || "ALL";
      render();
      return;
    }
    const actionBtn = e.target.closest("[data-odc-action]");
    if (actionBtn) {
      const action = actionBtn.getAttribute("data-odc-action");
      if (action === "clear") {
        selectedKey = null;
        if (available) send(BC_DEBUG_CONSOLE_COMMAND, { type: "clear" });
      } else if (action === "close") {
        if (available) send(BC_DEBUG_CONSOLE_COMMAND, { type: "close" });
      } else if (action === "toggle-collapse") {
        collapsed = !collapsed;
        render();
      } else if (action === "close-details") {
        selectedKey = null;
        render();
      } else if (action === "copy-event") {
        const entry = entries.find((en) => entryKey(en) === selectedKey);
        if (entry) copyToClipboard(buildEntryCopyText(entry)).then(() => showCopyStatus("event"));
      } else if (action === "copy-visible") {
        copyToClipboard(buildVisibleCopyText(entries, filter)).then(() => showCopyStatus("visible"));
      }
      return;
    }
    const row = e.target.closest("[data-odc-row-key]");
    if (row) {
      const key = row.getAttribute("data-odc-row-key");
      selectedKey = selectedKey === key ? null : key; // click again to close
      render();
    }
  });

  if (available) {
    try {
      OBR.broadcast.onMessage(BC_DEBUG_CONSOLE_ENTRIES, (event) => {
        entries = Array.isArray(event?.data?.entries) ? event.data.entries : [];
        render();
      });
      send(BC_DEBUG_CONSOLE_REQUEST, {});
    } catch (_e) { /* standalone */ }
  }
  render();
}

if (OBR && OBR.isAvailable) {
  OBR.onReady(start);
} else {
  start();
}
