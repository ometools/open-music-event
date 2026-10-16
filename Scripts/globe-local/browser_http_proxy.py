#!/usr/bin/env python3
"""Expose the local globe AppView over loopback HTTP for browser development."""
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
import socket
import ssl
import urllib.parse


APPVIEW_HOST = 'metadata.ome-globe.test'
PDS_HOST = 'pds1.ome-globe.test'
PDS_PATH_PREFIX = '/.ome-globe-local/pds'
HOP_BY_HOP_HEADERS = {
    'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
    'proxy-connection', 'te', 'trailer', 'transfer-encoding', 'upgrade',
}


class SandboxHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, host, connect_host, **kwargs):
        super().__init__(host, **kwargs)
        self.connect_host = connect_host

    def connect(self):
        connection = socket.create_connection(
            (self.connect_host, self.port),
            self.timeout,
            self.source_address,
        )
        self.sock = self._context.wrap_socket(connection, server_hostname=self.host)


class GlobeProxyHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'OMEGlobeLoopback/1'

    def do_GET(self):
        self.proxy()

    def do_HEAD(self):
        self.proxy()

    def proxy(self):
        response_started = False
        if self.path == PDS_PATH_PREFIX or self.path.startswith(f'{PDS_PATH_PREFIX}/'):
            upstream_host = PDS_HOST
            upstream_path = self.path.removeprefix(PDS_PATH_PREFIX) or '/'
        else:
            upstream_host = APPVIEW_HOST
            upstream_path = self.path
        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS and name.lower() != 'host'
        }
        upstream = SandboxHTTPSConnection(
            upstream_host,
            connect_host=self.server.upstream_address,
            port=self.server.upstream_port,
            context=self.server.tls_context,
            timeout=30,
        )
        try:
            upstream.request(self.command, upstream_path, headers=headers)
            response = upstream.getresponse()
            self.send_response(response.status, response.reason)
            for name, value in response.getheaders():
                if name.lower() not in HOP_BY_HOP_HEADERS:
                    self.send_header(name, rewrite_local_pds_location(name, value))
            self.send_header('X-OME-Globe-Loopback-Proxy', '1')
            self.send_header('X-OME-Globe-Loopback-PID', str(os.getpid()))
            self.send_header('Connection', 'close')
            self.end_headers()
            response_started = True
            self.close_connection = True
            if self.command != 'HEAD':
                while chunk := response.read(64 * 1024):
                    self.wfile.write(chunk)
        except (ConnectionError, OSError, ssl.SSLError) as error:
            if not response_started:
                self.send_error(502, f'Local AppView unavailable: {error}')
            self.close_connection = True
        finally:
            upstream.close()

    def log_message(self, format, *args):
        print(f'{self.address_string()} - {format % args}', flush=True)


def rewrite_local_pds_location(name, value):
    if name.lower() != 'location':
        return value
    location = urllib.parse.urlsplit(value)
    if location.scheme != 'https' or location.netloc != PDS_HOST:
        return value
    target = urllib.parse.urlunsplit(('', '', location.path, location.query, location.fragment))
    return f'{PDS_PATH_PREFIX}{target}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ca-certificate', required=True)
    parser.add_argument('--listen-port', type=int, default=18081)
    parser.add_argument('--upstream-address', default='127.0.0.1')
    parser.add_argument('--upstream-port', type=int, default=443)
    arguments = parser.parse_args()

    server = ThreadingHTTPServer(('127.0.0.1', arguments.listen_port), GlobeProxyHandler)
    server.daemon_threads = True
    server.tls_context = ssl.create_default_context(cafile=arguments.ca_certificate)
    server.upstream_address = arguments.upstream_address
    server.upstream_port = arguments.upstream_port
    server.serve_forever()


if __name__ == '__main__':
    main()
