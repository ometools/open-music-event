// API measurements are separate from browser-rendering measurements.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const http = require('node:http');
const https = require('node:https');
const { gunzipSync } = require('node:zlib');
const base = process.env.OME_GLOBE_URL || 'http://127.0.0.1:18081';
const output = process.env.OME_GLOBE_REPORT_DIR || '.build/globe-map-validation/local-sandbox';
const catalogs = 'catalogs=events.openmusic.event&catalogs=community.lexicon.calendar.event';

function request(path, headers = {}) {
  return new Promise((resolve, reject) => {
    const started = performance.now(), url = new URL(path, base);
    const transport = url.protocol === 'https:' ? https : http;
    const req = transport.get(url, { headers: { 'accept-encoding': 'gzip', ...headers } }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('error', reject);
      response.on('end', () => {
        const encoded = Buffer.concat(chunks);
        resolve({ status: response.statusCode, headers: response.headers,
          milliseconds: performance.now() - started, encodedBytes: encoded.length,
          body: encoded.length && response.headers['content-encoding'] === 'gzip' ? gunzipSync(encoded) : encoded });
      });
    });
    req.setTimeout(30000, () => req.destroy(new Error('Local API request timed out')));
    req.on('error', reject);
  });
}

(async () => {
  for (const path of ['/', '/about', '/healthz']) assert.equal((await request(path)).status, 200);
  assert.equal((await request('/xrpc/app.openmusicevent.calendar.getMapItems')).status, 404);
  for (const query of ['limit=51', 'cursor=invalid', 'north=45']) {
    assert.equal((await request(`/xrpc/app.openmusicevent.calendar.browseEventSummaries?${catalogs}&${query}`)).status, 400);
  }
  const queries = {
    list: `/xrpc/app.openmusicevent.calendar.browseEventSummaries?${catalogs}&dates=current&limit=50`,
    search: `/xrpc/app.openmusicevent.calendar.browseEventSummaries?${catalogs}&dates=current&limit=50&query=music`,
    tile: `/map/events/0/0/0.mvt?${catalogs}&dates=current`,
  };
  const reports = [];
  for (const [name, path] of Object.entries(queries)) {
    const samples = [];
    let response;
    for (let index = 0; index < 20; index++) {
      response = await request(path);
      assert.equal(response.status, 200);
      samples.push(response.milliseconds);
    }
    const sorted = [...samples].sort((a, b) => a - b);
    if (name === 'tile') {
      assert.equal(response.headers['content-encoding'], 'gzip');
      assert.equal((await request(path, { 'if-none-match': response.headers.etag })).status, 304);
    } else {
      assert.equal(JSON.parse(response.body).events.length, 50);
    }
    reports.push({ name, samples, medianMilliseconds: (sorted[9] + sorted[10]) / 2,
      p95Milliseconds: sorted[18], encodedBytes: response.encodedBytes,
      decodedBytes: response.body.length, encoding: response.headers['content-encoding'] || 'identity',
      serverTiming: response.headers['server-timing'] || null });
  }
  for (const catalog of ['events.openmusic.event', 'community.lexicon.calendar.event']) {
    const response = await request(`/xrpc/app.openmusicevent.calendar.browseEventSummaries?catalogs=${catalog}&dates=all&limit=50`);
    assert.equal(response.status, 200);
    const page = JSON.parse(response.body);
    assert(page.events.length > 0 && page.events.every(event => event.catalog === catalog));
  }
  await fs.mkdir(output, { recursive: true });
  await fs.writeFile(`${output}/http-results.json`, JSON.stringify({ base, recordedAt: new Date().toISOString(), reports }, null, 2));
  console.log(JSON.stringify(reports.map(({ samples, ...report }) => report), null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
