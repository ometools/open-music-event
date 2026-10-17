// Only OME vector tiles use this protocol; basemap requests retain MapLibre's loader.
export const EVENT_TILE_PROTOCOL = "ome-event-tile";
export const eventTileURL = url => `${EVENT_TILE_PROTOCOL}://${url}`;

function waitForRetry(milliseconds, signal) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const cancel = () => {
      clearTimeout(timer);
      reject(signal.reason);
    };
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", cancel);
      resolve();
    }, milliseconds);
    signal.addEventListener("abort", cancel, { once: true });
  });
}

export async function loadEventTile(parameters, abortController) {
  const prefix = `${EVENT_TILE_PROTOCOL}://`;
  if (!parameters.url.startsWith(prefix)) throw new Error("Invalid event tile protocol");
  const url = parameters.url.slice(prefix.length);
  // Each request owns its deadline and cancellation. No shared mutable retry state.
  const controller = new AbortController();
  const signal = controller.signal;
  const cancel = () => controller.abort(abortController.signal.reason);
  abortController.signal.throwIfAborted();
  abortController.signal.addEventListener("abort", cancel, { once: true });
  const deadline = setTimeout(() => controller.abort(new DOMException("Event tile deadline exceeded", "TimeoutError")), 10_000);
  try {
    for (let attempt = 0; attempt < 6; attempt += 1) {
      signal.throwIfAborted();
      const response = await fetch(url, {
        signal,
        headers: parameters.headers,
        cache: parameters.cache,
        credentials: parameters.credentials || "same-origin",
      });
      if (response.ok) {
        const data = await response.arrayBuffer();
        signal.throwIfAborted();
        return {
          data,
          cacheControl: response.headers.get("Cache-Control") || undefined,
          expires: response.headers.get("Expires") || undefined,
        };
      }
      const retryAfter = response.headers.get("Retry-After");
      await response.body?.cancel();
      // Retry only explicit temporary admission pressure, never arbitrary failures.
      if (response.status !== 503 || retryAfter === null || !/^\d+$/.test(retryAfter) || attempt === 5) {
        throw Object.assign(new Error(`Event tile HTTP ${response.status}`), { status: response.status, url });
      }
      await waitForRetry(Math.min(10_000, Number(retryAfter) * 1000), signal);
    }
  } finally {
    clearTimeout(deadline);
    abortController.signal.removeEventListener("abort", cancel);
  }
}
