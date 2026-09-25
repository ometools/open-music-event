#!/usr/bin/env python3
"""Verify host DNS and TLS before building or driving either app."""
import json
import socket
import ssl
import urllib.request
from sandbox import UPSTREAM


def main():
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
            data = json.load(response)
        key = 'issuer' if host.startswith('pds1.') else 'client_id'
        expected = 'https://' + host + ('' if key == 'issuer' else path)
        if data.get(key) != expected:
            raise RuntimeError(f'Wrong {key} for {host}')
    print('Host DNS, private CA, PDS discovery, and OAuth metadata passed.')


if __name__ == '__main__':
    main()
