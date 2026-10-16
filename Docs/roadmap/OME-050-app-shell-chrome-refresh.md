---
id: OME-050
type: roadmap-card
area: app
kind: polish
tags:
  - chrome
  - navigation
  - attendee
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# App Shell Chrome Refresh

## Summary

```gpt-5
Bring navigation bars, tab bars, search, sheets, menus, segmented controls, toolbars, loading states, and empty states into one coherent OME app shell.
```

## Why

```gpt-5
The app should feel like a precise native tool first. Logo-derived visuals can make the product recognizable, but the everyday attendee and organizer workflows need stable chrome that does not feel like a neon skin.
```

## Rough Shape

```gpt-5
- Audit primary shell surfaces: app root, event browser, event viewer, schedule viewer, settings, auth, and editing flows.
- Standardize toolbar density, title behavior, icon use, search presentation, and sheet treatment.
- Define polished underhydrated states for missing event art, missing org metadata, no imported events, offline data, and unavailable source details.
- Keep event-specific identity inside content surfaces while OME chrome frames the experience.
- Reuse existing controls where possible, especially the current segmented picker and navigation patterns.
- Include Dynamic Type, reduced motion, and small-screen checks.
- Code pointers: `Sources/OpenMusicEvent`, `Sources/OpenMusicEventAppEventViewer`, `Sources/LiquidGlassSegmentedPicker`.
```

## Open Questions

```gpt-5
- Which app-shell surfaces should be launch-blocking for Wicked Woods?
- Should edit/maintainer flows share attendee chrome exactly, or get a slightly denser tool treatment?
- Where should loading and offline chrome live so it can be reused across source import, event viewing, and auth?
- Which fallback states should be generic OME chrome versus event/org-hydrated chrome?
```

## Next Step

```gpt-5
Do a screen-by-screen chrome audit from a real attendee path and list the smallest launch-facing inconsistencies.
```
