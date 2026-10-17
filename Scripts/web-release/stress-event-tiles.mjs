// Launched only by the HTTP harness against its own disposable loopback server.
import assert from "node:assert/strict";
const origin = new URL(process.argv[2]);
assert.equal(origin.hostname, "127.0.0.1");
assert.equal(origin.protocol, "http:");
const moduleResponse = await fetch(new URL("/assets/event-tiles.js", origin));
assert.equal(moduleResponse.status, 200);
const source = await moduleResponse.text();
const { eventTileURL, loadEventTile } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);
const wireStatuses = {};
const fetchHTTP = globalThis.fetch;
globalThis.fetch = async (...args) => {
  const response = await fetchHTTP(...args);
  if (String(args[0]).includes("/map/events/")) wireStatuses[response.status] = (wireStatuses[response.status] || 0) + 1;
  return response;
};
const timings = [];
let sequence = 0;
const url = index => eventTileURL(new URL(`/map/events/7/${(index * 37) % 128}/${(Math.floor(index / 128) * 17 + 64) % 128}.mvt?dates=all&catalogs=events.openmusic.event&catalogs=community.lexicon.calendar.event`, origin).href);
async function tile(index, controller = new AbortController()) {
  const start = performance.now();
  const result = await loadEventTile({ url: url(index) }, controller);
  assert(result.data instanceof ArrayBuffer);
  assert(result.data.byteLength > 0);
  timings.push((performance.now() - start) / 1000);
}
async function healthy() {
  for (const route of ["/healthz", "/readyz"]) {
    const response = await fetch(new URL(route, origin), { signal: AbortSignal.timeout(5000) });
    assert.equal(response.status, 200);
    assert.equal((await response.text()).trim(), route === "/healthz" ? "ok" : "ready");
  }
}
for (const workers of [16, 32, 64]) {
  for (let round = 0; round < 8; round += 1) {
    await Promise.all([healthy(), ...Array.from({ length: workers }, () => tile(sequence++))]);
  }
}
const controllers = Array.from({ length: 64 }, () => new AbortController());
const abandoned = controllers.map((controller, index) => tile(sequence + index, controller));
controllers.slice(0, 32).forEach(controller => controller.abort());
const outcomes = await Promise.allSettled(abandoned);
assert(outcomes.slice(0, 32).every(result => result.status === "rejected" && result.reason.name === "AbortError"));
assert(outcomes.slice(32).every(result => result.status === "fulfilled"));
await healthy();
timings.sort((a, b) => a - b);
console.log(JSON.stringify({ result: "passed", tileLoads: timings.length, cancelled: 32, wireStatuses,
  latencySeconds: Object.fromEntries([["p50", .5], ["p95", .95], ["p99", .99], ["max", 1]].map(([name, q]) => [name, timings[Math.min(timings.length - 1, Math.floor(timings.length * q))]])) }));
