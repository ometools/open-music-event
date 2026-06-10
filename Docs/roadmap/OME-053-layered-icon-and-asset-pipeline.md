---
id: OME-053
type: roadmap-card
area: release
kind: assets
tags:
  - ios
  - android
  - identity
launch: wicked-woods
priority: medium
created: "2026-06-10"
---

# Layered Icon and Asset Pipeline

## Summary

```gpt-5
Prepare the final designer-provided logo artwork for app icons, launch screens, adaptive icons, Liquid Glass composition, dark/light variants, tint variants, and optional alternate icons.
```

## Why

```gpt-5
The logo direction depends on depth, portal layers, light, and refraction. Those qualities need an asset pipeline that preserves the final art instead of flattening it too early or forcing manual one-off exports for each platform.
```

## Rough Shape

```gpt-5
- Do not modify the logo art as part of this card; start only after final source assets are delivered.
- Preserve separated layers where available: background, O/E or wordmark, portal/M, beam, highlights, and masks.
- Produce iOS layered icons, Android adaptive icons, launch/splash assets, dark/light/tint variants, store artwork, and any alternate user-selectable icons.
- Keep a polished generic OME launch-screen fallback when event or organization artwork is not available.
- Validate small-size readability and monochrome/tinted survival.
- Keep generated outputs under the existing platform asset locations.
- Code pointers: `Darwin/Assets.xcassets`, `Darwin`, `Android/app/src/main/res`, future documentation/release asset exports.
```

## Open Questions

```gpt-5
- Which final file formats and separated layers will the designer deliver?
- Which icon variants are required for launch versus nice-to-have alternates?
- Which launch-screen assets are generic OME assets versus event/org-hydrated assets?
- Should user-selectable app icons be included in v1 or saved for a later identity polish pass?
```

## Next Step

```gpt-5
After final logo delivery, inventory source layers and map them to iOS, Android, store, and documentation/release asset outputs.
```
