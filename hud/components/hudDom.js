// Combat HUD — tiny DOM/string helpers shared by the Phase 2 components.
// No framework. Just escaping + tooltip attribute building so each block stays
// terse and safe.

import { escapeHtml } from "../../utils/json.js";

export const esc = escapeHtml;

/** Join class names, dropping falsy entries. */
export function cls(...names) {
  return names.filter(Boolean).join(" ");
}

const TIP_SEP = "‖"; // ‖ — unlikely to appear in copy; splits tooltip lines.

/**
 * Build the data-* attributes consumed by the Tooltip helper. Returns a string
 * ready to splice into a tag (leading space included), or "" when no title.
 * @param {string} title
 * @param {Array<string|null|undefined>} [lines]
 */
export function tipAttr(title, lines = []) {
  if (!title) return "";
  const body = lines.filter(Boolean).join(TIP_SEP);
  const t = esc(String(title));
  const l = esc(body);
  return ` data-tip-title="${t}"${body ? ` data-tip-lines="${l}"` : ""}`;
}

export { TIP_SEP };
