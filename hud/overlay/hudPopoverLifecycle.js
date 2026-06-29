// Combat HUD - pure popover lifecycle helpers.
//
// Single source of truth for which HUD popovers should be open for a given
// mode and selection status. Kept pure so the open/close policy is testable
// without OBR, DOM, or Supabase.

import { HUD_MODULE_IDS } from "./hudLayout.js";
import {
  PRIMARY_MODULE_ID,
  SECONDARY_MODULE_IDS,
  isReadyStatus,
} from "../scene/selectionState.js";

const SECONDARY_SET = new Set(SECONDARY_MODULE_IDS);

export function moduleShouldBeOpen(mode, status, id) {
  if (mode !== "modules") return false;
  if (id === PRIMARY_MODULE_ID) return true;
  if (SECONDARY_SET.has(id)) return isReadyStatus(status);
  return true;
}

export function primaryModuleOpenMap(mode, status) {
  const map = {};
  for (const id of HUD_MODULE_IDS) {
    map[id] = moduleShouldBeOpen(mode, status, id);
  }
  return map;
}

export function secondaryReconcileAction(prevStatus, nextStatus) {
  const wasReady = isReadyStatus(prevStatus);
  const nowReady = isReadyStatus(nextStatus);
  if (wasReady === nowReady) return "none";
  return nowReady ? "open" : "close";
}

export function characterChangeClosesCompanions(prevCharId, nextCharId) {
  return (prevCharId ?? null) !== (nextCharId ?? null);
}
