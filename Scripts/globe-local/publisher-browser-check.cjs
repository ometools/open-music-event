const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const site = path.resolve(__dirname, '../../Sources/OpenMusicEventAppViewServer/Resources/Site');
const publishers = [
  { id: 1, did: 'did:plc:comedy', label: 'laugh.town', handle: 'laugh.town', eventCount: 2, avatarURL: 'https://cdn.bsky.app/img/avatar/plain/test' },
  { id: 2, did: 'did:plc:music', label: 'Music Calendar', handle: 'music.example', eventCount: 100 },
];

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const context = await browser.newContext();
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.origin !== 'http://ome.test') return route.abort();
      if (url.pathname.endsWith('getPublishers')) {
        const query = (url.searchParams.get('query') || '').toLowerCase();
        const ids = url.searchParams.getAll('publishers').map(Number);
        return route.fulfill({ json: { publishers: publishers.filter(p =>
          (!ids.length || ids.includes(p.id)) && `${p.label} ${p.did} ${p.handle}`.toLowerCase().includes(query)),
          defaults: { mode: 'allExcept', publishers: [1] } } });
      }
      if (url.pathname.endsWith('browseEventSummaries')) {
        const ids = url.searchParams.getAll('publishers').map(Number);
        const included = publishers.filter(p => url.searchParams.get('publisherMode') === 'only' ? ids.includes(p.id) : !ids.includes(p.id));
        return route.fulfill({ json: { events: included.map(p => ({
          uri: `at://${p.did}/community.lexicon.calendar.event/event`, catalog: 'community.lexicon.calendar.event',
          name: p.id === 1 ? 'Comedy Show' : 'Concert', startsAt: '2030-05-01T20:00:00Z',
          locationSummary: 'Local venue', hasEventViewer: false,
        })), hasMore: false, evaluatedAt: '2026-10-11T00:00:00Z' } });
      }
      if (url.pathname.includes('/xrpc/')) return route.fulfill({ json: { events: [], clusters: [] } });
      if (url.pathname.includes('maplibre-gl') && url.pathname.endsWith('.js')) return route.fulfill({ body: '' });
      const filename = path.join(site, url.pathname === '/' ? 'index.html' : url.pathname);
      if (!filename.startsWith(site + '/')) return route.abort();
      try {
        return route.fulfill({ body: await fs.readFile(filename), contentType: filename.endsWith('.js') ? 'text/javascript' : filename.endsWith('.css') ? 'text/css' : 'text/html' });
      } catch { return route.fulfill({ status: 404, body: '' }); }
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto('http://ome.test');
    await page.getByRole('button', { name: /Concert,/ }).waitFor();
    assert.equal(await page.getByRole('button', { name: /Comedy Show,/ }).count(), 0);
    await page.locator('#publisherPicker summary').click();
    await page.getByText('@music.example', { exact: true }).waitFor();
    assert.equal(await page.locator('#publisherChoices input').first().getAttribute('data-publisher-id'), '2');
    await page.getByText('100 events', { exact: true }).waitFor();
    assert.equal(await page.getByRole('link', { name: 'Bluesky profile for Music Calendar' }).getAttribute('href'), 'https://bsky.app/profile/did%3Aplc%3Amusic');
    await page.locator('#publisherSearch').fill('music.example');
    await page.waitForResponse(response => response.url().includes('getPublishers') && response.url().includes('music.example'));
    assert.equal(await page.getByRole('checkbox', { name: 'Include Music Calendar' }).count(), 1);
    await page.locator('#publisherSearch').fill('');
    await page.getByRole('checkbox', { name: 'Include laugh.town' }).check();
    await page.getByRole('button', { name: /Comedy Show,/ }).waitFor();
    const saved = await page.evaluate(() => localStorage.getItem('ome.publisherLens.v1'));
    assert.deepEqual(JSON.parse(saved), { mode: 'allExcept', publishers: [] });

    // A shared exclusion wins without overwriting the saved all-sources choice.
    await page.goto('http://ome.test/?publisherMode=allExcept&publishers=1');
    await page.getByRole('button', { name: /Concert,/ }).waitFor();
    assert.equal(await page.getByRole('button', { name: /Comedy Show,/ }).count(), 0);
    assert.equal(await page.evaluate(() => localStorage.getItem('ome.publisherLens.v1')), saved);
    await page.locator('#publisherPicker summary').click();
    await page.locator('#publisherMode').selectOption('only');
    await page.locator('#emptyState').waitFor({ state: 'visible' });
    await page.getByRole('checkbox', { name: 'Include laugh.town' }).check();
    await page.getByRole('button', { name: /Comedy Show,/ }).waitFor();
    assert.equal(await page.getByRole('button', { name: /Concert,/ }).count(), 0);
    await page.goBack();
    await page.locator('#emptyState').waitFor({ state: 'visible' });
    await page.goForward();
    await page.getByRole('button', { name: /Comedy Show,/ }).waitFor();
    await page.getByRole('button', { name: 'Reset to OME defaults' }).click();
    await page.getByRole('button', { name: /Concert,/ }).waitFor();
    await page.locator('#publisherSearch').fill('not a publisher');
    await page.getByText('No matching publishers.', { exact: false }).waitFor();
    assert.equal(await page.getByRole('checkbox', { name: 'Include laugh.town' }).count(), 1);
    assert.deepEqual(errors, []);
    console.log('Publisher browser stories passed (fixture-backed; map rendering not exercised).');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
