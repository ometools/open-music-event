const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');

async function main() {
  const pds = require.resolve('@atproto/pds', { paths: ['/app'] });
  const file = path.resolve(path.dirname(pds), '../../oauth-provider/dist/client/client-utils.js');
  const source = fs.readFileSync(file, 'utf8');
  const needle = 'if (isLocalHostname(url.hostname)) {';
  const clientID = 'https://metadata.ome-auth.test/oauth-client-metadata.json';
  if (source.split(needle).length !== 2) {
    throw new Error('Pinned PDS client validation changed; review the private client exception');
  }
  fs.writeFileSync(file, source.replace(needle,
    `if (isLocalHostname(url.hostname) && clientId !== ${JSON.stringify(clientID)}) {`));

  // Exercise the real pinned validator: only our exact private client is allowed.
  const { parseDiscoverableClientId } = await import(pathToFileURL(file).href);
  assert.equal(parseDiscoverableClientId(clientID).href, clientID);
  assert.equal(parseDiscoverableClientId('https://example.com/client.json').hostname, 'example.com');
  for (const rejected of [
    'https://other.ome-auth.test/oauth-client-metadata.json',
    'https://metadata.ome-auth.test/other.json',
    clientID + '?extra=1',
    'http://metadata.ome-auth.test/oauth-client-metadata.json',
    'https://localhost/client.json',
  ]) {
    assert.throws(() => parseDiscoverableClientId(rejected), rejected);
  }
  console.log('Private OAuth client exception: allowed exact fixture; rejected other local clients');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
