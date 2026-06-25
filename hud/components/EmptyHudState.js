// Combat HUD — empty / error body states (Phase 2).
//
// The HUD shell is never removed for these states (collapse/dev controls stay
// available); only the body changes. No random placeholder weapon/target data
// is shown.

import { buildEmptyStateModel } from "./hudLayoutModel.js";
import { ICON_MARK } from "./hudIcons.js";
import { esc } from "./hudDom.js";

export function renderEmptyState(state) {
  const { title, hint } = buildEmptyStateModel(state);
  return `<div class="ohud-empty">
    <span class="ohud-empty-mark" aria-hidden="true">${ICON_MARK}</span>
    <div class="ohud-empty-title">${esc(title)}</div>
    <div class="ohud-empty-hint">${esc(hint)}</div>
  </div>`;
}

export function renderErrorState(state) {
  const msg = state?.error?.message || "Something went wrong.";
  return `<div class="ohud-empty ohud-empty--error">
    <div class="ohud-empty-title">HUD ERROR</div>
    <div class="ohud-empty-hint">${esc(msg)}</div>
  </div>`;
}

export function renderLoadingState() {
  return `<div class="ohud-empty ohud-empty--loading">
    <div class="ohud-empty-title">LOADING…</div>
  </div>`;
}
