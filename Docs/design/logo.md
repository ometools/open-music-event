# Logo

This note tracks the working logo direction for Open Music Event.

These samples are close-to-final drafts, not canonical final artwork. Do not treat the current JPGs as final source assets, and do not modify the artwork locally. Product and chrome work should consume final designer-provided assets when they are delivered.

Designer reference: [xcrunchy](https://www.xcrunchy.com/)

## Final Mark Snapshot

![OME final mark](assets/ome-logo-final-mark-2026-06.png)

- `assets/ome-logo-final-mark-2026-06.png`
  - Current final mark snapshot for planning.
  - Size: 2000 x 2000.
  - Added from the supplied final mark image on 2026-06-15.
  - Use as the current visual reference for motion-system planning.
  - Still need final layered source files before production asset slicing.

Visual features to preserve:

- Center portal/M shape as the primary standalone identity.
- Left `O` loop and right `E` beam lockup around the portal.
- Horizontal light beam crossing through the mark.
- Circular refraction rings around the portal.
- Spectral blue, violet, rose, and gold gradients over a black field.
- Wide-spaced `OPEN MUSIC EVENT` wordmark as a supporting lockup, not required for every app surface.

## Current Samples

![OME logo sample mark](assets/ome-logo-sample-mark-2026-05.jpg)

- `assets/ome-logo-sample-mark-2026-05.jpg`
  - Standalone portal/M mark.
  - Size: 1024 x 1024.
  - Source at time of capture: `Darwin/Assets.xcassets/AppIcon.appiconset/OMEIconSample1.jpg`.
  - Use as an app-icon and motion-reference draft only.

![OME logo sample wordmark](assets/ome-logo-sample-wordmark-2026-05.jpg)

- `assets/ome-logo-sample-wordmark-2026-05.jpg`
  - Full OME wordmark sample.
  - Size: 2000 x 2000.
  - Downloaded from the supplied Discord CDN image.
  - Use as a lockup and public-surface reference draft only.

## Original Brief

- Name: Open Music Event, abbreviated OME.
- The mark should be able to stand on its own as a symbol.
- It should feel recognizable, comfortable, and utilitarian.
- It should feel at home next to calendar and email on a home screen.
- It should also work beside QR codes, on digital surfaces, and on physical event objects or signage.
- It should be a solid foundation for richer graphics, not the whole visual system by itself.
- The product should feel closer to a trusty iPod than a flashy feed.

## Direction That Landed

- The center portal/M mark is the strongest part of the concept.
- The portal is useful beyond static branding: it can become the motion language for opening, loading, syncing, importing, and moving into an event context.
- The rainbow/spectral treatment works because it avoids locking OME to one brand color.
- Event surfaces can bring their own palettes, logos, posters, and visual identity.
- The OME chrome should stay calm and native around those event-specific visuals.
- The shape should lean precise rather than overly flowy.
- The mark should avoid becoming too music-specific, because the project may support conferences, comedy events, and other event categories later.

## Visual Identity Implications

- Treat spectral color as light, signal, or refraction rather than as the permanent OME accent color.
- Keep app shell chrome neutral and utility-oriented.
- Let event identity live primarily in event headers, rows, schedule accents, stage chips, badges, and public surfaces.
- Use the portal motif sparingly in high-value moments instead of repeating the logo everywhere.
- Preserve the option for OME to expand beyond the literal "Music" category.

## Motion And Liquid Glass

The logo folds naturally into iOS Liquid Glass because the portal, beam, and rings can read as refraction rather than decoration.

Good places for portal/refraction behavior:

- App launch or first load.
- Opening an event.
- Source import or sync progress.
- Auth handoff.
- QR scanning and event entry.
- Empty/loading/offline states.
- Later: optional audio-reactive or schedule-reactive motion.

Constraints:

- Prefer system glass/material effects where they carry the idea.
- Keep custom motion small and reusable.
- Include reduced-motion and reduced-transparency fallbacks.
- Avoid making the everyday UI feel like a neon theme.

## TouchDesigner Motion Planning

Start with TouchDesigner as a small external motion lab, not the app implementation. The goal is to learn the motion language from the final mark, then translate only the useful pieces into app-native animation later.

Expect a 3D model to be part of this system, likely authored in Blender. Blender should be the source for any dimensional logo geometry, materials, camera moves, and model cleanup; TouchDesigner can then ingest the model or rendered passes for procedural motion, compositing, audio-reactive experiments, and export studies.

Small prototype shape:

- Build the mark as separated layers: portal/M matte, `O` and `E` forms, beam, refraction rings, gradient pass, glow/bloom, and wordmark.
- Build or request a rough Blender model with separated portal/M geometry, side letterforms, beam volume, refraction rings, and optional wordmark geometry.
- Make one short loop or state transition first: beam wakes up, portal opens, rings pulse once, spectral color breathes, then the mark resolves to stillness.
- Keep parameters explicit: beam intensity, ring radius, ring decay, gradient phase, portal aperture, blur, bloom, and final hold time.
- Treat audio-reactive behavior as optional exploration, not a requirement for the first pass.
- Export reference clips and still frames for review; keep notes on the model, material, camera, and parameter values that feel reusable.
- Later app translation can be SwiftUI/Liquid Glass first, with custom rendering only where the system materials cannot carry the effect.

Open questions:

- Is TouchDesigner only a sketching tool, or should it also render event-specific visual assets?
- Is Blender the canonical 3D asset source, or only a rough model for motion exploration?
- Who owns the first Blender model: designer-provided layered/source artwork, or an internal rough rebuild for prototyping?
- Which single app moment should inherit the first motion idea: launch, event open, import/sync, auth handoff, or QR entry?
- Should the portal react to real audio or schedule state later, or stay purely state-driven?

## Asset Needs

- Final layered source artwork.
- Blender model or source geometry for the dimensional mark.
- Standalone mark.
- Full wordmark.
- App icon layers for iOS.
- Android adaptive icon foreground/background assets.
- Dark, light, tinted, and monochrome survival variants.
- QR-adjacent lockups.
- "Powered by Open Music Event" style lockups.

## Related Roadmap Cards

- [[../roadmap/OME-049-visual-identity-tokens-and-chrome-rules|OME-049: Visual Identity Tokens and Chrome Rules]]
- [[../roadmap/OME-050-app-shell-chrome-refresh|OME-050: App Shell Chrome Refresh]]
- [[../roadmap/OME-051-event-theme-system|OME-051: Event Theme System]]
- [[../roadmap/OME-052-liquid-glass-portal-motion-system|OME-052: Liquid Glass Portal Motion System]]
- [[../roadmap/OME-053-layered-icon-and-asset-pipeline|OME-053: Layered Icon and Asset Pipeline]]
- [[../roadmap/OME-054-public-surface-and-qr-lockups|OME-054: Public Surface and QR Lockups]]
