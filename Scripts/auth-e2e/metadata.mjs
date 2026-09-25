import { createServer } from 'node:http';

const clientID = 'https://metadata.ome-auth.test/oauth-client-metadata.json';
const metadata = {
  client_id: clientID,
  client_name: 'OME Private Authentication Tests',
  client_uri: 'https://metadata.ome-auth.test',
  application_type: 'native',
  redirect_uris: ['app.openmusicevent:/oauth/callback'],
  grant_types: ['authorization_code', 'refresh_token'],
  response_types: ['code'],
  scope: 'atproto',
  token_endpoint_auth_method: 'none',
  dpop_bound_access_tokens: true,
};

createServer((request, response) => {
  if (request.method !== 'GET' || !['/', '/oauth-client-metadata.json'].includes(request.url)) {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  response.end(JSON.stringify(metadata));
}).listen(8080, '0.0.0.0');
