const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');

async function main() {
  const pds = require.resolve('@atproto/pds', { paths: ['/app'] });
  const provider = fs.realpathSync(path.resolve(path.dirname(pds), '../../oauth-provider'));
  const types = fs.realpathSync(path.resolve(provider, '../oauth-types'));
  const { parseDiscoverableClientId } = await import(pathToFileURL(path.join(provider, 'dist/client/client-utils.js')));
  const { ClientManager } = await import(pathToFileURL(path.join(provider, 'dist/client/client-manager.js')));
  const { oauthClientMetadataSchema } = await import(pathToFileURL(path.join(types, 'dist/index.js')));
  const manager = Object.create(ClientManager.prototype);
  manager.serverMetadata = { grant_types_supported: ['authorization_code', 'refresh_token'] };
  const clientID = 'https://metadata.ome-auth.test/oauth-client-metadata.json';
  const fetchLive = process.argv[2] === '--fetch';
  async function fetchPrivate(url) {
    const response = await fetch(url, {redirect: 'error', signal: AbortSignal.timeout(10000)});
    assert.equal(response.status, 200, url);
    return response;
  }
  const metadata = fetchLive
    ? await fetchPrivate(clientID).then(response => {
      assert.equal(response.headers.get('content-type')?.split(';')[0], 'application/json');
      return response.json();
    })
    : process.argv[2]
    ? JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
    : {
      client_id: clientID, client_uri: 'https://metadata.ome-auth.test/',
      redirect_uris: ['test.ome-auth.metadata:/oauth/callback'],
      application_type: 'native', grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'], scope: 'atproto',
      token_endpoint_auth_method: 'none', dpop_bound_access_tokens: true,
    };
  const validate = (id, value) => {
    parseDiscoverableClientId(id);
    return manager.validateClientMetadata(id, oauthClientMetadataSchema.parse(value));
  };
  validate(clientID, metadata);
  if (fetchLive) {
    assert.equal(metadata.client_uri, 'https://metadata.ome-auth.test/');
    assert.deepEqual(metadata.redirect_uris, ['test.ome-auth.metadata:/oauth/callback']);
    for (const route of ['/', '/healthz', '/readyz']) {
      await fetchPrivate('https://metadata.ome-auth.test' + route);
    }
    console.log('Live AppView: private DNS, trusted HTTPS, JSON metadata, homepage and health passed.');
  }
  validate('https://openmusicevent.app/.well-known/oauth-client-metadata.json', {
    ...metadata,
    client_id: 'https://openmusicevent.app/.well-known/oauth-client-metadata.json',
    client_uri: 'https://openmusicevent.app',
    redirect_uris: ['app.openmusicevent:/oauth/callback'],
  });
  for (const id of [
    'https://other.ome-auth.test/oauth-client-metadata.json',
    'https://metadata.ome-auth.test/other.json',
    clientID + '?extra=1',
    'http://metadata.ome-auth.test/oauth-client-metadata.json',
    'https://localhost/client.json',
  ]) assert.throws(() => validate(id, {...metadata, client_id: id}), id);
  for (const change of [
    {client_id: 'https://example.com/client.json'},
    {client_uri: 'https://openmusicevent.app'},
    {client_uri: 'https://metadata.ome-auth.test/other/'},
    {client_uri: 'http://metadata.ome-auth.test/'},
    {client_uri: 'https://other.ome-auth.test/'},
    {redirect_uris: ['app.openmusicevent:/oauth/callback']},
    {redirect_uris: ['test.ome-auth.other:/oauth/callback']},
    {redirect_uris: ['test.ome-auth.metadata://oauth/callback']},
    {redirect_uris: ['test.ome-auth.metadata:/other']},
    {redirect_uris: ['http://metadata.ome-auth.test/oauth/callback']},
    {dpop_bound_access_tokens: false},
    {scope: 'profile'},
    {grant_types: ['implicit']},
    {application_type: 'web'},
  ]) assert.throws(() => validate(clientID, {...metadata, ...change}), JSON.stringify(change));
  // A public client cannot borrow the sandbox redirect or homepage exception.
  assert.throws(() => validate('https://example.com/client.json', {
    ...metadata, client_id: 'https://example.com/client.json', client_uri: 'https://example.com/'
  }));
  assert.throws(() => manager.validateClientMetadata('http://localhost', oauthClientMetadataSchema.parse({
    ...metadata, client_id: 'http://localhost', client_uri: undefined,
  })));
  console.log('Pinned PDS: private and production metadata accepted; 21 invalid identities/protocol variants rejected.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
