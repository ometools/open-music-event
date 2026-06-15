# OME Blender Starter Model

This folder contains a simple generated Blender scene for exploring the Open Music Event logo as a dimensional motion asset.

The first goal is not an exact production model. It is a low-friction starting point with named, separated parts that can be edited by hand in Blender or used as source material for TouchDesigner.

## Files

- `ome_logo_starter_model.py` generates the scene.
- `ome-logo-starter-model.blend` is the generated Blender file.
- `ome-logo-starter-model.glb` is a portable export for other tools.
- `ome-logo-starter-preview.png` is a rendered preview frame.

## Regenerate

From the repo root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python Docs/design/blender/ome_logo_starter_model.py
```

## Model Shape

The scene is split into collections:

- `00_reference`: locked image plane using the final mark snapshot.
- `10_logo_geometry`: simple torus, curve, rounded-box, beam, ring, and wordmark geometry.
- `20_controls`: a named empty with handoff parameters for TouchDesigner.
- `30_lights_camera`: orthographic camera and a soft light.

Useful first edits in Blender:

- Move the `portal left arch tube` and `portal right arch tube` curves until the central portal feels right.
- Adjust the `left O loop` torus scale and position.
- Tune the three `right E` rounded bars.
- Hide or lower the opacity of `reference_final_mark_image_locked` once the model starts matching the mark.
- Keep object names stable if TouchDesigner starts referencing them.

## TouchDesigner Handoff

Treat Blender as the source for rough dimensional geometry and materials. Treat TouchDesigner as the place where the logo comes alive through beam intensity, ring pulse, gradient phase, bloom, audio input, and state-driven animation.
