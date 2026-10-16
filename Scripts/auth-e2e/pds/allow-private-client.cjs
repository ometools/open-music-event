const fs = require('node:fs');
const path = require('node:path');

const pds = require.resolve('@atproto/pds', { paths: ['/app'] });
const provider = fs.realpathSync(path.resolve(path.dirname(pds), '../../oauth-provider'));
const types = fs.realpathSync(path.resolve(provider, '../oauth-types'));
const clientID = 'https://metadata.ome-auth.test/oauth-client-metadata.json';
const homepage = 'https://metadata.ome-auth.test/';
const callback = 'test.ome-auth.metadata:/oauth/callback';

function replaceOnce(file, needle, replacement) {
  const source = fs.readFileSync(file, 'utf8');
  if (source.split(needle).length !== 2) {
    throw new Error('Pinned PDS validation changed; review exception in ' + file);
  }
  fs.writeFileSync(file, source.replace(needle, replacement));
}

// Only the reserved/local hostname checks change. URL shape, reverse-domain
// callback matching, homepage origin/parent path, DPoP, PKCE and grants stay upstream.
replaceOnce(path.join(provider, 'dist/client/client-utils.js'),
  'if (isLocalHostname(url.hostname)) {',
  `if (isLocalHostname(url.hostname) && clientId !== ${JSON.stringify(clientID)}) {`);
replaceOnce(path.join(provider, 'dist/client/client-manager.js'),
  'if (clientUriUrl && isLocalHostname(clientUriUrl.hostname)) {',
  `if (clientUriUrl && isLocalHostname(clientUriUrl.hostname) &&
      !(clientId === ${JSON.stringify(clientID)} && metadata.client_uri === ${JSON.stringify(homepage)})) {`);
replaceOnce(path.join(types, 'dist/uri.js'),
  'if (isLocalHostname(urlDomain)) {',
  `if (isLocalHostname(urlDomain) && value !== ${JSON.stringify(callback)}) {`);

// The URI schema has no client context. Bind its one exception to our client
// here as well, including stored and loopback clients.
replaceOnce(path.join(provider, 'dist/client/client-manager.js'),
  'validateClientMetadata(clientId, metadata) {',
  `validateClientMetadata(clientId, metadata) {
    if (metadata.redirect_uris?.includes(${JSON.stringify(callback)}) &&
        clientId !== ${JSON.stringify(clientID)}) {
      throw new InvalidClientMetadataError('Private test callback requires the exact sandbox client');
    }`);
