// Run against a local AppView: PLAYWRIGHT_MODULE=/path/to/playwright node Scripts/globe-local/browser-check.cjs
const { chromium, devices } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const base = process.env.OME_GLOBE_URL || 'http://127.0.0.1:18082';
const output = process.env.OME_GLOBE_REPORT_DIR || '.build/globe-map-validation';

(async () => {
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const reports = [];
    for (const mobile of [false, true]) {
      const context = await browser.newContext(mobile ? { ...devices['Pixel 7'] } : { viewport: { width: 1440, height: 1000 } });
      const page = await context.newPage();
      await page.addInitScript(() => {
        let library;
        Object.defineProperty(window, 'maplibregl', { configurable: true, get: () => library, set(value) {
          library = value;
          library.Map = new Proxy(library.Map, { construct(target, args) {
            const map = Reflect.construct(target, args);
            window.__omeTestMap = map;
            return map;
          } });
        } });
      });
      const errors = [], requests = [], responses = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => {
        if (message.type() === 'error' || message.text().includes('unavailable')) console.error(message.text());
      });
      page.on('request', request => {
        if (request.url().includes('/xrpc/') || request.url().includes('/map/events/')) requests.push(request.url());
      });
      page.on('response', response => {
        if (response.url().includes('/map/events/')) responses.push({ status: response.status(), url: response.url() });
      });
      const started = Date.now();
      await page.goto(base, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => window.OME_GLOBE_METRICS?.displayedItems > 0, null, { timeout: 45000 });
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      const initial = await page.evaluate(() => window.OME_GLOBE_METRICS);
      assert.equal(await page.locator('input[name=catalog]:checked').count(), 2);
      assert.equal(await page.locator('#mapCard').isVisible(), false);
      assert.equal(await page.locator('#dateMode').inputValue(), 'current');
      assert(responses.some(response => response.status === 200));
      assert(!requests.some(url => url.includes('getMapItems')));
      await page.screenshot({ path: `${output}/${mobile ? 'mobile-emulated' : 'desktop'}-browse.png` });
      await page.locator('.maplibregl-canvas').scrollIntoViewIfNeeded();
      const cluster = await page.evaluate(() => {
        const map = window.__omeTestMap;
        const feature = map.queryRenderedFeatures({ layers: ['browse-clusters'] }).find(item => {
          const [longitude, latitude] = item.geometry.coordinates;
          return longitude > -125 && longitude < -90 && latitude > 25 && latitude < 50;
        });
        if (!feature) return null;
        const point = map.project(feature.geometry.coordinates);
        const rectangle = map.getCanvas().getBoundingClientRect();
        return { x: rectangle.left + point.x, y: rectangle.top + point.y, zoom: map.getZoom() };
      });
      assert(cluster, 'The backfilled US events should form a visible cluster');
      await Promise.all([
        page.waitForResponse(response => response.url().includes('browseEventSummaries') && new URL(response.url()).searchParams.has('cell')),
        page.mouse.click(cluster.x, cluster.y),
      ]);
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      assert.match(await page.locator('#listHeading').innerText(), /Events in this cluster/i);
      assert((await page.locator('.event-card-button').count()) > 0);
      await page.waitForFunction(zoom => window.__omeTestMap.getZoom() > zoom && !window.__omeTestMap.isMoving(), cluster.zoom);

      const search = page.locator('#searchInput');
      await search.fill('music');
      await page.waitForResponse(response => response.url().includes('getSearchMapItems') && response.status() === 200);
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      const names = await page.locator('.event-name').allTextContents();
      assert(names.length > 0 && names.length <= 50);
      assert.equal(await page.locator('#loadMore').isVisible(), true);
      await Promise.all([
        page.waitForResponse(response => response.url().includes('getSearchMapItems') && response.status() === 200),
        page.locator('#loadMore').click(),
      ]);
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      assert.notDeepEqual(await page.locator('.event-name').allTextContents(), names);
      await Promise.all([
        page.waitForResponse(response => response.url().includes('getSearchMapItems') && response.status() === 200),
        page.locator('#previousPage').click(),
      ]);
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      assert.deepEqual(await page.locator('.event-name').allTextContents(), names);
      assert.equal(await page.locator('#previousPage').isVisible(), false);
      assert.match(await page.locator('#listHeading').innerText(), /Search results everywhere/i);
      const searchRequest = new URL(requests.filter(url => url.includes('browseEventSummaries')).at(-1));
      assert.equal(searchRequest.searchParams.has('north'), false);
      const listRequests = requests.filter(url => url.includes('browseEventSummaries')).length;
      await page.locator('#zoomInButton').click();
      await page.waitForTimeout(1200); // Browser animation/debounce observation, not a Swift scheduling assertion.
      assert.equal(requests.filter(url => url.includes('browseEventSummaries')).length, listRequests);
      assert.deepEqual(await page.locator('.event-name').allTextContents(), names);
      // Search results stay put while the map crosses from globe to flat and back.
      const originalCamera = await page.evaluate(() => ({ center: window.__omeTestMap.getCenter().toArray(), zoom: window.__omeTestMap.getZoom() }));
      for (const zoom of [12, 1.5]) {
        await page.evaluate(zoom => new Promise(resolve => {
          const map = window.__omeTestMap;
          map.once('render', resolve);
          map.jumpTo({ zoom });
        }), zoom);
        assert.deepEqual(errors, [], `Projection at zoom ${zoom} must render without shader errors`);
      }
      await page.evaluate(camera => window.__omeTestMap.jumpTo(camera), originalCamera);
      await Promise.all([
        page.waitForResponse(response => response.url().includes('calendar.getEvent?') && response.status() === 200),
        page.locator('.event-card-button').first().click(),
      ]);
      await page.waitForFunction(() => !document.querySelector('.event-detail:not([hidden])')?.textContent.includes('Loading event details'));
      assert.equal(await page.locator('.event-card-button').first().getAttribute('aria-expanded'), 'true');
      await page.locator('.event-card-button').first().focus();
      await page.keyboard.press('ArrowDown');
      assert.equal(await page.locator('.event-card-button').nth(1).evaluate(node => node === document.activeElement), true);
      await page.waitForFunction(() => !window.__omeTestMap.isMoving());
      const beforeJump = await page.evaluate(() => ({ center: window.__omeTestMap.getCenter().toArray(), zoom: window.__omeTestMap.getZoom() }));
      await Promise.all([
        page.waitForResponse(response => response.url().includes('getSearchMapItems') && response.status() === 200),
        page.locator('#jumpToNow').click(),
      ]);
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      assert.equal(await search.inputValue(), 'music');
      assert.equal(await page.locator('input[name=catalog]:checked').count(), 2);
      assert.deepEqual(await page.evaluate(() => ({ center: window.__omeTestMap.getCenter().toArray(), zoom: window.__omeTestMap.getZoom() })), beforeJump);
      await Promise.all([
        page.waitForResponse(response => response.url().includes('browseEventSummaries') && response.url().includes('north=')),
        page.locator('#searchArea').click(),
      ]);
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      assert.match(await page.locator('#listHeading').innerText(), /selected area/i);
      // Hold an obsolete response explicitly; a newer search must win even after it is released.
      let releaseObsolete, obsoleteSeen;
      const obsoleteGate = new Promise(resolve => { releaseObsolete = resolve; });
      const obsoleteRequest = new Promise(resolve => { obsoleteSeen = resolve; });
      const obsoleteURL = /browseEventSummaries.*query=obsolete-request-test/;
      await page.route(obsoleteURL, async route => {
        obsoleteSeen();
        await obsoleteGate;
        await route.fulfill({ contentType: 'application/json', body: JSON.stringify({
          events: [{ uri: 'at://did:plc:test/community.lexicon.calendar.event/obsolete', name: 'OBSOLETE RESULT', catalog: 'community.lexicon.calendar.event' }],
          hasMore: false, evaluatedAt: new Date().toISOString(),
        }) }).catch(() => {}); // An aborted fetch may already have closed the route.
      });
      await search.fill('obsolete-request-test');
      await obsoleteRequest;
      await search.fill('no-match-xyzzylongword');
      await page.waitForFunction(() => !document.querySelector('#emptyState').hidden);
      releaseObsolete();
      await page.unrouteAll({ behavior: 'wait' });
      assert.equal(await page.locator('.event-card-button').count(), 0);
      assert.equal(await page.getByText('OBSOLETE RESULT').count(), 0);
      for (const checkbox of await page.locator('input[name=catalog]').all()) await checkbox.uncheck();
      await page.waitForFunction(() => document.querySelector('#eventList').getAttribute('aria-busy') === 'false');
      assert.equal(await page.locator('.event-card-button').count(), 0);
      assert.equal(await page.locator('input[name=catalog]:checked').count(), 0);
      assert.deepEqual(errors, []);
      reports.push({ browser: mobile ? 'Chrome Pixel 7 emulation (not physical mobile)' : 'desktop Chrome', initial, totalTestMilliseconds: Date.now() - started, errors, failedTiles: responses.filter(response => response.status >= 400) });
      await context.close();
    }
    // A slow basemap must not postpone our event requests or visible markers.
    const delayedContext = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    let releaseBasemap, blockedBasemapRequests = 0;
    const basemapGate = new Promise(resolve => { releaseBasemap = resolve; });
    try {
      const page = await delayedContext.newPage();
      await page.route('**/natural_earth/**', async route => {
        blockedBasemapRequests++;
        await basemapGate;
        await route.continue().catch(() => {});
      });
      await page.goto(base, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => window.OME_GLOBE_METRICS?.displayedItems > 0, null, { timeout: 15000 });
      assert(blockedBasemapRequests > 0);
      reports.push({ check: 'Event markers render while basemap raster requests are blocked', passed: true, blockedBasemapRequests });
    } finally {
      releaseBasemap();
      await delayedContext.close();
    }
    await fs.writeFile(`${output}/browser-results.json`, JSON.stringify(reports, null, 2));
    console.log(JSON.stringify(reports, null, 2));
  } catch (error) {
    console.error(error);
    for (const context of browser.contexts()) {
      for (const page of context.pages()) {
        console.error(await page.evaluate(() => ({ metrics: window.OME_GLOBE_METRICS, status: document.querySelector('#dataStatus')?.textContent, text: document.body.innerText.slice(0, 1500) })).catch(() => 'Page unavailable'));
        await page.screenshot({ path: `${output}/browser-failure.png` });
      }
    }
    throw error;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
