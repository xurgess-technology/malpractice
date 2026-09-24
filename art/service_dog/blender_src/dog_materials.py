"""Service Dog materials: six Principled BSDF materials. The first four are chosen per face by
dog_geometry.py's vertex masks; the last two are forced onto specific faces by `Part.add_patch`
(the vest's iconography) regardless of any mask.

  Dog_Coat       dark, wiry, matte -- the body, legs, tail, ears
  Dog_Skull      pale, gaunt bone-white -- the skull and jaw only (image refs 1/3/4)
  Dog_Vest_Clean bright, saturated safety-vest orange -- the strap/panel where it is not worn
  Dog_Vest_Worn  the same canvas, darker and desaturated, for the low/edge wear mask
  Dog_Vest_Cross the red-cross patch (first-aid iconography, so the vest reads as a service
                 animal's at a glance, not just a colour block)
  Dog_Vest_Badge a small pale ID-badge patch, the vest's second piece of iconography

Revision 13 (2026-09-24, styling pass -- see README): Zach asked for actual surface detail --
grime/fur variation and blood, matching how the rest of the project's monsters get this (a baked
texture atlas: art/seal/, art/night_nurse/'s `*_materials.py` + `*_build.py` bake pass), not the
flat per-face colour blocks this file used through Revision 12. `Dog_Coat`, `Dog_Skull`,
`Dog_Vest_Clean` and `Dog_Vest_Worn` (the four big-area materials; the two small icon patches stay
flat and clean so they read unambiguously, per Zach's earlier "make the cross unmistakable" note)
now build a small procedural Cycles node graph -- patchy fur-clump noise, grime concentrated low on
the legs/body, and a scattering of dried-blood stains -- that `dog_build.py`'s new `bake()` step
bakes to a real image per mesh (`Dog_Body_Albedo` / `Dog_Vest_Albedo`) through each part's own
(already-existing, already-packed) UV layer, exactly the seal/night-nurse pattern, just without a
separate high-poly sculpt to bake AO/normal detail from (this mesh has none) -- a self-bake of the
procedural colour only, not a full PBR atlas.
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


class _NB:
    """A minimal node-tree builder -- just enough for the grime/blood graphs below (a much smaller
    subset of art/seal/blender_src/seal_materials.py's `NB`, since this mesh has no infection mask,
    UV2 atlas or flow-frame attribute to support)."""

    def __init__(self, mat):
        self.mat = mat
        self.nt = mat.node_tree
        self.x = -800

    def n(self, kind, **props):
        node = self.nt.nodes.new(kind)
        node.location = (self.x, 0)
        self.x += 180
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def link(self, a, b):
        self.nt.links.new(a, b)

    def value(self, v):
        node = self.n('ShaderNodeValue')
        node.outputs[0].default_value = v
        return node.outputs[0]

    def noise(self, scale, detail=2.0, roughness=0.5, w=0.0):
        node = self.n('ShaderNodeTexNoise')
        node.noise_dimensions = '4D'
        node.inputs['Scale'].default_value = scale
        node.inputs['Detail'].default_value = detail
        node.inputs['Roughness'].default_value = roughness
        node.inputs['W'].default_value = w
        return node.outputs['Fac']

    def ramp(self, fac, stops):
        """`stops`: [(pos, value_or_color), ...], value can be a float or an (r,g,b) tuple."""
        node = self.n('ShaderNodeValToRGB')
        node.color_ramp.elements[0].position = stops[0][0]
        node.color_ramp.elements[0].color = self._c(stops[0][1])
        node.color_ramp.elements[1].position = stops[-1][0]
        node.color_ramp.elements[1].color = self._c(stops[-1][1])
        for pos, val in stops[1:-1]:
            e = node.color_ramp.elements.new(pos)
            e.color = self._c(val)
        self.link(fac, node.inputs['Fac'])
        return node.outputs['Color'], node.outputs['Alpha']

    @staticmethod
    def _c(v):
        if isinstance(v, tuple):
            return (*v, 1.0) if len(v) == 3 else v
        return (v, v, v, 1.0)

    def mix_color(self, fac, a, b):
        node = self.n('ShaderNodeMix', data_type='RGBA', clamp_factor=True)
        for idx, v in ((0, fac), (6, a), (7, b)):
            if isinstance(v, (int, float)):
                node.inputs[idx].default_value = self._c(v)
            elif isinstance(v, tuple):
                node.inputs[idx].default_value = self._c(v)
            else:
                self.link(v, node.inputs[idx])
        return node.outputs[2]

    def math(self, op, a, b=None, clamp=True):
        node = self.n('ShaderNodeMath', operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                node.inputs[i].default_value = v
            else:
                self.link(v, node.inputs[i])
        return node.outputs[0]

    def position(self):
        return self.n('ShaderNodeNewGeometry').outputs['Position']

    def sep(self, vec):
        s = self.n('ShaderNodeSeparateXYZ')
        self.link(vec, s.inputs[0])
        return s.outputs['X'], s.outputs['Y'], s.outputs['Z']


def _grimy_material(name, base_color, roughness, *, grime_color, blood_color=None,
                     grime_seed=0.0, blood_seed=7.0, ground_bias=True, blood_amount=0.05):
    """A Principled BSDF whose Base Color is base_color with patchy fur-clump micro-noise, blotchy
    grime (concentrated low on the body/legs when `ground_bias`, since that is where a real animal
    actually picks up dirt) and, if `blood_color` is given, a scatter of small dried-blood stains
    layered on top -- all driven by object-space Position, so the pattern is coherent in 3D (no UV
    seams) and reads the same regardless of how a given part's UV island happens to be laid out."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    b = _NB(mat)
    pos = b.position()
    _, _, z = b.sep(pos)

    # Fur-clump micro-variation: a fine, high-frequency noise nudging brightness +-12%.
    micro = b.noise(46.0, detail=2.0, roughness=0.55, w=grime_seed)
    micro_mul = b.math('MULTIPLY', b.math('SUBTRACT', micro, 0.5), 0.24)
    micro_mul = b.math('ADD', micro_mul, 1.0)

    # Grime patches: coarse noise thresholded into blotches, biased toward low Z (legs/belly/hem)
    # for `ground_bias` materials (the coat, the vest's own lower edge) via a smooth 0..1 ramp on Z.
    grime_n = b.noise(5.5, detail=3.0, roughness=0.6, w=grime_seed + 11.0)
    if ground_bias:
        height_bias = b.math('SUBTRACT', 1.0, b.math('MULTIPLY', z, 0.55))
        grime_n = b.math('MULTIPLY', grime_n, b.math('ADD', 0.35, b.math('MULTIPLY', height_bias, 0.65)))
    grime_mask, _ = b.ramp(grime_n, [(0.30, 0.0), (0.58, 1.0)])
    # grime_mask is an RGB output (greyscale ramp); use its red channel as a 0..1 factor.
    grime_fac_sep = b.n('ShaderNodeSeparateColor')
    b.link(grime_mask, grime_fac_sep.inputs['Color'])
    grime_fac = grime_fac_sep.outputs['Red']
    grime_fac = b.math('MULTIPLY', grime_fac, 0.85)  # never fully hides the base garment/coat colour

    grimed = b.mix_color(grime_fac, base_color, grime_color)
    dirtied = b.n('ShaderNodeMixRGB', blend_type='MULTIPLY')
    b.link(grimed, dirtied.inputs['Color1'])
    b.link(micro_mul, dirtied.inputs['Color2'])
    dirtied.inputs['Fac'].default_value = 1.0
    out_color = dirtied.outputs['Color']

    if blood_color is not None:
        # Dried-blood stains: raise a low-frequency noise to a high power so only its highest peaks
        # survive -- a robust way to get "a few small stains, not a wash" without hand-tuning a
        # razor-thin colour-ramp threshold against an unknown noise distribution (an early pass
        # here did exactly that and swung between "invisible" and "half the body" for a few percent
        # change in threshold). The surviving peaks' own falloff (from `power`) doubles as a soft,
        # organic stain edge -- soaked-in, not painted-on.
        blood_n = b.noise(2.2, detail=3.0, roughness=0.55, w=blood_seed)
        peaked = b.math('POWER', blood_n, 9.0)
        # `blood_amount` (roughly 0..0.1) is a coverage knob, not a raw factor -- `peaked` is tiny
        # almost everywhere, so it needs a large multiplier to bring its rare high spots up near 1.0.
        blood_fac = b.math('MULTIPLY', peaked, blood_amount * 40.0)
        out_color = b.mix_color(blood_fac, out_color, blood_color)

    b.link(out_color, bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = roughness
    mat.use_fake_user = True
    return mat


def coat_material():
    # Near-black, slightly warm charcoal, with fur-clump noise, grime biased low on the legs/belly
    # (a real animal picks up dirt from the ground, not the shoulders) and a few dried-blood stains
    # (image ref tone: "wrong dog", not merely dirty) -- Revision 13.
    return _grimy_material('Dog_Coat', (0.028, 0.026, 0.030), 0.78,
                            grime_color=(0.008, 0.007, 0.009), blood_color=(0.34, 0.028, 0.020),
                            grime_seed=1.0, blood_seed=4.0, blood_amount=0.05)


def skull_material():
    # Pale, gaunt bone-white for the skull and jaw only. A lighter touch than the coat (Zach's
    # brief calls for grime/blood generally; the skull is the model's single strongest tonal image,
    # so this stays a SUBTLE smudge/stain rather than the coat's fuller grime treatment) plus one
    # dried-blood stain concentrated toward the jaw (low Z, the mouth's own end of the skull mesh).
    return _grimy_material('Dog_Skull', (0.72, 0.69, 0.63), 0.55,
                            grime_color=(0.42, 0.40, 0.36), blood_color=(0.42, 0.05, 0.035),
                            grime_seed=2.0, blood_seed=9.0, ground_bias=True, blood_amount=0.04)


def vest_clean_material():
    # Bright, saturated safety-vest orange, with the same fur-material grime/blood treatment kept
    # deliberately light here (`_grimy_material`'s grime_fac cap already limits how much shows) so
    # the garment itself still reads unmistakably first, per Zach's original "make the vest itself
    # unmistakable" note -- this is the worn-in canvas texture on top of that, not a redesign.
    return _grimy_material('Dog_Vest_Clean', (0.62, 0.24, 0.05), 0.6,
                            grime_color=(0.18, 0.09, 0.03), blood_color=(0.38, 0.025, 0.020),
                            grime_seed=3.0, blood_seed=13.0, blood_amount=0.08)


def vest_worn_material():
    # Darker, greyer and a little desaturated: grime and old stains, not fresh canvas. Kept to a
    # minority of the vest by dog_geometry.py's stain mask so it never competes with the base
    # garment's readability. Revision 13: this was already the "dirty" material, so its own texture
    # treatment leans harder into grime (more visible patchiness) but a lighter blood touch (the
    # stain mask already concentrates it where wear reads naturally).
    return _grimy_material('Dog_Vest_Worn', (0.28, 0.14, 0.08), 0.85,
                            grime_color=(0.09, 0.05, 0.03), blood_color=(0.30, 0.02, 0.015),
                            grime_seed=5.0, blood_seed=17.0, blood_amount=0.07)


def vest_cross_material():
    # Revision 7: the old (0.62, 0.03, 0.02) shared the exact same red channel as
    # Dog_Vest_Clean's (0.62, 0.24, 0.05) -- the two colours only differed in green/blue, which
    # washed out under directional lighting and made the cross unreadable at any distance. A true
    # bright red (higher red channel than the vest, near-zero green/blue) is unambiguous against
    # the vest's orange regardless of lighting. Left flat (no grime/blood texture, Revision 13):
    # this is small first-aid iconography, and Zach has twice asked for it to read unambiguously,
    # not weathered.
    return _principled('Dog_Vest_Cross', (0.85, 0.04, 0.03), 0.45)


def vest_badge_material():
    return _principled('Dog_Vest_Badge', (0.85, 0.82, 0.72), 0.4)


def build_all():
    # Order matters: dog_geometry.py's VEST_CROSS_MAT / VEST_BADGE_MAT are indices into this list.
    return [coat_material(), skull_material(), vest_clean_material(), vest_worn_material(),
            vest_cross_material(), vest_badge_material()]
