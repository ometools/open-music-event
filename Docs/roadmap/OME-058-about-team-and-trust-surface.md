---
id: OME-058
type: roadmap-card
area: app
kind: polish
tags:
  - chrome
  - trust
  - identity
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# About, Team, and Trust Surface

## Summary

```gpt-5
Create a real About surface that explains OpenMusicEvent, links developer and team profiles, exposes project/support/source links, and still works when event or organization metadata is sparse.
```

## Why

```gpt-5
The app needs a trust surface beyond store metadata. Attendees, organizers, contributors, and testers should be able to tell who built the app, where the event data comes from, how to get support, and what version they are using without leaving the native app.
```

## Rough Shape

```gpt-5
- Add an About entry from settings or app chrome with project description, developer/team profiles, support links, source/project links, privacy/local-data notes, version/build info, and acknowledgements.
- Support hydratable event and organization content: organizer profile, website, social/profile links, source repository, privacy/support links, and event-specific attribution.
- Provide polished fallback content for underhydrated apps: generic OpenMusicEvent description, default developer/team links, default support/source links, and clear missing-metadata behavior.
- Keep app developer/team profiles separate from event contributor profiles, while linking to contributor surfaces where that helps explain event data.
- Make the surface useful for screenshots, trusted testers, and white-label handoff without turning it into marketing copy.
- Code pointers: `Sources/OpenMusicEvent`, `Sources/OpenMusicEventAppEventViewer`, `Sources/OpenMusicEventAuthentication`.
```

## Open Questions

```gpt-5
- Which developer/team profiles should ship in the generic OpenMusicEvent fallback?
- Which profile/link fields should be static app metadata, source-backed event/org metadata, or fetched ATProto profile data?
- Should About be a single global screen, an event-scoped screen, or a global screen with event/org sections?
- Which privacy, support, and source links are required before TestFlight or trusted tester rollout?
```

## Next Step

```gpt-5
Inventory the current settings/about surfaces and define the minimum generic About content needed for a polished Wicked Woods tester build.
```
