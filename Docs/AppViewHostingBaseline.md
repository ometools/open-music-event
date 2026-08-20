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
OME_APPVIEW_PUBLIC_HOST=openmusicevent.app
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
OME_SOURCE_ARTIFACT_S3_BUCKET=resources.openmusicevent.app
OME_SOURCE_ARTIFACT_S3_REGION=us-east-1
OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN=https://resources.openmusicevent.app
AWS_ACCESS_KEY_ID=<source-artifact-writer-access-key>
AWS_SECRET_ACCESS_KEY=<source-artifact-writer-secret-key>
AWS_SESSION_TOKEN=<optional-session-token>
```

`OME_APPVIEW_HOST` is the local bind address. `OME_APPVIEW_PUBLIC_HOST` is the AppView hostname
advertised by XRPC catalog records; staging must set it to `stg.openmusicevent.app`. Bundled catalog
entries identify their canonical Tangled repository record key. When a configured webhook watch has
the same organizer ID and repository record key, the catalog advertises the durable published
artifact recorded for that watch's current revision while preserving the organizer, event, channel,
and post IDs. The existing `resolvedRepository` response shape does not change, so clients require
no S3-specific behavior.

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
      "environment": "production",
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

Use `development` for an application ID whose tokens come from Xcode development builds and
`production` for an application ID distributed through TestFlight or the App Store. APNs routing
is selected independently for every registered application ID; FCM routes each application ID to
its configured Firebase project and has no APNs-style sandbox host. The routing file contains no
private key or service-account JSON.

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
    "id": "woody.fm/wicked-woods-ome-stg#refs/heads/main",
    "hookID": 123,
    "repositoryOwnerDID": "did:plc:cqqtuv75m7e5s4uj6nw4czyu",
    "repositoryKey": "wicked-woods-ome-stg",
    "ref": "refs/heads/main",
    "canonicalSource": {
      "organizerID": "did:plc:5df2u7ief6m6tn77jznicxob",
      "repositoryRecordKey": "ome-workspace"
    },
    "artifactRepository": {
      "owner": "wickedwoods.ca",
      "repository": "ome-workspace"
    }
  }]
}
```

The numeric `hookID` is assigned by Tangled; replace `123` with the created hook's ID. `id` is the
AppView's stable local key for this physical watch and its checkpoint; conventionally use the
Tangled repository path plus ref. It is not an organizer or source identity. The public watch
separates the remaining two identities. `repositoryOwnerDID`, `repositoryKey`, and `ref` identify
the physical Tangled repository that signs the webhook and supplies bytes. `canonicalSource`
identifies the organizer and `sh.tangled.repo` record whose stable namespace those bytes represent.
`artifactRepository` selects the stable public path beneath
`OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN`. This lets staging watch a fork without changing the organizer,
event, channel, post, or published repository identities seen by clients. One source repository can
contain multiple events; AppView projects all of them. Configure at most one authoritative physical
watch and artifact path for the same canonical source in an environment.

AppView downloads each exact Tangled revision once, validates those archive bytes, publishes those
same bytes to the immutable S3 key
`<artifact owner>/<artifact repository>/archive/<revision>.tar.gz`, and only then stores the
revision, S3 reference, checksum, byte count, and communication-post identities in its primary
SQLite database. The checkpoint update and notification outbox inserts share one transaction. An
S3 upload failure therefore cannot advance the advertised revision or enqueue a refresh. Only
installations subscribed to that canonical channel route receive the signal. The first processed
push compares `before` and `after`, so posts that already existed before AppView was deployed do not
produce a historical notification burst; a replay of the same `after` revision performs no source
download or upload and creates no duplicate outbox row.

This first projection treats a newly added communication-post identity as notification-worthy.
Editing or deleting an existing post does not enqueue another notification. Each new post enqueues
one visible `content` message per subscribed installation, and each affected channel also enqueues
one background `source_available` refresh per subscribed installation for that source revision.

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

### Artifact cutover and backfill

Grant the AppView service identity `s3:PutObject` only for the configured artifact bucket/prefix.
Keep its AWS secret out of the public watch file and service logs. The published objects are
content-addressed by source revision, carry a SHA-256 checksum, and are served through
`OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN`.

The new catalog intentionally fails closed for a configured watch whose current checkpoint has no
published-artifact metadata; it never falls back to Tangled. During deployment, stage the new
executable and configuration, keep the new service process stopped, and run:

```sh
OpenMusicEventAppView backfill-source-artifacts
```

The command uses every configured watch's existing checkpoint, validates and uploads its exact
revision, then repairs the checkpoint without producing notifications. It is idempotent: a watch
that already has complete publication metadata is reported without another download or upload.
Verify each reported S3 object, checksum, and database row before starting or restarting the new
service. Then query the catalog and confirm that `resolvedRepository.reference` is beneath the
configured public origin and `resolvedRepository.ref` is the checkpoint's exact revision.

