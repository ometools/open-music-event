---
id: OME-067
type: roadmap-card
area: appview
kind: notifications
tags: [appview, notifications, emergency-alerts, critical-alerts, deep-linking, xrpc, apns, fcm]
priority: high
created: "2026-07-20"
---

# AppView Push Notification Delivery

## Summary

Define account and anonymous installation registration, private notification preferences, durable AppView delivery, and a canonical attendee navigation target for every actionable notification. Use direct APNs delivery for Apple registrations, direct FCM delivery for Android registrations, and first-class emergency alerts that target Apple Critical Alerts in the 2026 applications.

## Why

Attendees need event, channel, and emergency notifications before they create or connect an ATProto account. Following Bluesky's service boundary, push registrations, notification preferences, subscriptions, any future seen state, and delivery state remain private AppView data even when an installation is associated with an authenticated DID; they are not public repository records. The announcement or emergency alert that causes a notification remains an ATProto record and the AppView projection remains rebuildable. Ingest therefore needs a durable boundary: deciding that a notification exists belongs with AppView projection, while network delivery must happen after commit in a retryable worker.

## Decisions

- Support both push providers directly. Apple installations register an APNs destination and Android installations register an FCM destination; the AppView does not route Apple delivery through FCM.
- Model the provider and its registration data as one typed union, such as `Push.Destination.apns(APNS.Registration)` and `.fcm(FCM.Registration)`. Do not transport independent `platform`, `token`, and `appID` strings that can form invalid combinations.
- Keep APNs and FCM tokens as distinct string-encoded types. Each provider registration carries the app/topic identifier needed to select server-side credentials; deployment environment and credentials remain trusted server configuration.
- Copy Bluesky's service-state ownership rather than publishing subscriber preference records. Keep push registration, notification preferences, event/channel subscriptions, and any later seen state behind notification XRPC methods and out of user repositories.
- Split destination registration from notification preferences. Start with a small surface analogous to Bluesky's `registerPush`, `getPreferences`, and `putPreferences`: registration creates or updates one installation and handles token refresh; preferences replace that subscriber's desired event/channel subscriptions.
- Accept OAuth when an account is present and associate the installation and preferences with that DID. Without OAuth, authorize the same surface with the installation capability. Notification delivery must never require an ATProto account.
- Identify an installation with an opaque installation-scoped capability stored in Keychain or the Android secure-storage equivalent. An ATProto DID may be associated later but is never required to register for event notifications.
- Use `@Dependency(\.defaultDatabase)` for XRPC operations, ingest, projections, and delivery workers. Do not introduce a parallel notification database dependency. A scoped database value may be passed only inside the active transaction opened on `defaultDatabase`.
- Separate rebuildable projection tables from correctness-critical operational tables inside the database reached through `defaultDatabase`. Rebuilding or replacing the AppView projection must preserve registrations, preferences, subscriptions, the notification delivery cursor, outbox rows, and delivery deduplication state.
- Keep the first durable operational schema to `PushRegistration`, `PushPreference`, `PushSubscription`, `PushOutbox`, and the smallest delivery ledger needed for idempotency. Do not add a server-side notification inbox, read state, unread counts, or notification-history XRPC surface until the product needs them.
- Let the ingest projection decide which installations should receive a notification and insert idempotent outbox rows in the same transaction as normalized projection and checkpoint advancement. Include source URI, CID, sequence, and notification reason in the projection context.
- Use a uniqueness rule such as installation plus source URI/CID plus reason so replayed or stale source events cannot enqueue duplicate delivery.
- Keep projection rebuild and historical backfill side-effect free. Only delivery-eligible ingest after the durable notification cursor may enqueue outbox work; catch-up after an outage remains delivery-eligible, while an explicit projection rebuild does not resend historical notifications.
- Use database observation only to wake the outbox worker after committed changes. Do not make observation or a SQL trigger the source of notification policy, and do not send APNs or FCM requests directly from an ingest callback.
- Run delivery in a long-lived worker with awaited sends, bounded concurrency, cancellation and shutdown participation, retry/backoff, provider response recording, and permanent invalid-token cleanup.
- Keep the provider endpoint and attendee navigation target as separate domain concepts. `Push.Destination` selects an APNs or FCM registration; a provider-neutral `Notification.Target` identifies the content the attendee should see.
- Give `Notification.Target` the stable public source AT URI and canonical HTTPS URL needed to open the exact event surface. The OME projection owns constructing an OME `AppRoute`; the shared notifications package transports the resulting target without learning OME application routes.
- Snapshot the complete notification target onto `PushOutbox` when the delivery is enqueued. Retries send that stored target unchanged rather than re-deriving a possibly different route from mutable projection state.
- Keep push payloads small and routeable. Preserve the canonical target through APNs and FCM payload encoding, then feed notification taps through the same top-level `openURL` -> `AppRoute` -> `NavigationRequest` path used by Universal Links. Do not add a provider-specific navigation router.
- Let the app hydrate current display content from the source URI and route identity. Content-update notifications keep the stable route while the outbox source CID establishes which mutation caused delivery; tapping opens the current projected version rather than trusting stale display text from the push.

## Emergency Alerts

