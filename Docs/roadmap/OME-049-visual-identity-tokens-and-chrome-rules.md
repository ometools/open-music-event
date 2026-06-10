---
id: OME-049
type: roadmap-card
area: app
kind: design-system
tags:
  - identity
  - chrome
  - accessibility
launch: wicked-woods
priority: high
created: "2026-06-10"
---

# Visual Identity Tokens and Chrome Rules

## Summary

```gpt-5
Define the stable OME visual system around native app chrome: colors, typography, materials, dividers, control states, spacing, and the rules for when spectral/rainbow treatment is allowed.
```

## Why

```gpt-5
The logo direction gives OME a memorable identity, but the app still needs to feel calm, native, and utilitarian beside calendar, mail, and event tools. The rainbow should read as light or signal, not as a permanent app accent that competes with event-specific branding.
```

## Rough Shape

```gpt-5
- Define neutral app chrome tokens for backgrounds, text, dividers, list rows, cards, controls, and disabled/loading states.
- Reserve spectral color for identity moments: portal light, sync/import motion, app icon, launch/loading, and selected high-emphasis surfaces.
- Keep event color separate from OME chrome so festivals, conferences, venues, and organizers can adopt their own palettes.
- Include light mode, dark mode, contrast, grayscale, and reduced-transparency checks.
- Code pointers: `Sources/OpenMusicEvent`, `Sources/OpenMusicEventAppEventViewer`, `Sources/LiquidGlassSegmentedPicker`.
```

## Open Questions

```gpt-5
- Which existing screen should become the visual baseline: calendar browser, event viewer, or schedule viewer?
- Should OME have one default accent color when no event theme is active, or should it stay mostly system-neutral?
- Which tokens need to be shared with Android versus iOS-only Liquid Glass behavior?
```

## Next Step

```gpt-5
Pick one real event screen and define the first pass of neutral chrome tokens without changing the final logo artwork.
```
