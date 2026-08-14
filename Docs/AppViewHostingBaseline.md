# OpenMusicEvent AppView Hosting Baseline

This workspace contains the first hosting-oriented AppView scaffold for `openmusicevent.app` and `ome.social`.

The AppView origin is intended to serve `openmusicevent.app`, `ome.social`,
`openmusic.events`, `opencomedy.events`, `openconferences.events`, and
`openmusicevent.live`, including their configured `www` aliases.

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
- `GET /events/{claim}`: host-scoped branded attendee page for a configured durable event.
- `POST /notifications/v1/installations`: creates an anonymous installation credential.
- `PUT /notifications/v1/destination`: replaces the authenticated installation's typed APNs or
  FCM destination.
- `PUT /notifications/v1/subscriptions`: replaces the authenticated installation's desired
  source subscriptions.
- `POST /webhooks/tangled`: authenticates configured Tangled push deliveries and records each
  provider delivery once in the durable inbox.

## Local Run

```sh
swift run OpenMusicEventAppView
```

Optional environment:

```sh
OME_APPVIEW_HOST=0.0.0.0
OME_APPVIEW_PORT=8080
OME_APPVIEW_WELL_KNOWN_ROOT=/absolute/path/to/WellKnown
OME_APPVIEW_DATABASE_PATH=/absolute/path/to/open-music-event-appview.sqlite
OME_BRANDED_EVENT_ROUTE_CONFIGURATION_PATH=/absolute/path/to/branded-event-routes.json
OME_NOTIFICATION_DESTINATION_KEY=<base64-encoded-32-byte-key>
OME_NOTIFICATION_DESTINATION_KEY_VERSION=1
OME_NOTIFICATION_REGISTRATION_AUTHORIZATION=anonymous
OME_NOTIFICATION_APPLICATION_IDS=app.openmusicevent,com.Festivl.WickedWoods
OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH=/absolute/path/to/notification-providers.json
OME_APNS_TEAM_ID=YJRWV8Z7KT
OME_APNS_KEY_ID=<Apple-key-ID>
OME_APNS_PRIVATE_KEY_PATH=/run/credentials/ome-appview.service/apns-private-key
OME_FCM_SERVICE_ACCOUNT_PATH=/run/credentials/ome-appview.service/fcm-service-account.json
OME_TANGLED_WEBHOOK_CONFIGURATION_PATH=/absolute/path/to/tangled-webhooks.json
OME_WEBHOOK_SECRET_KEY_PATH=/absolute/path/to/webhook-secret-key
OME_WEBHOOK_SECRET_KEY_VERSION=1
```

`OME_TCA26_PATH` and `OME_COMPOSABLE_NOTIFICATIONS_PATH` are build-time package overrides, not
runtime service configuration. During active deployment iteration, point them at reviewed sibling
checkouts on the build host. The current Swift 6.3 toolchain requires the TCA26 sibling containing
the `Store.deinit` optimizer workaround for release builds; an ordinary remote `main` resolution
does not currently produce a release binary on this toolchain.

Provider routing is non-secret deployment configuration. Each registered application ID must have
at least one matching provider route:

```json
{
  "apns": [
    {
      "applicationID": "app.openmusicevent",
      "environment": "development",
      "topic": "app.openmusicevent"
    },
    {
      "applicationID": "com.Festivl.WickedWoods",
      "environment": "development",
      "topic": "com.Festivl.WickedWoods"
    }
  ],
  "fcm": [
    {
      "applicationID": "com.Festivl.WickedWoods",
      "projectID": "ome-push-notifications"
    }
  ]
}
```

Use `development` for tokens from Xcode development builds and `production` for distributed iOS
builds. The routing file contains no private key or service-account JSON.

Branded route configuration keeps the public claim separate from the durable event identity. The
Wicked Woods production entry is:

```json
{
  "claims": [
    {
      "host": "wickedwoods.openmusicevent.app",
      "eventClaim": "2026",
      "organizerID": "did:plc:5df2u7ief6m6tn77jznicxob",
      "eventRKey": "ome-workspace-2026"
    }
  ]
}
```

The attendee URL therefore stays `https://wickedwoods.openmusicevent.app/events/2026`; the event
rkey is deployment configuration and never appears in the branded path.

The notification destination key belongs to the deployment, not the database or source tree.
AppView stores AES-GCM ciphertext plus its key version so a future key rotation can retain old keys
after the protection dependency grows key-ring support. Do not increment the configured version or
replace the key while registrations still use the current single-key implementation. If the key is
absent, notification registration remains unavailable and the routes return `503` rather than
storing provider tokens in plaintext. A key alone does not enable the public installation route;
the deployment must explicitly select `anonymous` authorization and allow each application ID.
When provider routes are installed, registration additionally rejects an application/provider
pair that has no matching route, so an undeliverable token cannot enter the outbox.

## Notification Registration Observation

Registration logs identify the operation, installation ID, application ID, provider, subscription
count, and HTTP failure status where those values are available. They never include the reusable
installation credential or provider token. Follow the live registration flow with:

```sh
sudo journalctl -u ome-appview.service -f -o cat \
  | grep --line-buffered 'Notification \(installation\|destination\|subscriptions\|registration\)'
```

The database is the durable confirmation. This query intentionally selects neither credential
fingerprints nor encrypted destination bytes:

```sh
sqlite3 /srv/ome-appview/data/appview/open-music-event-appview.sqlite \
  'SELECT i.id, r.applicationID, r.provider, COUNT(s.sourceID) AS subscriptions
   FROM pushInstallations AS i
   LEFT JOIN pushRegistrations AS r ON r.installationID = i.id
   LEFT JOIN pushSubscriptions AS s ON s.installationID = i.id
   GROUP BY i.id, r.applicationID, r.provider
   ORDER BY i.rowid DESC;'
```

