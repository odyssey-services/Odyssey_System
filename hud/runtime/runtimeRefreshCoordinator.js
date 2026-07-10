const runtimeRefreshInFlight = new Map();

export function getRuntimeRefreshInFlightCount() {
  return runtimeRefreshInFlight.size;
}

export function clearRuntimeRefreshCoordinator() {
  runtimeRefreshInFlight.clear();
}

export async function singleFlightRuntimeRefresh(key, factory, { onDeduped = null } = {}) {
  const normalizedKey = String(key ?? "").trim() || "runtime-refresh";
  if (runtimeRefreshInFlight.has(normalizedKey)) {
    if (typeof onDeduped === "function") {
      try { onDeduped(normalizedKey); } catch (_error) { /* ignore observer errors */ }
    }
    return runtimeRefreshInFlight.get(normalizedKey);
  }

  const promise = Promise.resolve()
    .then(() => factory())
    .finally(() => {
      if (runtimeRefreshInFlight.get(normalizedKey) === promise) {
        runtimeRefreshInFlight.delete(normalizedKey);
      }
    });

  runtimeRefreshInFlight.set(normalizedKey, promise);
  return promise;
}

export function createDebouncedRefreshScheduler(callback, delayMs = 200) {
  let timer = null;
  let lastArgs = [];

  function cancel() {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  }

  async function flush() {
    if (!lastArgs.length) return null;
    cancel();
    return callback(...lastArgs);
  }

  function schedule(...args) {
    lastArgs = args;
    cancel();
    timer = setTimeout(() => {
      const runArgs = lastArgs.slice();
      timer = null;
      void Promise.resolve(callback(...runArgs)).catch(() => {});
    }, Math.max(0, Number(delayMs) || 0));
  }

  return {
    schedule,
    flush,
    cancel,
    isScheduled: () => timer !== null,
  };
}
