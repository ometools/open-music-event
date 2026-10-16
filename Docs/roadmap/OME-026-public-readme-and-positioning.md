---
id: OME-026
type: roadmap-card
area: docs
kind: positioning
priority: medium
created: "2026-06-09"
---

# Public README and Positioning

## Summary

Position OpenMusicEvent as a high-quality native event app with open, reusable event data underneath.

## Why

The public story should lead with app quality, organizer usefulness, and the "write once, display everywhere" value of public event data. ATProto, Tangled, source repositories, Skip, and SQLite are supporting infrastructure, not the headline.

OpenMusicEvent should not sell infinite customization. The first-party app should stay focused and useful, while public ATProto records and AppView projections let others build alternate websites, embeds, branded presentations, or custom experiences on top of the same data.

## Rough Shape

- Present ATProto, Tangled, source repositories, Skip, and SQLite as supporting infrastructure.
- Keep public-facing copy practical and app-first.
- Position OME around a clear product split:
  - open data
  - focused official app
  - precise branding controls
  - public display surfaces
  - permissionless third-party rendering
- Avoid implying that organizers need to manage source files directly. The app is the authoring surface; source and protocol records are persistence, collaboration, audit, and distribution machinery.
- Avoid positioning OME as a generic page builder or infinitely customizable event CMS. The official app should feel authored and tool-like.
- Use "write once, display everywhere" to connect native app surfaces, public web, QR/App Clip entry, embeds, AppView queries, and social/protocol reuse.
- Code pointers: `README.md`, `Android/fastlane/metadata/android/en-US`, `Darwin/fastlane/metadata/en-US`.

## Open Questions

- Which audience should the public README prioritize next: attendees, organizers, or developers?
- What is the shortest wording for "open data, focused app" that does not sound like protocol marketing?
- Which public examples best prove write-once/display-everywhere: native app, web event page, schedule embed, QR route, or third-party rendering?

## Next Step

- Draft the first app-store/README positioning pass around "open data, focused app" and test whether it still reads as a useful event app for non-technical organizers.
