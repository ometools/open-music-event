# Approved OME vector master

Approved by Woody on 2026-10-21 after reviewing the cage, O/E balance, portal silhouette, cage fit, and smooth sphere/streak connection.

## Files

- OME-master.svg: named assembly layers in approved drawing order.
- layers/o.svg and layers/e.svg: supporting letterforms.
- layers/cage-rear.svg and layers/cage-front.svg: separate cage parts.
- layers/cage.svg: complete cage as one combined contour. Use this instead of the two cage parts when a complete cage is wanted.
- layers/portal.svg: the complete solid portal as one closed contour.
- preview.png and preview.html: dark-background inspection views.
- validation.json: accepted dimensions, curve checks, and file hashes.

The SVGs are the editable artwork sources. Keep the assembled master and registered component files together.

## Registration and sizing

All SVGs use viewBox="0 0 2000 2000" with the same origin and scale. Drawing order: O, E, rear cage, portal, front cage. Preserve that registration when moving components between Affinity, cutting software, and other uses. Scale the whole assembly together; do not auto-center, crop, or resize each imported component independently.

The portal is symmetric around (1000, 950), with a circular core of radius 184 and horizontal endpoints at x225.5 and x1774.5. Its circle-to-streak joins have matching tangents. The accepted cage, O and E geometry is unchanged.

Preview colors distinguish components; they do not define a new fixed brand palette. The master has a CSS dark viewing background with no background rectangle or cut path. Component exports have solid black fills and transparent backgrounds.

## Cutting and other exports

These files define approved geometry. Minimum feature widths, kerf compensation, material compatibility and cutter settings must be established for each physical size/material. Check the narrow outer arcs and beam tips in a material test. No machine settings or kerf compensation are baked into the artwork.

The July sphere-cage PNG remains a lighting/spectral reference. This flat vector master does not replace the user-authored Blender model or change existing app/site asset references.
