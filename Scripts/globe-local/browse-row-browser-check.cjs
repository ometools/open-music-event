const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const site = path.resolve(__dirname, '../../Sources/OpenMusicEventAppViewServer/Resources/Site');
const catalog = 'community.lexicon.calendar.event';
const avatar = 'https://cdn.bsky.app/img/avatar/plain/venue';
const events = [
  { name: 'London show', startsAt: '2026-10-12T16:00:00Z', endsAt: '2026-10-12T18:00:00Z', timeZoneIdentifier: 'Europe/London',
    locationSummary: 'The Hive', locality: 'Penzance', region: 'Cornwall', country: 'GB', publisherName: 'Venue Calendar', publisherAvatarURL: avatar },
  { name: 'Local show', startsAt: '2026-01-12T00:30:00Z', timeZoneIdentifier: 'America/Denver',
    locationSummary: 'Theatre', locality: 'Boulder', region: 'CO', country: 'US' },
  { name: 'Missing fields' },
  { name: 'Unknown zone', startsAt: '2026-10-12T16:00:00Z' },
  { name: 'Date only', startsAt: '2026-10-12T00:00:00Z', dateOnly: true },
  { name: 'Clock change', startsAt: '2026-11-01T07:30:00Z', endsAt: '2026-11-01T08:30:00Z', timeZoneIdentifier: 'America/Denver' },
  { name: 'Freeform address', locationSummary: 'Elmore Court, Gloucester, UK', country: 'United Kingdom' },
].map((event, index) => ({ uri: `at://did:plc:venue/${catalog}/${index}`, catalog, ...event }));

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    for (const timeZone of ['America/Denver', 'America/Phoenix', 'Europe/London']) {
      const context = await browser.newContext({ locale: 'en-US', timezoneId: timeZone });
      await context.route('**/*', async route => {
        const url = new URL(route.request().url());
        if (url.href === avatar) return route.fulfill({ contentType: 'image/png', body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=', 'base64') });
        if (url.origin !== 'http://ome.test') return route.abort();
        if (url.pathname.endsWith('getPublishers')) return route.fulfill({ json: { publishers: [], defaults: { mode: 'allExcept', publishers: [] } } });
        if (url.pathname.endsWith('browseEventSummaries')) return route.fulfill({ json: { events, hasMore: false } });
        if (url.pathname.includes('/xrpc/')) return route.fulfill({ json: { events: [], clusters: [] } });
        if (url.pathname.includes('maplibre-gl') && url.pathname.endsWith('.js')) return route.fulfill({ body: '' });
        const filename = path.join(site, url.pathname === '/' ? 'index.html' : url.pathname);
        if (!filename.startsWith(site + '/')) return route.abort();
        try { return route.fulfill({ body: await fs.readFile(filename), contentType: filename.endsWith('.js') ? 'text/javascript' : filename.endsWith('.css') ? 'text/css' : 'text/html' }); }
        catch { return route.fulfill({ status: 404, body: '' }); }
      });
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto('http://ome.test');
      await page.locator('.event-card').nth(5).waitFor();
      const row = name => page.locator('.event-card').filter({ has: page.locator('.event-name', { hasText: name }) });
      assert.equal(await row('London show').locator('.event-location').innerText(), 'The Hive · Penzance · Cornwall · United Kingdom');
      assert.match(await row('Local show').locator('.event-location').innerText(), /Boulder · CO · United States/);
      assert.equal(await row('Freeform address').locator('.event-location').innerText(), 'Elmore Court, Gloucester, UK');
      assert.equal(await row('London show').locator('.publisher-avatar').getAttribute('src'), avatar);
      assert((await row('London show').locator('.event-art').evaluate(element => element.style.backgroundImage)).includes(avatar));
      for (const name of ['Missing fields', 'Unknown zone']) {
        assert.equal(await row(name).locator('.event-location').isVisible(), false);
        assert.equal(await row(name).locator('.event-time').isVisible(), false);
        assert.equal(await row(name).locator('.event-calendar').isVisible(), false);
      }
      assert.equal(await row('Date only').locator('.event-time').isVisible(), false);
      assert.equal(await row('Date only').locator('.event-day').innerText(), '12');
      assert.equal(await row('Local show').locator('.event-day').innerText(), '11');
      assert.equal(await row('Local show').locator('.event-time').innerText(), timeZone === 'America/Denver' ? '5:30 PM' : '5:30 PM (MST)');
      const london = await row('London show').locator('.event-time').innerText();
      assert.match(london, timeZone === 'Europe/London' ? /^5:00 PM – 7:00 PM$/ : /^5:00 PM – 7:00 PM \((GMT\+1|BST)\)$/);
      if (timeZone === 'Europe/London') assert.equal(await row('Clock change').locator('.event-time').innerText(), '1:30 AM (MDT) – 1:30 AM (MST)');
      assert(!/to be announced|not supplied|not specified|Open for location/.test(await page.locator('#eventList').innerText()));
      assert.deepEqual(errors, []);
      await context.close();
    }
    console.log('Browse-row stories passed: locations, publisher artwork, omission, local dates, zone identity, DST.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
