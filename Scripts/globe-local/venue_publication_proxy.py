#!/usr/bin/env python3
"""Local-only CONNECT bridge from the host publisher to the sandbox PDS."""
import asyncio
import os


ALLOWED_AUTHORITY = 'pds1.ome-globe.test:443'
UPSTREAM_HOST = os.environ.get('OME_GLOBE_PROXY_UPSTREAM_HOST', 'gateway')
UPSTREAM_PORT = int(os.environ.get('OME_GLOBE_PROXY_UPSTREAM_PORT', '443'))
LISTEN_PORT = int(os.environ.get('OME_GLOBE_PROXY_LISTEN_PORT', '8083'))


async def pump(reader, writer):
    try:
        while chunk := await reader.read(64 * 1024):
            writer.write(chunk)
            await writer.drain()
    finally:
        writer.close()


async def handle(reader, writer):
    upstream_writer = None
    try:
        header = await reader.readuntil(b'\r\n\r\n')
        if len(header) > 64 * 1024:
            raise ValueError('request header is too large')
        request_line = header.split(b'\r\n', 1)[0].decode('ascii')
        method, authority, _ = request_line.split(' ', 2)
        if method != 'CONNECT':
            writer.write(b'HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n')
            await writer.drain()
            return
        if authority.lower() != ALLOWED_AUTHORITY:
            raise ValueError('destination is not the local venue PDS')
        upstream_reader, upstream_writer = await asyncio.open_connection(
            UPSTREAM_HOST,
            UPSTREAM_PORT,
        )
        writer.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
        await writer.drain()
        await asyncio.gather(
            pump(reader, upstream_writer),
            pump(upstream_reader, writer),
        )
    except (asyncio.IncompleteReadError, OSError, UnicodeError, ValueError):
        if not writer.is_closing():
            writer.write(b'HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n')
            await writer.drain()
    finally:
        if upstream_writer is not None:
            upstream_writer.close()
        writer.close()


async def main():
    server = await asyncio.start_server(handle, '127.0.0.1', LISTEN_PORT)
    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    asyncio.run(main())
