---
id: OME-064
type: roadmap-card
area: feedback
kind: package
tags:
  - atproto
  - userinput
  - feedback
  - appview
priority: medium
created: "2026-06-17"
---

# OpenMusicEvent.app Feedback Board

## Summary

Create a reusable Swift package for UserInput.app-shaped ATProto feedback records, then use it to power an OpenMusicEvent.app feedback board.

## Why

OpenMusicEvent needs a public place for product feedback that is not tied to a single event source repository. Bugs, feature suggestions, account friction, app-store/tester feedback, documentation confusion, and platform-specific issues should flow into an OME product board where users can post, discuss, vote, and follow status.

That is distinct from event content feedback. "The schedule time is wrong" or "this artist bio needs an update" may start from the same intake affordance, but it should be routed toward organizer-owned event data and source-editing workflows instead of becoming generic product backlog.

During-event reporting is a separate problem again. Safety reports, medical issues, harassment reports, lost items, staff needs, and operational incidents need private, urgent, and event-owned handling. Do not model those as public UserInput voting threads.

## Rough Shape

- Start with a new sibling Swift package, tentatively `swift-userinput-atproto`, instead of adding UserInput models directly to the OME app package.
- Model the observed UserInput.app record families as the package's core surface:
  - `app.userinput.space`
  - `app.userinput.discussion`
  - `app.userinput.reply`
  - `app.userinput.upvote`
  - `app.userinput.downvote`
  - `app.userinput.status`
  - `app.userinput.member`
  - `app.userinput.pin`
  - `app.userinput.hide`
  - `app.userinput.ban`
  - `app.userinput.lock`
  - `app.userinput.edit`
  - notification/history helpers such as checked notifications and visited boards only after the core board is useful
- Keep the reusable package UserInput-focused:
  - lexicon constants and OAuth scope helpers
  - Codable record models
  - AT URI/CID/reference helpers
  - board/thread/status projections
  - read/write client protocols later, without OME source-editing knowledge
- Add an OME adapter later that classifies feedback scope:
  - OpenMusicEvent.app product feedback
  - event content feedback tied to an event, source file, record URI, or route
  - explicit non-goal for during-event incident reporting
- Create the first canonical board: `OpenMusicEvent.app Feedback`.
- Use initial categories/tags such as `bug`, `feature`, `ios`, `android`, `account`, `event-content`, `docs`, and `accessibility`.
- Treat UserInput.app's schema as the v1 canonical feedback shape. ATProto records are public, referenceable by AT URI, and projectable through adapters, so migration to a future shared schema should be feasible if another record family becomes a better fit.
- Keep reads projected through the OME AppView once this is inside the app, so the app can normalize UserInput records, classify event-content suggestions, and preserve migration flexibility.
- Keep QR and support entry points separate:
  - feedback board links can come from settings, about, tester flows, and non-urgent QR targets
  - operational or safety reporting gets a separate reporting system

## Acceptance Criteria

- A new Swift package exists for UserInput-shaped ATProto feedback records, independent of OME app/source-editing code.
- The package exposes collection identifiers, OAuth scope strings, Codable record models, and projection types for board/thread rendering.
- OME has a roadmap-level integration plan for the OpenMusicEvent.app product feedback board.
- The plan clearly separates OME product feedback, event content feedback, and during-event incident reporting.
- The first implementation slice can be tested without requiring a live ATProto write path.

## Open Questions

- Should `OpenMusicEvent.app Feedback` live under an OME-controlled DID, an `openmusicevent.app` handle, or another operational account?
- Which UserInput.app record fields should be treated as stable enough for v1, and which should stay behind tolerant decoding?
- How should event content feedback link back to source-controlled records: event AT URI, source path, route, source proposal, or all of the above?
- Should event content feedback appear in the same public board with `event-content` tags at first, or should it get a separate board once source routing exists?
- What is the minimum moderation surface needed before the board is public: status, pin, hide, ban, lock, moderator membership, or all of them?

## Next Step

Scaffold `swift-userinput-atproto` with the core UserInput record models and projection helpers, then add a focused package test suite before wiring it into the OME app.
