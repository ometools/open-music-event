# Logo

This note tracks the working logo direction for Open Music Event.

These samples are close-to-final drafts, not canonical final artwork. Do not treat the current JPGs as final source assets, and do not modify the artwork locally. Product and chrome work should consume final designer-provided assets when they are delivered.

Designer reference: [xcrunchy](https://www.xcrunchy.com/)

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

## Asset Needs

- Final layered source artwork.
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
