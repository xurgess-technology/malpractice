"""Build the Service Dog: geometry, rig, weights, animations, materials, .blend and .glb.

    blender --background --factory-startup --python dog_build.py -- [--export]

No bake pass (dog_materials.py is four flat Principled BSDF materials chosen per face, not a
baked PBR atlas -- see README for why this is a smaller step than the seal/night_nurse pipeline
they were templated from). Runs in well under a minute.
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
    for face in part.f:
        idxs.append(mat_index_fn(face))
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
