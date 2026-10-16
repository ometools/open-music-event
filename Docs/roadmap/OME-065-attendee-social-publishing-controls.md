---
id: OME-065
type: roadmap-card
area: social
kind: publishing
tags:
  - attendee
  - atproto
  - privacy
  - local-first
  - social
priority: high
created: "2026-06-17"
---

# Attendee Social Publishing Controls

## Summary

```gpt-5
Add a local-first Social tab where attendee activity works normally while logged out, then lets the attendee explicitly decide when and how local favorites, follows, likes, and attendance signals become public ATProto records after login.
```

## Why

```gpt-5
OpenMusicEvent's attendee experience should not treat login as consent to publish. Favoriting a performance, following an artist, liking something, or saving attendance intent should remain useful local app behavior before the attendee has an account connected.

When the attendee does log in, OME should show their local social records as reviewable, policy-driven publication candidates. The local record remains the source of truth. Public ATProto records are projections the attendee chose through an explicit action or policy.

This is distinct from organizer source publishing, OME product feedback, event-content correction flows, and during-event reporting. Those features can all use ATProto, but they do not own the attendee's private-to-public consent boundary.
```

## Rough Shape

```gpt-5
- Keep logged-out social behavior normal:
  - favorite performances, artists, stages, or events
  - follow artists, events, organizers, or communities where the app has local affordances
  - like or save local content where that helps the attendee navigate
  - express attendance interest without requiring an account
- Treat login as enabling account capabilities, not publishing:
  - discover and store the selected account identity
  - read relevant public records when authorized
  - prepare publish actions
  - never publish existing local records as a side effect of login
- Add a Social tab focused on local-to-public review:
  - group records by event and record kind
  - show local value, publication status, selected policy, and public record reference when published
  - offer publish, keep private, ignore, retry, and policy update actions
  - support bulk actions only when the affected event and record kind are clear
- Default publication policies are scoped by event plus record kind:
  - "For Wicked Woods, publish artist follows"
  - "For Wicked Woods, keep favorites private"
  - "For this event, ask before publishing likes"
  - global defaults can seed new events later, but should not replace event-scoped control
- Allow record-level overrides:
  - publish this one favorite
  - keep this one follow private even if the event policy publishes future follows
  - ignore this old local record without deleting it
- Model publication as a projection lifecycle:
  - local-only
  - publishable / draft
  - publishing
  - published with AT URI, CID, and last published timestamp
  - failed with retry context
  - ignored or intentionally private
- Use portable ATProto/community records only where the semantics are actually shared. Use OME-native records for event-specific attendee signals that need OME context.
- Keep AppView projection separate from the device-local source of truth. AppViews can combine public records later, but they must not imply that private local records exist.
- Keep this connected to, but separate from:
  - [[OME-017-atproto-oauth-authentication|OME-017: ATProto OAuth Authentication]]
  - [[OME-027-real-atproto-record-publishing|OME-027: Real ATProto Record Publishing]]
  - [[OME-040-pds-account-provider-onboarding|OME-040: PDS / Account Provider Onboarding]]
  - [[OME-041-appview-auth-and-scope-model|OME-041: AppView Auth and Scope Model]]
  - [[OME-059-community-calendar-appview-ingestion|OME-059: Community Calendar AppView Ingestion]]
  - [[OME-064-openmusicevent-feedback-board|OME-064: OpenMusicEvent.app Feedback Board]]
```

## Swift Sketch

```swift
enum AttendeeSocialRecordKind: String, Codable, Sendable {
  case eventFavorite
  case eventFollow
  case artistFavorite
  case artistFollow
  case performanceFavorite
  case performanceLike
  case attendanceInterest
}

struct SocialPublicationPolicy: Codable, Equatable, Sendable {
  var eventID: OME.Event.ID
  var recordKind: AttendeeSocialRecordKind
  var defaultAction: SocialPublicationDefaultAction
}

enum SocialPublicationDefaultAction: String, Codable, Sendable {
  case keepPrivate
  case askBeforePublishing
  case publishFutureRecords
  case neverPublish
}

struct SocialPublicationRecord: Codable, Equatable, Sendable {
  var localID: String
  var eventID: OME.Event.ID
  var recordKind: AttendeeSocialRecordKind
  var localRecordReference: LocalRecordReference
  var policyOverride: SocialPublicationDefaultAction?
  var state: SocialPublicationState
}

enum SocialPublicationState: Equatable, Sendable {
  case localOnly
  case publishable
  case publishing
  case published(atURI: String, cid: String?, lastPublishedAt: Date)
  case failed(message: String)
  case ignored
}
```

## Acceptance Criteria

```gpt-5
- Attendees can favorite, follow, like, save, or express attendance intent while logged out.
- Logging in does not publish any existing local social record.
- The Social tab lists local social records grouped by event and record kind.
- The default policy model supports event plus record kind scoping.
- Individual local records can override the event plus record-kind policy.
- Published projections store enough public reference data to reconcile, retry, or show where the record exists.
- The first implementation slice can be tested with a fake publisher and local records before requiring live ATProto writes.
```

## Open Questions

```gpt-5
- Which record kinds should be in the first attendee slice: favorites, follows, likes, attendance interest, saved artists, saved performances, or only one narrow path?
- Which social actions should map to shared portable records, and which need OME-native event-context records?
- What should "unpublish" mean for each record type: delete the ATProto record, mark an OME record inactive, publish a tombstone, or only stop future updates?
- How should OME reconcile public records that already exist on the user's account before the local app knows about them?
- Should global defaults exist in v1, or should the first version be strictly per event plus record kind?
- What language best explains that public ATProto records may be indexed or copied by other services after publication?
```

## Next Step

```gpt-5
Read the current local attendee activity models, then sketch the smallest Social tab state model that can list one event's local favorites/follows and apply an event plus record-kind publication policy through a fake ATProto publisher.
```
