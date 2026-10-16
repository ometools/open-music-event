// Only access-token age changes. Refresh-token and session lifetimes stay upstream.
const fs = require('node:fs');
const path = require.resolve('@atproto/pds', {paths: ['/app']}).replace(/index\.js$/, 'context.js');
const source = fs.readFileSync(path, 'utf8');
const needle = 'new OAuthProvider({';
if (source.split(needle).length !== 2 || source.includes('tokenMaxAge:')) {
  throw new Error('Pinned PDS OAuth constructor changed; review the lifetime patch');
}
fs.writeFileSync(path, source.replace(needle, needle + '\n                tokenMaxAge: 60_000,'));