- Make an emergency alert a first-class organizer-authored ATProto record rather than an ordinary channel post with transport metadata such as `sendPush`.
- Give an emergency alert an explicit lifecycle, including `active`, `resolved`, and `cancelled`, plus issued, expiration, and supersession information. An all-clear is a real alert transition that can produce its own notification.
- Treat event emergency routing as mandatory service policy. Every active installation registered for an event receives its emergency alerts regardless of optional channel preferences; OME does not present an in-app emergency opt-out, while the operating system retains its notification controls.
- Keep OME topics as AppView routing concepts rather than APNs or FCM provider topics. Resolve recipients per installation so authorization, audit, retry, idempotency, and invalid-token cleanup remain explicit.
- Require the Apple Critical Alerts entitlement for every shipping 2026 App ID that can issue emergency alerts. Request critical-alert authorization in context and map eligible emergency delivery to the APNs critical interruption level and critical sound behavior.
- Treat entitlement rejection, missing critical authorization, or disabled notifications as degraded operating conditions rather than alternative product targets. Preserve an in-app active-alert surface and document the exact fallback behavior without representing fallback delivery as critical.
- Deliver Android emergencies with high-priority FCM through a dedicated high-importance `Emergency alerts` Android notification channel. Document the user-controlled permission, importance, and Do Not Disturb limits rather than claiming the application can override them.
- Prioritize emergency outbox work ahead of ordinary notification backlog, give it a short expiration, and never deliver an expired emergency alert as if it were current.
- Route active, superseded, resolved/all-clear, and cancelled emergency notifications to the exact alert detail or active-alert surface for that source record. If the record is no longer locally available, show an explicit event-scoped unavailable/resolved fallback rather than silently opening a generic notifications screen.

## Provider Configuration

- Configure APNs signing material, key ID, team ID, topic, and sandbox/production routing in the service environment or secret store. Do not accept credential or environment selection from the registration request.
- Apply for, provision, and verify the Apple Critical Alerts entitlement against each exact shipping App ID and distribution profile before emergency delivery is considered release-ready.
- Configure FCM HTTP v1 credentials and project/application routing in the service environment or secret store.
- Maintain an allowlist that maps each OME or white-label application identifier to its APNs topic or FCM project. Reject unknown application identifiers before persisting a registration.
- Classify provider responses into provider-accepted, retryable, and permanently invalid registration outcomes so the worker can update `PushOutbox` and `PushRegistration` deterministically. Provider acceptance is not proof that a device displayed the notification.

## Required Composable Atmosphere Work

- Preserve record CID as well as URI and sequence when Jetstream commits become `AppView.RecordEnvelope` values.
- Add a transactional typed projection hook that runs with the index and checkpoint write against `defaultDatabase`.
- Keep post-commit reactions separate for effects that do not establish durable product state.
- Add the provider-neutral notification target and payload codec to the shared notifications package. APNs and FCM adapters must preserve the canonical URL and source URI exactly while adding only provider-specific envelope fields.
- Add an XRPC server registration surface that derives method/path, input decoding, output encoding, and authorization policy from the request type while operations continue to read `defaultDatabase` through Dependencies.

## Validation

- Prove an installation can create and update a push registration and preferences without OAuth or an account DID, using its installation capability.
- Prove an authenticated installation associates the same private service state with its DID without creating notification preference or subscription records in the account repository.
- Snapshot the registration and preference XRPC request and response JSON, including the typed APNs/FCM Lexicon union and the OAuth-or-installation-capability authorization policy.
- Prove token refresh replaces the destination without duplicating subscriptions, and an empty desired subscription set disables delivery.
- Ingest one approved announcement through a real `RecordEnvelope` and assert indexed record, normalized projection, checkpoint, and matching outbox rows commit together.
- Prove announcement, content-update, and emergency projections enqueue the exact canonical event, channel, announcement, or alert target expected for their source record.
- Snapshot APNs and FCM payload JSON and prove each provider preserves the outbox target's source URI and canonical HTTPS URL unchanged.
- Replay the same URI/CID/sequence and prove no duplicate outbox row is created.
- Rebuild the projection and prove subscriptions and delivery history remain intact while historical records produce no new outbox work.
- Prove optional-channel opt-out prevents enqueueing, while event emergency policy still reaches every active event installation.
- Exercise active, superseded, resolved/all-clear, cancelled, and expired emergency alerts. Prove ordinary backlog cannot starve an emergency and expired alerts are not delivered.
- Exercise APNs and FCM transports independently with raw HTTP transcript fixtures, including success, retryable failure, and permanently invalid token responses.
- Prove the outbox worker awaits provider responses, respects bounded concurrency, retries without duplicating a provider-accepted job, and exits cleanly on cancellation.
- Drive notification responses through the app's real `openURL` boundary and prove cold-start, warm-app, and foreground taps select the exact event feature and nested channel, announcement, or emergency-alert detail.
- Start with the target content absent locally and prove the app hydrates it before navigation. Exercise deleted, expired, private, and malformed targets and assert a human-readable event-scoped fallback instead of a dropped tap or unrelated screen.
- On physical Apple devices, drill emergency delivery with Critical Alerts authorized under mute and Focus, then verify the documented degraded behavior when critical or general notification permission is denied.
- On physical Android devices, drill emergency delivery with the dedicated channel at high importance, then verify and document behavior when notification permission, channel importance, or Do Not Disturb settings prevent presentation.

## Open Questions

- Should the client generate the first installation capability, or should an open create call return a server-issued capability for subsequent updates?
- Which request limits or platform-attestation checks are necessary for the first public anonymous registration endpoint?
- When an anonymous installation signs in or an account signs out, which event/channel preferences remain installation-scoped and which move to or from the DID-scoped private service state?
- Should required channels be expanded into stored subscriptions at registration time or evaluated from current channel policy during ingest?
- When does a server-side notification inbox become useful enough to justify list, unread-count, and seen-state XRPC methods?

## Next Step

- Define the `Push.Destination` Lexicon union, provider-neutral `Notification.Target`, and registration and preference XRPC requests. Then model the durable operational tables and projection-rebuild boundary before enqueueing one idempotent ordinary notification and one prioritized emergency notification with canonical routes that round-trip through the OME app.
