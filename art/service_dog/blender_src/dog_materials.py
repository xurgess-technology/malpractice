"""Service Dog materials: four flat Principled BSDF materials, chosen per face by
dog_geometry.py's vertex masks (no bake pipeline -- see README, 'Known problems / simplifications'
for why this is a smaller step than the seal/night_nurse baked-texture pipeline).

  Dog_Coat       dark, wiry, matte -- the body, legs, tail, ears
  Dog_Skull      pale, gaunt bone-white -- the skull and jaw only (image refs 1/3/4)
  Dog_Vest_Clean the vest's canvas where it is not worn
  Dog_Vest_Worn  the same canvas, darker and desaturated, for the low/edge/strap wear mask

Zach has not signed off on vest condition (see README); Dog_Vest_Worn's strength is the one knob
to turn if he wants it cleaner or dirtier.
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
    return _principled('Dog_Vest_Clean', (0.44, 0.40, 0.26), 0.65)


def vest_worn_material():
    # Darker, greyer and a little desaturated: grime and old stains, not fresh canvas.
    return _principled('Dog_Vest_Worn', (0.22, 0.20, 0.15), 0.80)


def build_all():
    return [coat_material(), skull_material(), vest_clean_material(), vest_worn_material()]
