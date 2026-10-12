import asyncio
import os
import unittest
from unittest.mock import AsyncMock, patch

import public_https_proxy


class PublisherProxyTests(unittest.IsolatedAsyncioTestCase):
    async def response(self, request):
        server = await asyncio.start_server(public_https_proxy.handle, '127.0.0.1', 0)
        async with server:
            reader, writer = await asyncio.open_connection('127.0.0.1', server.sockets[0].getsockname()[1])
            writer.write(request + b'\r\n\r\n')
            await writer.drain()
            status = await reader.readline()
            writer.close()
            await writer.wait_closed()
            return status

    async def test_unrelated_host_is_denied_before_dns_lookup(self):
        with patch.dict(os.environ, ALLOWED_HOSTS='public.api.bsky.app'):
            with patch.object(public_https_proxy, 'public_address', new_callable=AsyncMock) as resolve:
                self.assertIn(b'403', await self.response(b'CONNECT example.com:443 HTTP/1.1'))
                resolve.assert_not_awaited()

    async def test_only_https_port_is_allowed(self):
        with patch.dict(os.environ, ALLOWED_HOSTS='public.api.bsky.app'):
            with patch.object(public_https_proxy, 'public_address', new_callable=AsyncMock) as resolve:
                self.assertIn(b'502', await self.response(b'CONNECT public.api.bsky.app:80 HTTP/1.1'))
                resolve.assert_not_awaited()

    async def test_allowed_host_reaches_public_address_validation(self):
        with patch.dict(os.environ, ALLOWED_HOSTS='public.api.bsky.app'):
            with patch.object(public_https_proxy, 'public_address', new_callable=AsyncMock,
                              side_effect=ValueError('No public address')) as resolve:
                self.assertIn(b'502', await self.response(b'CONNECT public.api.bsky.app:443 HTTP/1.1'))
                resolve.assert_awaited_once_with('public.api.bsky.app', 443)


if __name__ == '__main__':
    unittest.main()
