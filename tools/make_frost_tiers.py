"""フロストタワーのティア 5 段ぶんの .tres と .tscn を書き出す。

使い方 (標準ライブラリだけで動く):

    python tools/make_frost_tiers.py

`tools/make_tower_tiers.py`（アロー系）とほぼ同じ構造だが、フロストタワーは
`effect = SLOW` と slow_factor / slow_duration を持つので専用スクリプトにしてある。
段が上がるほど耐久力を削るだけでなく **足止めそのものが強くなる**
（slow_factor が下がる＝敵の速度倍率が下がる、slow_duration が延びる）。

5 段のモデルは Blender で作ったもの (tools/export_tower_models.py で .glb 化済み)。
Turret の取り付け高さと Muzzle の位置はモデルごとに違うので、
書き出し時に表示された値をここに写して .tscn を組み立てる。

**書き出す前に必ず検算する**:

- 設置費用・ダメージ・射程が段ごとに増えているか（下位が上位に勝たない）
- slow_factor が段ごとに下がっている・slow_duration が伸びているか
  （足止めそのものが弱くなる段があってはいけない）
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
# file        : .tres / .tscn のファイル名。
# model       : assets/models/<model>_base.glb と _turret.glb を使う。
# mount       : Turret ノードの Y（= .blend の砲塔の取り付け高さ）。
# muzzle      : Muzzle の位置（Turret ローカル）。
#               mount と muzzle は export_tower_models.py が出力した値をそのまま写す。
# slow_factor : 敵の移動速度に掛かる倍率。低いほど強く足止めする。
# slow_duration: 効果が続く秒数。
# upgrade     : この段から次の段へ上げる費用。最終段は 0（これ以上上がらない）。

# shot_color / shot_scale : 氷の玉の色と大きさ。**段ごとに大きく・淡くする**ので、
#           飛んでいる弾を見ただけで何段目のフロストタワーかが分かる。

## 氷の玉。フロスト系は 5 段ともこれで統一する（系統の見分けが弾にも出るように）。
ORB = 2

TIERS = [
    {
        "file": "tower_frost", "name": "フロストタワー", "model": "tower_slow",
        "mount": 0.52, "muzzle": (0.09, 0.175, -0.79),
        "cost": 170, "damage": 4, "range": 6.0, "rate": 1.5, "speed": 22.0,
        "slow_factor": 0.35, "slow_duration": 2.5,
        "color": (0.45, 0.72, 0.95), "upgrade": 500,
        "shot_color": (0.55, 0.82, 1.0), "shot_scale": 0.9,
    },
    {
        "file": "tower_glacier", "name": "グレイシャータワー", "model": "tower_frost2",
        "mount": 0.7850, "muzzle": (0.0900, 0.2145, -0.8760),
        "cost": 215, "damage": 6, "range": 6.5, "rate": 1.5, "speed": 23.0,
        "slow_factor": 0.30, "slow_duration": 2.8,
        "color": (0.40, 0.68, 0.93), "upgrade": 850,
        "shot_color": (0.62, 0.88, 1.0), "shot_scale": 1.05,
    },
    {
        "file": "tower_blizzard", "name": "ブリザードタワー", "model": "tower_frost3",
        "mount": 0.7850, "muzzle": (0.0900, 0.1815, -0.8760),
        "cost": 265, "damage": 9, "range": 7.0, "rate": 1.6, "speed": 24.0,
        "slow_factor": 0.26, "slow_duration": 3.1,
        "color": (0.55, 0.85, 0.98), "upgrade": 1100,
        "shot_color": (0.72, 0.93, 1.0), "shot_scale": 1.2,
    },
    {
        "file": "tower_permafrost", "name": "パーマフロストタワー", "model": "tower_frost4",
        "mount": 0.8750, "muzzle": (0.0900, 0.1815, -0.8760),
        "cost": 320, "damage": 13, "range": 7.5, "rate": 1.6, "speed": 25.0,
        "slow_factor": 0.22, "slow_duration": 3.4,
        "color": (0.75, 0.93, 1.0), "upgrade": 1450,
        "shot_color": (0.82, 0.96, 1.0), "shot_scale": 1.35,
    },
    {
        "file": "tower_absolute_zero", "name": "アブソリュートゼロタワー", "model": "tower_frost5",
        "mount": 0.9550, "muzzle": (0.0900, 0.1700, -0.8760),
        "cost": 385, "damage": 18, "range": 8.0, "rate": 1.7, "speed": 26.0,
        "slow_factor": 0.18, "slow_duration": 3.8,
        "color": (0.9, 0.98, 1.0), "upgrade": 0,
        "shot_color": (0.93, 0.99, 1.0), "shot_scale": 1.55,
    },
]


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
    slow_factors = [tier["slow_factor"] for tier in TIERS]
    for i in range(1, len(slow_factors)):
        if slow_factors[i] >= slow_factors[i - 1]:
            problems.append(
                "slow_factor が段 %d で下がっていない=足止めが強くなっていない (%s -> %s)"
                % (i + 1, slow_factors[i - 1], slow_factors[i])
            )
    durations = [tier["slow_duration"] for tier in TIERS]
    for i in range(1, len(durations)):
        if durations[i] <= durations[i - 1]:
            problems.append(
                "slow_duration が段 %d で伸びていない (%s -> %s)"
                % (i + 1, durations[i - 1], durations[i])
            )
    scales = [tier["shot_scale"] for tier in TIERS]
    for i in range(1, len(scales)):
        if scales[i] <= scales[i - 1]:
            problems.append(
                "shot_scale が段 %d で大きくなっていない (%s -> %s)"
                % (i + 1, scales[i - 1], scales[i])
            )
    colors = [tier["shot_color"] for tier in TIERS]
    if len(set(colors)) != len(colors):
        problems.append("shot_color が段で重複している（弾を見て段が分からない）")
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
        'effect = 1',
        'slow_factor = %s' % _float(tier["slow_factor"]),
        'slow_duration = %s' % _float(tier["slow_duration"]),
        'body_color = Color(%g, %g, %g, 1)' % tier["color"],
        'shot = %d' % ORB,
        'shot_color = Color(%g, %g, %g, 1)' % tier["shot_color"],
        'shot_scale = %s' % _float(tier["shot_scale"]),
        'shoot_sfx = &"shoot_frost"',
        'upgrade_cost = %d' % tier["upgrade"],
    ]
    if next_tier is not None:
        lines.append('next_tier = ExtResource("3_next")')
    lines.append('')
    return "\n".join(lines)


def build():
    problems = verify()
    for i, tier in enumerate(TIERS):
        print("%-20s 段 %d  設置 %3d G / ダメージ %2d / 射程 %.1f / 減速 x%.2f %.1fs / 強化 %4d G"
              % (tier["file"], i + 1, tier["cost"], tier["damage"], tier["range"],
                 tier["slow_factor"], tier["slow_duration"], tier["upgrade"]))
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
