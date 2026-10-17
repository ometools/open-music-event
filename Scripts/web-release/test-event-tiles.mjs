import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { test } from "node:test";

// Import the exact browser module without requiring a Node package or transpiler.
const source = await readFile(new URL("../../Sources/OpenMusicEventAppViewServer/Resources/Site/assets/event-tiles.js", import.meta.url));
const { eventTileURL, loadEventTile } = await import(`data:text/javascript;base64,${source.toString("base64")}`);

async function serve(t, handler) {
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => {
    server.closeAllConnections();
    server.close(resolve);
  }));
  const url = eventTileURL(`http://127.0.0.1:${server.address().port}/map/events/6/1/1.mvt`);
  return controller => loadEventTile({ url }, controller || new AbortController());
}

test("temporary admission responses recover with exact tile bytes and cache metadata", async t => {
  let requests = 0;
  const bytes = Buffer.from([26, 2, 120, 2]);
  const load = await serve(t, (_req, res) => {
    requests += 1;
    if (requests < 4) res.writeHead(503, { "Retry-After": "0" }).end();
    else res.writeHead(200, { "Cache-Control": "public, max-age=60", "Expires": "Wed, 21 Oct 2026 07:28:00 GMT" }).end(bytes);
  });
  const result = await load();
  assert.deepEqual(Buffer.from(result.data), bytes);
  assert.equal(result.cacheControl, "public, max-age=60");
  assert.equal(result.expires, "Wed, 21 Oct 2026 07:28:00 GMT");
  assert.equal(requests, 4);
});

test("persistent admission failure stops after six attempts", async t => {
  let requests = 0;
  const load = await serve(t, (_req, res) => {
    requests += 1;
    res.writeHead(503, { "Retry-After": "0" }).end();
  });
  await assert.rejects(load(), { status: 503 });
  assert.equal(requests, 6);
});

for (const [status, headers] of [[404, {}], [500, { "Retry-After": "0" }], [503, {}], [503, { "Retry-After": "invalid" }]]) {
  test(`HTTP ${status} with ${JSON.stringify(headers)} is not retried`, async t => {
    let requests = 0;
    const load = await serve(t, (_req, res) => { requests += 1; res.writeHead(status, headers).end(); });
    await assert.rejects(load(), { status });
    assert.equal(requests, 1);
  });
}

test("MapLibre cancellation terminates an in-flight request without another attempt", async t => {
  let entered;
  const requestEntered = new Promise(resolve => { entered = resolve; });
  let requests = 0;
  const load = await serve(t, () => { requests += 1; entered(); });
  const controller = new AbortController();
  const result = load(controller);
  await requestEntered;
  controller.abort();
  await assert.rejects(result, { name: "AbortError" });
  assert.equal(requests, 1);
});

test("an already-cancelled tile performs no network request", async t => {
  let requests = 0;
  const load = await serve(t, (_req, res) => { requests += 1; res.end(); });
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(load(controller), { name: "AbortError" });
  assert.equal(requests, 0);
});

test("a Retry-After exceeding the request deadline never retries early", { timeout: 12_000 }, async t => {
  let requests = 0;
  const load = await serve(t, (_req, res) => {
    requests += 1;
    res.writeHead(503, { "Retry-After": "999999999999999999999999" }).end();
  });
  await assert.rejects(load(), { name: "TimeoutError" });
  assert.equal(requests, 1);
});
