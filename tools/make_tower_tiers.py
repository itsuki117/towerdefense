"""アロータワーのティア 5 段ぶんの .tres と .tscn を書き出す。

使い方 (標準ライブラリだけで動く):

    python tools/make_tower_tiers.py

ティアは「1 本のタワーを育てる」のではなく **タワーの種類そのものを底上げする**。
ステージが変わると設置はリセットされるので、置いた 1 本に掛けても次で消えてしまう。
インターバルで種類を強化しておけば、以降そのティアで建つ。

5 段のモデルは Blender で作ったもの (tools/export_tower_models.py で .glb 化済み)。
Turret の取り付け高さと Muzzle の位置はモデルごとに違うので、
書き出し時に表示された値をここに写して .tscn を組み立てる。

**書き出す前に必ず検算する**:

- 設置費用・ダメージ・射程が段ごとに増えているか（下位が上位に勝たない）
- 鎖が 5 段で終わっているか（next_tier のループが無いか）
- 参照している .glb が実在するか

検算に落ちたら書き出さずに止まる。数値をいじったらこのスクリプトを回す。
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOWER_DIR = os.path.join(ROOT, "resources", "towers")
SCENE_DIR = os.path.join(ROOT, "scenes")
MODEL_DIR = os.path.join(ROOT, "assets", "models")

# --- ティア定義 ---------------------------------------------------------------
# file    : .tres / .tscn のファイル名。
# model   : assets/models/<model>_base.glb と _turret.glb を使う。
# mount   : Turret ノードの Y（= .blend の砲塔の取り付け高さ）。
# muzzle  : Muzzle の位置（Turret ローカル）。
#           mount と muzzle は export_tower_models.py が出力した値をそのまま写す。
# upgrade : この段から次の段へ上げる費用。最終段は 0（これ以上上がらない）。
# shot    : 弾の種類（TowerData.Shot: 0=BOLT 1=SHELL 2=ORB 3=BEAM）。
# shot_color / shot_scale : 弾の色と太さ。**段ごとに変える**ので、飛んでいる弾を
#           見ただけで何段目のタワーが撃ったのか分かる。
# splash  : 着弾時に巻き込む半径 (m)。0 なら単体攻撃。最終段だけが持つ。

BOLT, SHELL, ORB, BEAM = 0, 1, 2, 3

TIERS = [
    {
        "file": "tower_arrow", "name": "アロータワー", "model": "tower_basic",
        "mount": 0.52, "muzzle": (0.09, 0.175, -0.56),
        "cost": 200, "damage": 4, "range": 6.0, "rate": 1.6, "speed": 18.0,
        "color": (0.85, 0.72, 0.35), "upgrade": 600,
        "shot": BOLT, "shot_color": (1.0, 0.88, 0.45), "shot_scale": 0.9, "splash": 0.0,
    },
    {
        "file": "tower_cannon", "name": "キャノンタワー", "model": "tower_cannon",
        "mount": 0.4473, "muzzle": (0.09, 0.188, -0.898),
        "cost": 250, "damage": 7, "range": 6.5, "rate": 1.6, "speed": 19.0,
        "color": (0.88, 0.66, 0.32), "upgrade": 960,
        "shot": SHELL, "shot_color": (1.0, 0.74, 0.32), "shot_scale": 1.05, "splash": 0.8,
    },
    {
        "file": "tower_heavy", "name": "ヘビータワー", "model": "tower_heavy",
        "mount": 0.6152, "muzzle": (0.09, 0.19, -0.996),
        "cost": 305, "damage": 11, "range": 7.0, "rate": 1.7, "speed": 20.0,
        "color": (0.92, 0.6, 0.3), "upgrade": 1200,
        "shot": SHELL, "shot_color": (1.0, 0.6, 0.26), "shot_scale": 1.25, "splash": 1.0,
    },
    {
        "file": "tower_siege", "name": "シージタワー", "model": "tower_siege",
        "mount": 0.808, "muzzle": (0.09, 0.1915, -1.175),
        "cost": 370, "damage": 16, "range": 7.5, "rate": 1.7, "speed": 21.0,
        "color": (0.96, 0.56, 0.3), "upgrade": 1600,
        "shot": SHELL, "shot_color": (1.0, 0.46, 0.22), "shot_scale": 1.5, "splash": 1.2,
    },
    {
        # 砲身が 1.35 m と系統でいちばん長く、見た目がレールガンなので、
        # 最終段だけ弾を飛ばさず光線で即着弾させ、周りも巻き込む。
        # **弾速だけ飛び抜けて速い。** 見た目は光線（BeamFx）だが、当てるのは
        # 他の段と同じく飛んでいる弾のほうなので、的が先に倒れれば無駄弾も出る。
        # 8 m を 0.13 秒で渡るので、見た目は「撃った瞬間に当たっている」で通る。
        "file": "tower_apex", "name": "エイペックスタワー", "model": "tower_apex",
        "mount": 0.975, "muzzle": (0.0, 0.25, -1.345),
        "cost": 440, "damage": 22, "range": 8.0, "rate": 1.8, "speed": 22.0,
        "color": (1.0, 0.52, 0.34), "upgrade": 0,
        "shot": BEAM, "shot_color": (1.0, 0.9, 0.62), "shot_scale": 1.6, "splash": 1.6,
    },
]
## 巻き込まれた敵に通るダメージの割合。狙われた 1 体には常に全部入る。
##
## **半径と割合は実測で絞った値。** 最初 2.2 m / 0.5 で出してみたら、
## エイペックス 3 本だけでステージ 1 をライフ 20 のまま完封してしまい、
## 「強化だけでは勝てない（置ける本数と役職の組み合わせが要る）」という
## §16.4-5 の担保が崩れた。道の上で敵が詰まるので、半径が広いと 1 発で
## 4〜5 体に入ってしまうのが効きすぎる原因。
SPLASH_FALLOFF = 0.25


# --- 検算 ---------------------------------------------------------------------

def verify():
    problems = []
    for key in ("cost", "damage", "range"):
        values = [tier[key] for tier in TIERS]
        for i in range(1, len(values)):
            if values[i] <= values[i - 1]:
                problems.append(
                    "%s が段 %d で増えていない (%s -> %s)"
                    % (key, i + 1, values[i - 1], values[i])
                )
    scales = [tier["shot_scale"] for tier in TIERS]
    for i in range(1, len(scales)):
        if scales[i] <= scales[i - 1]:
            problems.append(
                "shot_scale が段 %d で太くなっていない (%s -> %s)"
                % (i + 1, scales[i - 1], scales[i])
            )
    colors = [tier["shot_color"] for tier in TIERS]
    if len(set(colors)) != len(colors):
        problems.append("shot_color が段で重複している（弾を見て段が分からない）")
    if TIERS[0]["splash"] != 0.0:
        problems.append("段 1 に巻き込みが付いている（矢弾は炸裂しない）")
    splashes = [tier["splash"] for tier in TIERS]
    for i in range(2, len(splashes)):
        if splashes[i] <= splashes[i - 1]:
            problems.append(
                "巻き込みの半径が段 %d で広がっていない (%s -> %s)"
                % (i + 1, splashes[i - 1], splashes[i])
            )
    if TIERS[-1]["upgrade"] != 0:
        problems.append("最終段に upgrade_cost が残っている（鎖が終わらない）")
    for tier in TIERS[:-1]:
        if tier["upgrade"] <= 0:
            problems.append("%s の upgrade_cost が 0 なので次段へ上げられない" % tier["file"])
    for tier in TIERS:
        for suffix in ("_base.glb", "_turret.glb"):
            path = os.path.join(MODEL_DIR, tier["model"] + suffix)
            if not os.path.exists(path):
                problems.append("モデルが無い: %s" % os.path.basename(path))
    return problems


# --- 書き出し -----------------------------------------------------------------

def scene_text(tier):
    model = tier["model"]
    mx, my, mz = tier["muzzle"]
    return (
        '[gd_scene load_steps=6 format=3]\n\n'
        '[ext_resource type="Script" path="res://scripts/tower.gd" id="1_tower"]\n'
        '[ext_resource type="PackedScene" path="res://scenes/projectile.tscn" id="2_projectile"]\n'
        '[ext_resource type="PackedScene" path="res://assets/models/%s_base.glb" id="3_base_model"]\n'
        '[ext_resource type="PackedScene" path="res://assets/models/%s_turret.glb" id="4_turret_model"]\n\n'
        '[sub_resource type="SphereShape3D" id="SphereShape3D_range"]\n'
        'radius = %g\n\n'
        '[node name="Tower" type="Node3D"]\n'
        'script = ExtResource("1_tower")\n'
        'projectile_scene = ExtResource("2_projectile")\n\n'
        '[node name="BaseModel" parent="." instance=ExtResource("3_base_model")]\n\n'
        '[node name="Turret" type="Node3D" parent="."]\n'
        'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %g, 0)\n\n'
        '[node name="TurretModel" parent="Turret" instance=ExtResource("4_turret_model")]\n\n'
        '[node name="Muzzle" type="Marker3D" parent="Turret"]\n'
        'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, %g, %g)\n\n'
        '[node name="Range" type="Area3D" parent="."]\n'
        'collision_layer = 0\n'
        'collision_mask = 2\n'
        'monitorable = false\n\n'
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="Range"]\n'
        'shape = SubResource("SphereShape3D_range")\n\n'
        '[node name="FireTimer" type="Timer" parent="."]\n'
        % (model, model, tier["range"], tier["mount"], mx, my, mz)
    )


def _float(value):
    # Godot は "6" を int として読むので、float の欄には必ず小数点を残す。
    return "%g" % value if value != int(value) else "%.1f" % value


def resource_text(tier, next_tier):
    steps = 3 if next_tier is None else 4
    lines = [
        '[gd_resource type="Resource" script_class="TowerData" load_steps=%d format=3]' % steps,
        '',
        '[ext_resource type="Script" path="res://scripts/data/tower_data.gd" id="1_tower_data"]',
        '[ext_resource type="PackedScene" path="res://scenes/%s.tscn" id="2_scene"]' % tier["file"],
    ]
    if next_tier is not None:
        lines.append(
            '[ext_resource type="Resource" path="res://resources/towers/%s.tres" id="3_next"]'
            % next_tier["file"]
        )
    lines += [
        '',
        '[resource]',
        'script = ExtResource("1_tower_data")',
        'display_name = "%s"' % tier["name"],
        'tier = %d' % (TIERS.index(tier) + 1),
        'tower_scene = ExtResource("2_scene")',
        'cost = %d' % tier["cost"],
        'damage = %d' % tier["damage"],
        'attack_range = %s' % _float(tier["range"]),
        'fire_rate = %s' % _float(tier["rate"]),
        'projectile_speed = %s' % _float(tier["speed"]),
        'effect = 0',
        'body_color = Color(%g, %g, %g, 1)' % tier["color"],
        'shot = %d' % tier["shot"],
        'shot_color = Color(%g, %g, %g, 1)' % tier["shot_color"],
        'shot_scale = %s' % _float(tier["shot_scale"]),
        'splash_radius = %s' % _float(tier["splash"]),
        'splash_falloff = %s' % _float(SPLASH_FALLOFF),
        'upgrade_cost = %d' % tier["upgrade"],
    ]
    if next_tier is not None:
        lines.append('next_tier = ExtResource("3_next")')
    lines.append('')
    return "\n".join(lines)


def build():
    problems = verify()
    names = {BOLT: "BOLT", SHELL: "SHELL", ORB: "ORB", BEAM: "BEAM"}
    for i, tier in enumerate(TIERS):
        splash = "巻き込み %.1fm" % tier["splash"] if tier["splash"] > 0 else "単体"
        print("%-14s 段 %d  設置 %3d G / ダメージ %2d / 射程 %.1f / 強化 %4d G"
              " / 弾 %-5s x%.2f / %s"
              % (tier["file"], i + 1, tier["cost"], tier["damage"], tier["range"],
                 tier["upgrade"], names[tier["shot"]], tier["shot_scale"], splash))
    if problems:
        for problem in problems:
            print("    - " + problem)
        raise SystemExit("検算に失敗したので書き出していない。数値を直すこと。")

    for i, tier in enumerate(TIERS):
        # 1 段目のシーンは v1.0 から使っているものをそのまま残す
        # （手で入れた値があるかもしれないので上書きしない）。
        if i > 0:
            path = os.path.join(SCENE_DIR, tier["file"] + ".tscn")
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(scene_text(tier))
        next_tier = TIERS[i + 1] if i + 1 < len(TIERS) else None
        path = os.path.join(TOWER_DIR, tier["file"] + ".tres")
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(resource_text(tier, next_tier))
    print("書き出した: resources/towers/ と scenes/")


if __name__ == "__main__":
    build()
