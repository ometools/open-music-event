#!/usr/bin/env python3
"""Verify host DNS and TLS before building or driving either app."""
import json
import socket
import ssl
import subprocess
import urllib.request
import uuid
from sandbox import PROJECT, UPSTREAM


def main():
    # A never-provisioned name proves domain DNS works, rather than a stale hosts entry.
    probe = 'dns-check-' + uuid.uuid4().hex + '.pds1.ome-auth.test'
    try:
        addresses = {entry[4][0] for entry in socket.getaddrinfo(probe, 443)}
    except socket.gaierror as error:
        raise RuntimeError('Sandbox domain DNS is unavailable. Start host-dns and install '
                           'the one-time resolver with host-routing.py install.') from error
    if addresses != {'127.0.0.1'}:
        raise RuntimeError('Sandbox domain DNS must resolve fresh names only to 127.0.0.1')
    context = ssl.create_default_context(cafile=str(UPSTREAM / 'state/ca/root.crt'))
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                         urllib.request.HTTPSHandler(context=context))
    endpoints = {
        'pds1.ome-auth.test': '/.well-known/oauth-authorization-server',
        'metadata.ome-auth.test': '/oauth-client-metadata.json',
    }
    for host in ['plc.ome-auth.test', *endpoints,
                 'ios-tester.pds1.ome-auth.test', 'android-tester.pds1.ome-auth.test']:
        if socket.gethostbyname(host) != '127.0.0.1':
            raise RuntimeError(f'{host} must resolve to the loopback-only sandbox relay')
    for host, path in endpoints.items():
        with opener.open('https://' + host + path, timeout=10) as response:
            if response.status != 200 or response.headers.get_content_type() != 'application/json':
                raise RuntimeError(f'{host} must serve JSON directly with HTTP 200')
            if response.url != 'https://' + host + path:
                raise RuntimeError(f'{host} must not redirect discovery')
            data = json.load(response)
        key = 'issuer' if host.startswith('pds1.') else 'client_id'
        expected = 'https://' + host + ('' if key == 'issuer' else path)
        if data.get(key) != expected:
            raise RuntimeError(f'Wrong {key} for {host}')
        if key == 'client_id':
            expected_fields = {
                'client_uri': 'https://metadata.ome-auth.test/',
                'redirect_uris': ['test.ome-auth.metadata:/oauth/callback'],
                'application_type': 'native',
                'grant_types': ['authorization_code', 'refresh_token'],
                'response_types': ['code'],
                'scope': 'atproto repo:events.openmusic.event?action=create repo:events.openmusic.event?action=update blob:image/png blob:image/jpeg',
                'token_endpoint_auth_method': 'none',
                'dpop_bound_access_tokens': True,
            }
            for field, value in expected_fields.items():
                if data.get(field) != value:
                    raise RuntimeError(f'Wrong sandbox metadata {field}: {data.get(field)!r}')
            if 'openmusicevent.app' in json.dumps(data):
                raise RuntimeError('Sandbox metadata contains production identity')
    for path in ['/', '/healthz', '/readyz']:
        with opener.open('https://metadata.ome-auth.test' + path, timeout=10) as response:
            if response.status != 200:
                raise RuntimeError(f'Private AppView is unavailable at {path}')
    subprocess.run([
        'docker', 'exec', '-e', 'NODE_EXTRA_CA_CERTS=/ca/root.crt',
        f'{PROJECT}-pds1-1', 'node', '/usr/local/lib/validate-private-client.cjs', '--fetch',
    ], check=True)
    print('Host DNS, private CA, PDS discovery, and complete AppView OAuth identity passed.')


if __name__ == '__main__':
    main()
