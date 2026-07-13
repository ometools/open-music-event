# OpenMusicEvent AppView Hosting Baseline

This workspace contains the first hosting-oriented AppView scaffold for `openmusicevent.app` and `ome.social`.

## Current Surface

- `OpenMusicEventAppView`: Hummingbird executable.
- `OpenMusicEventAppViewServer`: route and static well-known file library.
- `GET /healthz`: process health check.
- `GET /readyz`: readiness check.
- `GET /.well-known/atproto-did`: ATProto handle proof.
- `GET /.well-known/did.json`: DID Web document placeholder.
- `GET /.well-known/apple-app-site-association`: Apple Universal Links association.
- `GET /apple-app-site-association`: Apple root-path fallback.
- `GET /.well-known/assetlinks.json`: Android App Links association.

## Local Run

```sh
swift run OpenMusicEventAppView
```

Optional environment:

```sh
OME_APPVIEW_HOST=0.0.0.0
OME_APPVIEW_PORT=8080
OME_APPVIEW_WELL_KNOWN_ROOT=/absolute/path/to/WellKnown
```

## Hosting Notes

- Preserve the incoming `Host` header; well-known file selection is host-based.
- Do not redirect `/.well-known/*` paths.
- TLS termination can happen before the Swift process, but public production URLs must be HTTPS.
- Replace placeholder DIDs, Apple team/app IDs, Android package names, and Android signing fingerprints before production.
- Keep user handle claims dynamic later; these static files are only for official/root domains.

## Future Hosting Shape

- API handlers should remain stateless.
- Durable state should live in an external database, object storage, and a job queue.
- Jetstream ingestion and long-running reactors should run as workers, not inside request handlers.
- Lambda can host the stateless API later if the database/session/token/job dependencies are externalized.
