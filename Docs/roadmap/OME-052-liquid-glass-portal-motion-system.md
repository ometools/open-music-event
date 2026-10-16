---
id: OME-052
type: roadmap-card
area: app
kind: motion
tags:
  - ios
  - identity
  - motion
  - accessibility
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# Liquid Glass Portal Motion System

## Summary

```gpt-5
Use iOS Liquid Glass and restrained custom motion to turn the logo's portal/refraction idea into reusable product moments.
```

## Why

```gpt-5
The portal is the strongest bridge between the logo and the app experience. It can express opening an event, importing source data, syncing, auth handoff, loading, and moving between community contexts without making every screen visually loud.
```

## Rough Shape

```gpt-5
- Identify the few right places for refraction: app launch, event open transition, import/sync, auth handoff, QR scanning, empty/loading states, and maybe live-now schedule affordances.
- Prefer native Liquid Glass, system materials, and platform animation where they can carry the effect.
- Build a small portal/refraction component only where system materials are not enough.
- Include reduced-motion and reduced-transparency fallbacks from the first pass.
- Keep Android behavior conceptually aligned without requiring iOS-only glass effects.
- Code pointers: `Darwin`, `Sources/OpenMusicEvent`, `Sources/OpenMusicEventAppEventViewer`.
```

## Open Questions

```gpt-5
- Which single transition should prove the motion language first?
- How far can native Liquid Glass carry the refraction before a custom component is needed?
- Should any portal animation respond to real music or schedule data later, or stay purely state-driven for v1?
```

## Next Step

```gpt-5
Prototype one restrained portal/refraction moment in a non-critical loading or event-open state, with reduced-motion behavior defined alongside it.
```
