"""Build the Service Dog: geometry, rig, weights, animations, materials, .blend and .glb.

    blender --background --factory-startup --python dog_build.py -- [--export]

Revision 13 (2026-09-24): a colour-only self-bake (Cycles DIFFUSE/COLOR pass, no separate high-poly
source -- this mesh has none) of dog_materials.py's procedural grime/blood node graphs, through
each part's own already-packed UV layer, into `Dog_Body_Albedo`/`Dog_Vest_Albedo` (art/service_dog/
blender_src/textures/, git-ignored like the seal/night-nurse ones -- the game copy under
assets/models/ is what ships). Smaller than the seal/night-nurse pipeline (no AO/normal bake, no
separate high-poly sculpt) but the same underlying pattern: a real baked texture atlas, not flat
per-face colour blocks. Runs in well under a minute.
"""
import sys
import os
import time
import importlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy
import dog_geometry as G
import dog_materials as M
import dog_rig as R
for m in (G, M, R):
    importlib.reload(m)

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
EXPORT = '--export' in ARGS
T0 = time.time()


def log(*a):
    print('[dog_build %6.1fs]' % (time.time() - T0), *a, flush=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def part_object(part, mats, mat_index_fn):
    me = bpy.data.meshes.new(part.name)
    me.from_pydata([tuple(v) for v in part.v], [], part.f)
    uv = me.uv_layers.new(name='UVMap')
    flat = []
    for fu in part.fuv:
        for u, v in fu:
            flat += [u, v]
    uv.data.foreach_set('uv', flat)
    for mt in mats:
        me.materials.append(mt)
    idxs = []
    for face, forced in zip(part.f, part.face_mat):
        idxs.append(forced if forced is not None else mat_index_fn(face))
    me.polygons.foreach_set('material_index', idxs)
    me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
    me.validate(clean_customdata=False)
    ob = bpy.data.objects.new(part.name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def pack_uvs(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(udim_source='CLOSEST_UDIM', rotate=True, scale=True, margin_method='FRACTION', margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')


def select_only(objs, active=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def new_image(name, size):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = 'sRGB'
    return img


def bake_albedo(obj, mats, image, samples=8):
    """Self-bake each of `mats`' procedural Base Color graph (dog_materials.py's grime/blood node
    trees, or a flat colour for materials that skip them) into `image`, through `obj`'s own
    (already-packed) UV layer -- the seal/night-nurse pattern (`*_build.py`'s `bake()`), just
    without a separate high-poly source: there is nothing here to bake AO/normal detail from, so
    this bakes colour only, self-to-self."""
    # Deselect every node in EVERY material's tree first, not just `mats`': `use_clear=True` below
    # clears whichever image is the "active" bake target it finds, and a stale active/selected node
    # left over in a DIFFERENT material from a previous `bake_albedo()` call (e.g. the coat/skull
    # bake's own target node, still marked active in its own material when the vest bake runs next)
    # gets its image cleared too -- found by baking body then vest and watching the body image's
    # own pixel data go to all-zero the moment the second (vest) bake ran, with no code touching it.
    for anymat in bpy.data.materials:
        if anymat.use_nodes:
            for n in anymat.node_tree.nodes:
                n.select = False
    nodes = []
    for m in mats:
        nt = m.node_tree
        node = nt.nodes.new('ShaderNodeTexImage')
        node.image = image
        node.select = True
        nt.nodes.active = node
        nodes.append(node)
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.device = 'CPU'
    scn.cycles.samples = samples
    select_only([obj], obj)
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=8, use_clear=True, target='IMAGE_TEXTURES')
    return nodes


def wire_baked_albedo(mat, node):
    """After baking, make the baked image the material's actual Base Color (replacing its
    procedural grime/blood graph, which is only there to produce the bake) -- same "texture wins
    once baked" pattern the seal/night-nurse materials use."""
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    mat.node_tree.links.new(node.outputs['Color'], bsdf.inputs['Base Color'])


def main():
    reset()
    scn = bpy.context.scene
    scn.render.fps = 30

    log('generating mesh')
    parts, joints = G.build_all(1)
    body, vest = parts
    for p in parts:
        log('  %-12s %6d tris' % (p.name, p.tris()))

    mats = M.build_all()   # [coat, skull, vest_clean, vest_worn]
    for m in mats:
        m.use_fake_user = True

    def body_index(face):
        avg = sum(body.attr['head'][i] for i in face) / len(face)
        return 1 if avg > 0.5 else 0   # 0 Coat, 1 Skull

    def vest_index(face):
        avg = sum(vest.attr['stain'][i] for i in face) / len(face)
        return 3 if avg > 0.4 else 2   # 2 Vest_Clean, 3 Vest_Worn

    body_obj = part_object(body, mats, body_index)
    vest_obj = part_object(vest, mats, vest_index)
    pack_uvs(body_obj)
    pack_uvs(vest_obj)

    log('baking grime/blood texture (Revision 13)')
    body_img = new_image('Dog_Body_Albedo', 1024)
    vest_img = new_image('Dog_Vest_Albedo', 512)
    body_nodes = bake_albedo(body_obj, mats[0:2], body_img)      # Coat, Skull
    vest_nodes = bake_albedo(vest_obj, mats[2:4], vest_img)      # Vest_Clean, Vest_Worn
    for m, n in zip(mats[0:2], body_nodes):
        wire_baked_albedo(m, n)
    for m, n in zip(mats[2:4], vest_nodes):
        wire_baked_albedo(m, n)
    tex_dir = os.path.join(HERE, 'textures')
    os.makedirs(tex_dir, exist_ok=True)
    for img in (body_img, vest_img):
        img.filepath_raw = os.path.join(tex_dir, img.name + '.png')
        img.file_format = 'PNG'
        img.save()
    bpy.ops.object.select_all(action='DESELECT')

    log('rig')
    arm = R.build_armature(joints)
    R.skin(body_obj, arm)
    R.assign_weights(body_obj, body)
    R.skin(vest_obj, arm)
    R.assign_weights(vest_obj, vest)
    for b in arm.data.bones:
        b.use_deform = b.name != 'root'
    bpy.ops.object.select_all(action='DESELECT')

    log('actions')
    R.build_actions(arm)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)

    log('total tris %d' % sum(p.tris() for p in parts))

    bpy.context.preferences.filepaths.save_version = 0
    blend_path = os.path.join(HERE, 'service_dog.blend')
    arm.animation_data.action = bpy.data.actions['Idle']
    scn.frame_set(0)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, relative_remap=True, compress=True)
    log('saved', blend_path)

    if not EXPORT:
        return
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.ops.object.select_all(action='DESELECT')
    body_obj.select_set(True)
    vest_obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    glb = os.path.join(os.path.dirname(HERE), 'service_dog_embedded.glb')
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True, export_animations=True,
                               export_animation_mode='ACTIONS', export_force_sampling=True, export_skins=True,
                               export_influence_nb=4, export_yup=True, export_apply=False, export_materials='EXPORT',
                               export_image_format='AUTO', export_def_bones=False, export_anim_slide_to_zero=True)
    log('exported', glb, os.path.getsize(glb) // 1024, 'KB')
    import dog_glb_extern
    game_glb = os.path.normpath(os.path.join(HERE, '..', '..', '..', 'assets', 'models', 'monsters', 'service_dog', 'service_dog.glb'))
    files, size = dog_glb_extern.extern(glb, game_glb)
    log('game copy', game_glb, size // 1024, 'KB, textures:', ', '.join(f for f, _ in files) if files else '(none: flat materials)')


main()
