"""戦士の .blend を Godot 用の .glb へ書き出す。

使い方 (Blender 5.0 以降):

    blender -b warrior_knight.blend --python tools/export_warrior_models.py \
        -- assets/models/warriors Kn_ warrior_shield.glb

引数は「出力先ディレクトリ」「書き出す対象オブジェクトの接頭辞」「出力ファイル名」。

戦士はタワーの砲塔と違って部位ごとに旋回させる必要が無いので、タワーのように
Base/Turret へ分けず、接頭辞に一致するメッシュを 1 つの .glb にまとめて書き出すだけでよい。
接頭辞に一致しても Ground で終わる名前（Blender 側の見た目確認用の地面板）は除く。

Blender 側の前提: キャラクターは -Y を向いて立っていること
（このプロジェクトの procedural な戦士・敵は Godot の -Z が正面で、
Blender glTF エクスポータは既定で Blender -Y 前方を glTF -Z 前方に変換するため、
-Y 向きで作れば Godot 側で回転を入れずに正面が揃う）。
"""

import os
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1 :]
OUT_DIR, PREFIX, FILENAME = args[0], args[1], args[2]

objects = [
    o for o in bpy.data.objects
    if o.type == "MESH" and o.name.startswith(PREFIX) and not o.name.endswith("Ground")
]
if not objects:
    raise SystemExit(f"接頭辞 '{PREFIX}' に一致するメッシュが見つかりません")

for obj in bpy.context.view_layer.objects:
    obj.select_set(False)
for obj in objects:
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]

os.makedirs(OUT_DIR, exist_ok=True)
path = os.path.join(OUT_DIR, FILENAME)
bpy.ops.export_scene.gltf(
    filepath=path,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
)
print("exported:", path, os.path.getsize(path), "bytes")
print("含めたメッシュ:", ", ".join(o.name for o in objects))
