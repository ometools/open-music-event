#!/usr/bin/env python3
"""Minimal CONNECT proxy limited to public HTTPS destinations."""
import asyncio
import ipaddress
import os
import socket


async def pump(reader, writer):
    try:
        while chunk := await reader.read(64 * 1024):
            writer.write(chunk)
            await writer.drain()
    finally:
        writer.close()


async def public_address(host, port):
    loop = asyncio.get_running_loop()
    addresses = await loop.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    for family, _, _, _, sockaddr in addresses:
        address = ipaddress.ip_address(sockaddr[0])
        if address.is_global:
            return family, sockaddr[0]
    raise ValueError('destination did not resolve to a public address')


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
        host, port_text = authority.rsplit(':', 1)
        allowed = os.environ.get('ALLOWED_HOSTS')
        if allowed is not None and host.lower() not in allowed.split(','):
            writer.write(b'HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n')
            await writer.drain()
            return
        port = int(port_text)
        if port != 443:
            raise ValueError('only public HTTPS destinations are allowed')
        family, address = await public_address(host.strip('[]'), port)
        upstream_reader, upstream_writer = await asyncio.open_connection(
            address,
            port,
            family=family,
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
    server = await asyncio.start_server(handle, '0.0.0.0', 8081)
    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    asyncio.run(main())
