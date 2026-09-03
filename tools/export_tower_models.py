"""tower.blend を Godot 用の .glb へ書き出す。

使い方 (Blender 5.0 以降):

    blender -b path/to/tower.blend --python tools/export_tower_models.py -- assets/models

やっていること:

1. 土台と砲塔を別々の .glb にする
   Godot 側で砲塔だけを旋回させるため。1 ファイルにまとめると、
   シーン内で砲塔だけを取り出して回すのが面倒になる。

2. 砲塔は旋回軸が原点に来るように移してから書き出す
   Godot では Turret ノードの位置 (= TURRET_MOUNT_HEIGHT) で高さを付ける。

3. Z 軸まわりに 180 度回してから書き出す
   このモデルは砲身が Blender の -Y を向いている。glTF 変換で
   Blender +Y が Godot の -Z (前方) になるため、そのままだと後ろ向きになる。
   Blender 側で砲身を +Y に向けて作れば、この回転は不要になる。

.blend は保存しないので、元ファイルは変更されない。
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

OUT_DIR = sys.argv[sys.argv.index("--") + 1]

BASE = bpy.data.objects["TowerSlow_Base"]
TURRET = bpy.data.objects["TowerSlow_Turret"]
BARREL = bpy.data.objects["TowerSlow_Barrel"]

# 砲身が -Y を向いているぶんの補正。
FACING_FIX = Matrix.Rotation(math.pi, 4, "Z")


def world_bbox(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return lo, hi


def export(objects, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print("exported:", path, os.path.getsize(path), "bytes")


os.makedirs(OUT_DIR, exist_ok=True)

# 砲塔の取り付け高さ。Godot の Turret ノードの Y 座標に使う。
turret_mount_height = TURRET.matrix_world.translation.z

# --- 土台 ---
# 原点はすでに接地面にある。向きだけ揃える。
BASE.matrix_world = FACING_FIX @ BASE.matrix_world
bpy.context.view_layer.update()
export([BASE], "tower_slow_base.glb")

# --- 砲塔 (砲身は子なので一緒に動く) ---
TURRET.parent = None
TURRET.matrix_world = FACING_FIX
bpy.context.view_layer.update()
export([TURRET, BARREL], "tower_slow_turret.glb")

# --- Godot 側で使う数値 ---
lo, hi = world_bbox(BARREL)
# 砲身の先端は +Y 側の端。Blender(x, y, z) -> Godot(x, z, -y)。
tip = Vector(((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5))
print("=== VALUES FOR GODOT ===")
print(f"TURRET_MOUNT_HEIGHT (Turret ノードの Y) = {turret_mount_height:.4f}")
print(f"MUZZLE (Turret ローカル) = ({tip.x:.4f}, {tip.z:.4f}, {-tip.y:.4f})")
print("=== DONE ===")
