"""Service Dog materials: six flat Principled BSDF materials. The first four are chosen per face by
dog_geometry.py's vertex masks (no bake pipeline -- see README, 'Known problems / simplifications'
for why this is a smaller step than the seal/night_nurse baked-texture pipeline); the last two are
forced onto specific faces by `Part.add_patch` (the vest's iconography) regardless of any mask.

  Dog_Coat       dark, wiry, matte -- the body, legs, tail, ears
  Dog_Skull      pale, gaunt bone-white -- the skull and jaw only (image refs 1/3/4)
  Dog_Vest_Clean bright, saturated safety-vest orange -- the strap/panel where it is not worn
  Dog_Vest_Worn  the same canvas, darker and desaturated, for the low/edge wear mask
  Dog_Vest_Cross the red-cross patch (first-aid iconography, so the vest reads as a service
                 animal's at a glance, not just a colour block)
  Dog_Vest_Badge a small pale ID-badge patch, the vest's second piece of iconography

Zach has not signed off on vest condition (see README); Dog_Vest_Worn's strength (and how much of
the mesh dog_geometry.py's stain mask actually pushes past the worn threshold) is the one knob to
turn if he wants it cleaner or dirtier -- the base garment itself (this file's job) always stays
bold and legible first, per his "make the vest itself unmistakable" note.
"""
import bpy


def _principled(name, base_color, roughness, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*base_color, 1.0)
    bsdf.inputs['Roughness'].default_value = roughness
    if 'Metallic' in bsdf.inputs:
        bsdf.inputs['Metallic'].default_value = metallic
    mat.use_fake_user = True
    return mat


def coat_material():
    # Near-black, slightly warm charcoal: a dark, wiry coat that reads as body-shaped shadow at
    # a distance (image ref 1's "looming in fog"), not a normal dog's fur color.
    return _principled('Dog_Coat', (0.028, 0.026, 0.030), 0.75)


def skull_material():
    # Pale, gaunt bone-white for the skull and jaw only -- the strongest single tonal cue from
    # every reference. Slightly less rough than the coat: skin drawn tight over bone, faintly damp.
    return _principled('Dog_Skull', (0.72, 0.69, 0.63), 0.55)


def vest_clean_material():
    # Bright, saturated safety-vest orange: the strongest possible contrast against the near-black
    # coat, so the garment's silhouette reads unmistakably at a glance (Zach: "much more visible").
    return _principled('Dog_Vest_Clean', (0.62, 0.24, 0.05), 0.55)


def vest_worn_material():
    # Darker, greyer and a little desaturated: grime and old stains, not fresh canvas. Kept to a
    # minority of the vest by dog_geometry.py's stain mask so it never competes with the base
    # garment's readability.
    return _principled('Dog_Vest_Worn', (0.28, 0.14, 0.08), 0.80)


def vest_cross_material():
    return _principled('Dog_Vest_Cross', (0.62, 0.03, 0.02), 0.5)


def vest_badge_material():
    return _principled('Dog_Vest_Badge', (0.85, 0.82, 0.72), 0.4)


def build_all():
    # Order matters: dog_geometry.py's VEST_CROSS_MAT / VEST_BADGE_MAT are indices into this list.
    return [coat_material(), skull_material(), vest_clean_material(), vest_worn_material(),
            vest_cross_material(), vest_badge_material()]