## Non-Device Production Acceptance

The first production acceptance pass deliberately stops before provider success or device delivery.
Run it in a canary AppView process using the exact production executable, provider configuration,
and credentials, but give it a separate SQLite database, a dedicated Tangled test watch/source, and
synthetic APNs and FCM destinations. Do not copy a real installation credential, provider token, or
production outbox row into the canary database.

Record the executable hash, OME revision, resolved Notifications/Atmosphere/JWSETKit revisions,
configuration-file hashes, canary database path, service start time, and Tangled delivery ID before
the run. Keep the provider configuration values in that record, but never copy the APNs private key,
FCM service-account private key, webhook secret, installation credential, or encrypted destination.

| Boundary | Production action | Required evidence |
| --- | --- | --- |
| Startup | Start the canary with production provider credentials and routing, its own database, and one dedicated watch. | Startup succeeds; `/healthz` and `/readyz` succeed; Wicked Woods selects APNs `production`, topic `com.Festivl.WickedWoods`, and the intended FCM project. |
| Registration | Create a synthetic installation through the public route, then replace its APNs or FCM destination and subscribe it to the canary channel route. | The API returns success; one installation, registration, and subscription survive restart; neither the credential nor destination appears in logs or plaintext database searches. |
| Webhook authentication | Send one correctly signed Tangled `push`, one bad signature, and one exact replay. | The signed request returns `202`; the bad signature is rejected and never enters the inbox; the replay does not add an inbox delivery, projection change, or outbox row. |
| Source projection | Add one new canary communication post while also editing one existing post and deleting another. | The checkpoint advances to the exact `after` revision; the post-identity projection matches that revision; only the new post creates visible content; the affected channel gets one silent refresh. |
| Subscription fan-out | Keep one synthetic installation subscribed to the canary channel and one subscribed only to the event. | Only the channel subscriber receives canary outbox rows. Each row records the canonical channel source, exact revision, and canonical post route. |
| Provider edge | Let the worker send a syntactically valid but nonexistent destination through the real APNs or FCM endpoint. | The complete status and sanitized provider error identify only the nonexistent recipient. APNs must not report provider-token or topic-authorization errors. FCM must not report OAuth, permission, or project-routing errors; a generic `INVALID_ARGUMENT` is insufficient because it can also identify a malformed message contract. A recipient rejection is expected and is not delivery success. |
| Retry and restart | Stop the canary after the failed provider attempt, restart it with the same database, and observe the job again. | `failedAttempts`, `lastAttemptAt`, and `nextAttemptAt` persist; the same outbox identity is retried; no duplicate job is inserted. |

Use the canary database to capture the durable proof without selecting encrypted destination bytes or
credential fingerprints:

```sh
sqlite3 /srv/ome-appview/data/canary/open-music-event-appview.sqlite \
  'SELECT watchID,
          repositoryDID AS repositoryOwnerDID,
          repositoryKey,
          ref,
          sourceID AS canonicalSourceReference,
          revision,
          artifactReference,
          artifactObjectKey,
          artifactChecksumSHA256,
          artifactByteCount,
          artifactPublishedAt
   FROM tangledSourceRevisions;
   SELECT sourceID, sourceVersion, reason, failedAttempts,
          lastAttemptAt, nextAttemptAt, deliveredAt
   FROM pushOutbox
   ORDER BY id;'
```

Archive the sanitized service log, HTTP statuses, provider error classifications, and SQL output as
one acceptance artifact. Preserve the canary database until the evidence is reviewed; then retire
the canary watch and service explicitly rather than repointing either one at the production database.

This pass does **not** prove provider `2xx` acceptance, physical-device receipt, foreground or
background OS handling, badge changes, alert presentation, or tap routing. Those require a real
release installation and are the next acceptance stage. Permanent invalid-destination
classification and cleanup must be implemented before the synthetic provider rejection can run in a
shared production outbox or before notifications are distributed broadly.

The synthetic APNs rejection also cannot independently prove the sandbox/production selection:
`BadDeviceToken` can mean either a nonexistent token or a token sent to the wrong environment. This
pass records and reviews the configured production host; the first real TestFlight token is the
environment proof. For FCM, retain the provider's structured error details and require a documented
unknown-recipient classification. Do not treat a bare HTTP `400` or `INVALID_ARGUMENT` as evidence
that the server reached recipient lookup.

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
- Scope the AWS source-artifact writer credentials to the configured S3 bucket/prefix. Keep
  `AWS_SECRET_ACCESS_KEY` and any `AWS_SESSION_TOKEN` in the service credential injection mechanism;
  do not put them in the Tangled watch JSON or logs.
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