For the temporary first-device acceptance deployment, anonymous bootstrap may be enabled before
edge rate limiting is installed. Treat that as an explicit short-lived exception: monitor the
installation count and add public-edge rate protection before broader distribution.

## Durable Notification Delivery

After a Tangled request is verified and recorded in the durable inbox, the route resolves current
subscriptions and commits idempotent `pushOutbox` rows before returning `202 Accepted`. Provider
network latency and failure are therefore outside the webhook request. Replaying the same source
version does not create duplicate installation deliveries.

A ServiceLifecycle-owned worker drains one due job at a time, awaits the provider response, and
records either delivery or a persisted exponential retry. Pending and failed jobs survive an
AppView restart, and graceful shutdown cancels provider work without recording cancellation as a
delivery failure. A short idle poll currently wakes the worker; replacing that poll with a database
observation wakeup remains a refinement. Permanent invalid-token classification and cleanup also
remain before broader production rollout.

AppView creates one provider-neutral delivery client from the routing file and host-owned
credentials. It routes APNs by application ID so OME and Wicked Woods receive the correct topic,
signs ES256 provider tokens on first use, and reuses each token for twenty minutes. It routes FCM
by application ID and exchanges the configured Google service-account key for a short-lived OAuth
access token with the Firebase Messaging scope. The access token is cached until one minute before
expiry. Supplying provider routes without all required credential paths fails server startup; FCM
also rejects a routing project ID that differs from the service account's project.

## Tangled Webhook Intake

`POST /webhooks/tangled` is installed only when
`OME_TANGLED_WEBHOOK_CONFIGURATION_PATH` points to a valid watch file. Keep repository and branch
metadata in the public server-configuration repository, for example:

```json
{
  "watches": [{
    "id": "wickedwoods.ca/ome-workspace#refs/heads/main",
    "hookID": 123,
    "repositoryDID": "did:plc:5df2u7ief6m6tn77jznicxob",
    "repositoryKey": "ome-workspace",
    "ref": "refs/heads/main",
    "sourceID": "at://did:plc:5df2u7ief6m6tn77jznicxob/app.openmusicevent.event/ome-workspace-2026"
  }]
}
```

The numeric `hookID` is assigned by Tangled; replace `123` with the created hook's ID. The public
`sourceID` must exactly match the source ID published by the app's mounted event feature, normally
the event's canonical AT URI. The verified Tangled `after` revision becomes that source's version.
The watch file never contains the webhook secret. AppView stores that secret as AES-GCM ciphertext
in its database, keyed by webhook source and watch ID. `OME_WEBHOOK_SECRET_KEY_PATH` names the
root-readable file containing the base64-encoded 32-byte deployment key used to protect those
database values; it is not the Tangled webhook secret.

For a new watch, create the Tangled hook as inactive with the production HTTPS URL, a generated
secret, and the `push` event selected. Record its assigned hook ID, publish the matching watch
metadata, and provision the exact secret into the AppView database for that watch ID before
activating the hook. Run the command with the same database, public configuration, and webhook-key
configuration as the service. It reads the secret from standard input and never prints it:

```sh
systemd-ask-password "Tangled webhook secret" \
  | OpenMusicEventAppView set-tangled-webhook-secret \
      --watch-id 'wickedwoods.ca/ome-workspace#refs/heads/main'
```

An unsigned or unknown hook must receive an authentication failure and must not enter the durable
inbox.

## Hosting Notes

- Preserve the incoming `Host` header; well-known file selection is host-based.
- Do not redirect `/.well-known/*` paths.
- TLS termination can happen before the Swift process, but public production URLs must be HTTPS.
- Restrict the SQLite file and its backups to the AppView service account. Lightsail disk encryption
  and snapshots protect the volume; application-level destination encryption additionally keeps
  provider tokens out of plaintext database rows.
- Keep `OME_NOTIFICATION_DESTINATION_KEY` in the Lightsail deployment environment or secret
  injection mechanism. Do not log the key, installation credentials, or provider tokens.
- Keep the APNs `.p8` key in the Lightsail/systemd credential mechanism, mount it read-only for the
  AppView service, and point `OME_APNS_PRIVATE_KEY_PATH` at that mounted file. Do not put the key
  contents in an environment variable or source-controlled configuration.
- Keep the Firebase service-account JSON under the same deployment credential controls, point
  `OME_FCM_SERVICE_ACCOUNT_PATH` at the mounted file, and never copy its private key into the
  provider routing JSON or environment.
- Keep the Tangled webhook master encryption key in the Lightsail deployment secret mechanism,
  and store each hook secret only through `set-tangled-webhook-secret` so AppView persists its
  ciphertext in SQLite. Do not commit either secret to the watch file, log request signatures, or
  log raw webhook payloads.
- Rate-limit `POST /notifications/v1/installations` at the Lightsail TLS proxy. The Swift service
  bounds credential, destination, source-ID, and subscription-set sizes, but the open bootstrap
  endpoint still needs request-rate protection at the public edge.
- Replace placeholder DIDs, Apple team/app IDs, Android package names, and Android signing fingerprints before production.
- Keep user handle claims dynamic later; these static files are only for official/root domains.

## Future Hosting Shape

- API handlers should remain stateless.
- Durable state should live in an external database, object storage, and a job queue.
- Jetstream ingestion and long-running reactors should run as workers, not inside request handlers.
- Lambda can host the stateless API later if the database/session/token/job dependencies are externalized.
