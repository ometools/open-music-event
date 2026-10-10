# Local globe data path

This harness creates one private Atmo-in-a-Box PDS with five accounts: one durable DID
per venue. It publishes the standard `app.bsky.actor.profile/self` record and each
venue's complete canonical OME source graph. The AppView consumes the private PDS and
the public Community Calendar network through separate Hydrant instances. Only a
relay adapter, PLC adapter, and port-443-only HTTPS proxy used by the public Hydrant
join an egress network; the PDS, local PLC, private Hydrant, and AppView remain on
Atmo-in-a-Box's internal network.

Account handles use short stable labels where Atmo-in-a-Box's local handle limit is
shorter than the venue's source slug; the account profile retains the full venue name.

The runtime state, credentials, DIDs, identity maps, image cache, receipts, Hydrant
databases, and AppView database live under `.build/globe-local` and are not source
fixtures.

```sh
python3 Scripts/globe-local/sandbox.py prepare
python3 Scripts/globe-local/sandbox.py up
python3 Scripts/globe-local/sandbox.py seed
python3 Scripts/globe-local/sandbox.py sync
```

Open `http://127.0.0.1:18081/`. `up` starts a loopback-only HTTP proxy for the globe;
the proxy verifies the sandbox's public CA itself, so browser testing does not require
host-file entries or certificate installation. Use `browser-start` and `browser-stop`
to manage that proxy separately. The known sample venues use checked-in local geocoding
overrides; set `GEOAPIFY_API_KEY` before `up` to resolve any other addresses.
`sync` temporarily runs a localhost-only CONNECT bridge
restricted to the sandbox PDS, so publication does not require host DNS or CA
installation. Re-running it preserves record URIs through the private identity maps and
verifies every PDS write by CID and payload readback.

The canonical private HTTPS endpoints remain available for protocol-level testing.
Run `hosts`, trust only the printed public CA, and use `access-start` when that behavior
is specifically needed. Port 443 must be free for both canonical HTTPS access and the
loopback HTTP proxy.

The harness never deploys remotely. `down` preserves every identity and database.
