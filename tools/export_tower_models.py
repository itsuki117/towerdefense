"""タワーの .blend を Godot 用の .glb へ書き出す。

使い方 (Blender 5.0 以降):

    blender -b tower_basic.blend --python tools/export_tower_models.py \
        -- assets/models TowerBasic tower_basic

引数は「出力先ディレクトリ」「.blend 内のオブジェクト名の接頭辞」「出力ファイル名の接頭辞」。
接頭辞 X に対し X_Base / X_Turret / X_Barrel の 3 オブジェクトがある前提。

やっていること:

1. 土台と砲塔を別々の .glb にする
   Godot 側で砲塔だけを旋回させるため。1 ファイルにまとめると、
   シーン内で砲塔だけを取り出して回すのが面倒になる。

2. 砲塔は旋回軸が原点に来るように移してから書き出す
   Godot では Turret ノードの位置で高さを付ける（下に出る取り付け高さを使う）。

3. 砲身が Blender の -Y を向いていたら Z 軸まわりに 180 度回す
   glTF 変換で Blender +Y が Godot の -Z (前方) になるため、-Y 向きのままだと
   後ろ向きに撃つタワーになる。Blender 側で +Y に向けて作れば回転は入らない。

最後に Godot のシーンに書く数値（取り付け高さと銃口位置）を出力する。
.blend は保存しないので、元ファイルは変更されない。
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1 :]
OUT_DIR, OBJECT_PREFIX, FILE_PREFIX = args[0], args[1], args[2]

BASE = bpy.data.objects[f"{OBJECT_PREFIX}_Base"]
TURRET = bpy.data.objects[f"{OBJECT_PREFIX}_Turret"]
BARREL = bpy.data.objects[f"{OBJECT_PREFIX}_Barrel"]


def world_bbox(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return lo, hi


def _set_selected(obj, selected):
    # 非表示のオブジェクトは選択できないので先に表示に戻す。
    # bpy.ops.object.select_all は .blend の保存状態次第で
    # poll() failed になるため、オペレータは使わない。
    try:
        obj.hide_set(False)
        obj.select_set(selected)
    except RuntimeError:
        pass


def export(objects, filename):
    for obj in bpy.context.view_layer.objects:
        _set_selected(obj, False)
    for obj in objects:
        _set_selected(obj, True)
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

# Godot の Turret ノードに入れる高さ。
turret_mount_height = TURRET.matrix_world.translation.z

# 砲身がどちら向きに伸びているかを、砲塔ローカルで測って判定する。
barrel_lo, barrel_hi = world_bbox(BARREL)
turret_y = TURRET.matrix_world.translation.y
needs_flip = abs(barrel_lo.y - turret_y) > abs(barrel_hi.y - turret_y)
facing_fix = Matrix.Rotation(math.pi, 4, "Z") if needs_flip else Matrix.Identity(4)
print("砲身の向き:", "-Y なので 180 度回す" if needs_flip else "+Y なのでそのまま")

# --- 土台 (原点はすでに接地面にある。向きだけ砲塔と揃える) ---
BASE.matrix_world = facing_fix @ BASE.matrix_world
bpy.context.view_layer.update()
export([BASE], f"{FILE_PREFIX}_base.glb")

# --- 砲塔 (砲身は子なので一緒に動く) ---
TURRET.parent = None
TURRET.matrix_world = facing_fix
bpy.context.view_layer.update()
export([TURRET, BARREL], f"{FILE_PREFIX}_turret.glb")

# --- Godot 側で使う数値 ---
lo, hi = world_bbox(BARREL)
# 砲身の先端は +Y 側の端。Blender(x, y, z) -> Godot(x, z, -y)。
tip = Vector(((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5))
print("=== VALUES FOR GODOT ===")
print(f"Turret ノードの Y = {turret_mount_height:.4f}")
print(f"Muzzle (Turret ローカル) = ({tip.x:.4f}, {tip.z:.4f}, {-tip.y:.4f})")
print("=== DONE ===")
