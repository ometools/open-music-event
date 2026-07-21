---
id: OME-061
type: roadmap-card
area: appview
kind: integration
tags: [atproto, opensocial, communications]
launch: wicked-woods
priority: high
created: "2026-06-11"
---

# OpenSocial Community Communications

## Summary

Plan the OpenSocial-backed communications surface for public event announcements, writer membership, channel permissions, moderation, and notification triggers.

## Why

OpenMusicEvent needs a public announcements surface where non-logged-in users can always read, trusted contributors can write, and the main media manager can control approval before anything is treated as official. OpenSocial can own the general community shape while OME keeps the festival-specific content projection, notification policy, and source-controlled event data boundaries.

## Rough Shape

- Create a reusable `OpenSocialCommunity` Swift package outside the app repo for OpenSocial profile, admin, membership, list, list item, shared content, record reference, and webhook models.
- Add a thin OME adapter that maps an event or organizer to an OpenSocial community DID, maps OpenSocial lists to OME channels, and projects public records into the app/web announcements surface.
- Keep canonical event data in source control; keep community profile, members, admins, writer permissions, channel lists, and public comms content in OpenSocial.
- Use `site.standard.document` as the preferred longform announcement envelope, with `content` carrying a compatible body format such as `at.markpub.markdown` when the announcement needs structured text.
- Use `app.bsky.feed.post` only as a short social mirror, reply target, or discussion surface; do not make Bluesky posts the canonical official comms object.
- Wrap published documents or posts with OpenSocial `sharedContent` and list/listitem records so OpenSocial handles community membership, channel placement, and admin removal.
- Keep a small OME policy layer for official status, channel-to-push routing, priority, pinning, expiry, and notification requirements. Add an OME-owned announcement record only if `site.standard.document` plus policy metadata cannot carry the old comms semantics.
- Make public reads go through the OME AppView projection, not directly through app-side OpenSocial credentials. The mobile app should not contain an OpenSocial API key.
- Feed OpenSocial record create/update/delete events through the AppView ingest boundary. The AppView verifies community, list/channel, publisher DID, approval state, and notification policy before atomically enqueueing eligible deliveries; a separate worker sends through direct APNs or FCM providers after commit.
- Treat webhooks as one possible source adapter or wake-up mechanism, not as the owner of notification policy or direct push delivery.
- Treat membership as writer access. Non-members read the public projection; trusted contributors such as ANKORS receive membership and channel/list-specific write capability.
- Let the media manager be an OpenSocial admin/moderator for the event community. If OpenSocial supports per-list approval/status records, use that first; otherwise store the per-channel capability and approval projection in the OME adapter.
- Code pointers: `Docs/roadmap/OME-028-appview-indexing-service.md`, `Docs/roadmap/OME-041-appview-auth-and-scope-model.md`, `Docs/roadmap/OME-042-appview-query-surface.md`, `Docs/roadmap/OME-067-appview-push-notification-delivery.md`, `Docs/roadmap/OME-039-organizer-authority-and-review-permissions.md`, `Sources/OpenMusicEventLexicon/MusicEvent.swift`, `Sources/OpenMusicEventAppEventViewer/CommunicationsViewer.swift`, and the future `OpenSocialCommunity` package.

## Open Questions

- Does OpenSocial expose enough per-list/channel permission and moderation state to model ANKORS-style channel-specific writers without an OME-side permission table?
- Should the media manager approval state live as an OpenSocial list item status, an OME AppView projection flag, or both?
- Is `site.standard.document` plus OME policy metadata enough for v1 official announcements, or do we need an OME-owned `announcement` record immediately?
- Which Wicked Woods channels should exist first, and which of them can trigger push notifications?
- Which source adapter supplies the record URI, CID, publisher, approval, and channel context required by the AppView projection?

## Next Step

- Draft the first projection contract for one OpenSocial shared longform announcement: community DID, list URI, shared content URI/CID, source document URI/CID, content kind, publisher DID, approval state, and notification policy.
