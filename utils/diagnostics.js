const ENTRY_LIMIT = 40;
const listeners = new Set();
let entries = [];

function notify() {
  for (const listener of listeners) {
    try {
      listener(entries.slice());
    } catch (_error) {
      // Ignore diagnostics listener failures.
    }
  }
}

export function getDiagnosticsEntries() {
  return entries.slice();
}

export function addDiagnosticEntry(level, title, details = "") {
  const entry = {
    id: `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`,
    level: String(level ?? "info").trim() || "info",
    title: String(title ?? "").trim() || "Diagnostic",
    details: String(details ?? "").trim(),
    createdAt: new Date().toISOString(),
  };
  entries = [entry, ...entries].slice(0, ENTRY_LIMIT);
  notify();
  return entry;
}

export function clearDiagnosticsEntries() {
  entries = [];
  notify();
}

export function subscribeDiagnostics(listener) {
  if (typeof listener !== "function") {
    return () => {};
  }
  listeners.add(listener);
  listener(getDiagnosticsEntries());
  return () => {
    listeners.delete(listener);
  };
}
