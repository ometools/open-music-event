# OME Blender Logo Blockout

This folder contains Blender working files for exploring the Open Music Event logo as a dimensional motion asset.

The current model direction is user-authored in Blender 5.1.2. Do not treat AI-generated geometry, scripts, or scene files as the source of truth unless Woody explicitly asks for that.

The first goal is not an exact production model. It is a low-friction blockout with separated parts that can be refined by hand in Blender and later used as source material for TouchDesigner.

## Files

- `OME-3d-Logo.blend` is the current working Blender file.
- `OME-3d-Logo-blockout-portal-cage.blend` is an earlier blockout milestone for the portal cage.
- `OME-3d-Logo.blend1` is Blender's local backup file.
- `ome_logo_starter_model.py` is historical scaffolding from an abandoned generated-starter attempt. Do not build on it unless explicitly requested.

## Current Shape Direction

- Four-prong spherical claw/cage around a glowing inner portal.
- The front prong crosses in front of the portal.
- The portal is the light source inside the cage, not a hole in the cage.
- The `O` and `E` are smoked-glass side forms around the portal cage.
- The bottom `OPEN MUSIC EVENT` wordmark is a supporting lockup, not the hero.

## Material And Lighting Direction

- The geometry should be able to go nearly invisible against black.
- Reveal the logo with lighting: portal glow, grazing lights, rim lights, and spectral reflections.
- Keep the material dark smoked glass rather than bright colored plastic.
- Let cyan/blue, violet, rose, and gold appear from lights and reflections.
- Use higher samples and denoise for final stills; viewport speckle is expected with glass/transparent previews.

## TouchDesigner Handoff

Treat Blender as the source for manually authored dimensional geometry and material look. Treat TouchDesigner as the place where the logo comes alive through beam intensity, ring pulse, gradient phase, bloom, audio input, and state-driven animation.

Useful future animation handles:

- Portal intensity.
- Cage rotation or opening.
- Front-prong silhouette against the portal core.
- `O` and `E` spectral shimmer.
- Horizontal beam intensity.
- Refraction ring pulse.
- Bloom and audio-reactive passes.
