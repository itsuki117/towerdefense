"""ステージの .tres（道・設置マス・ウェーブ）を書き出す。

使い方 (標準ライブラリだけで動く):

    python tools/make_stages.py

道と設置マスは座標の塊なので、手で .tres を書くと必ず数字を間違える。
ここで一度に組み立てて、**書き出す前に必ず検算する**:

- 設置マスが道に近すぎないか（近いと石の土台が道に食い込む）
- 設置マス同士が重なっていないか
- 節も設置マスも高台（プラトー）の内側に収まっているか

検算に落ちたら書き出さずに止まる。座標をいじったらこのスクリプトを回す。

道の形は絵に描いたとおり、直線と直角だけで作る。
ステージが進むほど道は長くなるが、**長い道はタワーが撃てる時間が増えるぶん
むしろ易しくなる**。難度はウェーブ側で作ること（バランスの取り直しは §16.4-6）。
"""

import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE_DIR = os.path.join(ROOT, "resources", "stages")

## 設置マスを道の中心線から空ける最小距離。
## 道の半幅 1.05 ＋ 土台の半径 0.8 = 1.85。v1.0 で実際に使っていた最小値が
## 2.0 で見た目に問題が無かったので、それをそのまま下限にしている。
MIN_ROAD_CLEARANCE = 2.0
## 設置マス同士の最小距離。
MIN_SPOT_GAP = 2.5
## 高台の範囲（Terrain の plateau_center / plateau_extents に合わせる）。
## 輪郭はノイズで揺れるので、公称値から少し内側を有効範囲とする。
PLATEAU_CENTER = (-1.0, 1.0)
PLATEAU_EXTENTS = (13.5, 12.5)
PLATEAU_MARGIN = 2.0


# --- ステージ定義 -------------------------------------------------------------
# nodes: 節の (x, z)。
# edges: 節番号のペア。省略すると隣り合う節を順につないで 1 本道になる。
# goal:  クリスタルを置く節。省略すると最後の節。
# spots: 設置マスの (x, z)。
# waves: 使う wave_XX.tres の番号。

STAGES = [
    {
        "file": "stage_01",
        "name": "ステージ 1 — 尾根の道",
        # v1.0 と同じ道。既存のバランス基準（タワー3本→波5敗北）を
        # そのまま生かすため、1 面目だけは形を変えない。
        "nodes": [(-11, -9), (-3, -9), (-3, 0), (6, 0), (6, 8), (0, 8)],
        "spots": [
            (-8.5, -7), (-5.5, -6.6), (-5.2, -3), (-1, -6), (-1, -2.2),
            (2.2, -2.4), (2.2, 2.4), (8.6, 3.6), (3.6, 4.6), (2.4, 10.4),
        ],
        "waves": [1, 2, 3, 4, 5, 6, 7, 8],
        "lives": 20,
        "reward": 80,
    },
    {
        "file": "stage_02",
        "name": "ステージ 2 — 回り込む道",
        # 絵の 2 枚目。外周をぐるりと回してからクリスタルへ入る。
        "nodes": [(-12, -9), (-3, -9), (-3, -2), (8, -2), (8, 6), (0, 6), (0, 8)],
        "spots": [
            (-9, -6.5), (-6, -6.5), (-0.5, -6), (-6.2, -2.6), (2, -5), (5.5, -5),
            (5, 1), (10.4, 2), (2.8, 3.4), (-3.5, 6), (3.5, 8.6), (8, 9),
        ],
        "waves": [5, 6, 7, 8],
        "lives": 20,
        "reward": 110,
    },
    {
        "file": "stage_03",
        "name": "ステージ 3 — 分かれ道",
        # 絵の 1 枚目。途中で道が二股に分かれ、合流してからクリスタルへ入る。
        # **2 本の枝は同じ長さ (16)** にしてある。長さで差が付いていると
        # A* が常に同じほうを選び、分岐を作った意味が無くなるため。
        # タワーで片方を守るともう片方が選ばれる、という形にしたい。
        "nodes": [
            (-12, -9), (-4, -9), (-4, -3),
            (-4, 4), (5, 4),            # 北回り（枝 A）
            (5, -3),                    # 南回り（枝 B）
            (5, 8), (0, 8),
        ],
        "edges": [
            (0, 1), (1, 2),
            (2, 3), (3, 4),             # 枝 A: 7 + 9 = 16
            (2, 5), (5, 4),             # 枝 B: 9 + 7 = 16
            (4, 6), (6, 7),
        ],
        "goal": 7,
        "spots": [
            (-8, -6), (-1, -6), (2, -6),
            (-11, -1), (-8, 0), (-8, 3),
            (-1, 0.5), (2.5, 0.5),
            (8, 0), (8.5, 5), (2.5, 6), (-3, 7),
        ],
        "waves": [5, 6, 7, 8],
        "lives": 20,
        "reward": 140,
    },
]


# --- 検算 ---------------------------------------------------------------------

def _distance_to_segment(point, start, end):
    px, pz = point
    ax, az = start
    bx, bz = end
    dx, dz = bx - ax, bz - az
    length_squared = dx * dx + dz * dz
    if length_squared <= 0.0:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / length_squared))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def _inside_plateau(point):
    return (
        abs(point[0] - PLATEAU_CENTER[0]) <= PLATEAU_EXTENTS[0] - PLATEAU_MARGIN
        and abs(point[1] - PLATEAU_CENTER[1]) <= PLATEAU_EXTENTS[1] - PLATEAU_MARGIN
    )


def edges_of(stage):
    nodes = stage["nodes"]
    return stage.get("edges") or [(i, i + 1) for i in range(len(nodes) - 1)]


def goal_of(stage):
    return stage.get("goal", len(stage["nodes"]) - 1)


def verify(stage):
    problems = []
    nodes = stage["nodes"]
    segments = [(nodes[a], nodes[b]) for a, b in edges_of(stage)]

    for point in nodes:
        if not _inside_plateau(point):
            problems.append("節 %s が高台からはみ出している" % (point,))

    for spot in stage["spots"]:
        if not _inside_plateau(spot):
            problems.append("設置マス %s が高台からはみ出している" % (spot,))
        nearest = min(_distance_to_segment(spot, a, b) for a, b in segments)
        if nearest < MIN_ROAD_CLEARANCE:
            problems.append("設置マス %s が道に近すぎる (%.2f < %.2f)"
                            % (spot, nearest, MIN_ROAD_CLEARANCE))

    for i, first in enumerate(stage["spots"]):
        for second in stage["spots"][i + 1:]:
            gap = math.hypot(first[0] - second[0], first[1] - second[1])
            if gap < MIN_SPOT_GAP:
                problems.append("設置マス %s と %s が近すぎる (%.2f)" % (first, second, gap))
    return problems


# --- 書き出し -----------------------------------------------------------------

def route_text(stage):
    nodes = stage["nodes"]
    node_values = ", ".join("%g, 0, %g" % (x, z) for x, z in nodes)
    edges = ", ".join("Vector2i(%d, %d)" % pair for pair in edges_of(stage))
    return (
        '[gd_resource type="Resource" script_class="RouteData" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://scripts/data/route_data.gd" id="1_route_data"]\n\n'
        '[resource]\n'
        'script = ExtResource("1_route_data")\n'
        'nodes = PackedVector3Array(%s)\n'
        'edges = Array[Vector2i]([%s])\n'
        'spawn_node = 0\n'
        'goal_node = %d\n' % (node_values, edges, len(nodes) - 1)
    )


def stage_text(stage):
    waves = stage["waves"]
    lines = [
        '[gd_resource type="Resource" script_class="StageData" load_steps=%d format=3]\n'
        % (3 + len(waves)),
        '',
        '[ext_resource type="Script" path="res://scripts/data/stage_data.gd" id="1_stage_data"]',
        '[ext_resource type="Resource" path="res://resources/stages/%s_route.tres" id="2_route"]'
        % stage["file"],
    ]
    for index, number in enumerate(waves):
        lines.append(
            '[ext_resource type="Resource" path="res://resources/waves/wave_%02d.tres" id="%d_wave"]'
            % (number, index + 3)
        )
    spots = ", ".join("%g, 0, %g" % (x, z) for x, z in stage["spots"])
    wave_refs = ", ".join('ExtResource("%d_wave")' % (i + 3) for i in range(len(waves)))
    lines += [
        '',
        '[resource]',
        'script = ExtResource("1_stage_data")',
        'display_name = "%s"' % stage["name"],
        'route = ExtResource("2_route")',
        'build_spots = PackedVector3Array(%s)' % spots,
        'waves = [%s]' % wave_refs,
        'lives = %d' % stage["lives"],
        'clear_reward = %d' % stage["reward"],
        '',
    ]
    return "\n".join(lines)


def campaign_text():
    lines = [
        '[gd_resource type="Resource" script_class="CampaignData" load_steps=%d format=3]\n'
        % (2 + len(STAGES)),
        '',
        '[ext_resource type="Script" path="res://scripts/data/campaign_data.gd" id="1_campaign"]',
    ]
    for index, stage in enumerate(STAGES):
        lines.append(
            '[ext_resource type="Resource" path="res://resources/stages/%s.tres" id="%d_stage"]'
            % (stage["file"], index + 2)
        )
    refs = ", ".join('ExtResource("%d_stage")' % (i + 2) for i in range(len(STAGES)))
    lines += ['', '[resource]', 'script = ExtResource("1_campaign")', 'stages = [%s]' % refs, '']
    return "\n".join(lines)


def build():
    failed = False
    for stage in STAGES:
        problems = verify(stage)
        nodes = stage["nodes"]
        edges = edges_of(stage)
        length = sum(
            math.hypot(nodes[b][0] - nodes[a][0], nodes[b][1] - nodes[a][1]) for a, b in edges
        )
        print("%-10s 節 %2d / 辺 %2d / マス %2d / 全長 %5.1f  %s"
              % (stage["file"], len(nodes), len(edges), len(stage["spots"]), length,
                 "OK" if not problems else "NG"))
        for problem in problems:
            print("    - " + problem)
            failed = True
    if failed:
        raise SystemExit("検算に失敗したので書き出していない。座標を直すこと。")

    os.makedirs(STAGE_DIR, exist_ok=True)
    for stage in STAGES:
        with open(os.path.join(STAGE_DIR, stage["file"] + "_route.tres"), "w",
                  encoding="utf-8", newline="\n") as handle:
            handle.write(route_text(stage))
        with open(os.path.join(STAGE_DIR, stage["file"] + ".tres"), "w",
                  encoding="utf-8", newline="\n") as handle:
            handle.write(stage_text(stage))
    with open(os.path.join(ROOT, "resources", "campaign.tres"), "w",
              encoding="utf-8", newline="\n") as handle:
        handle.write(campaign_text())
    print("書き出した: resources/stages/ と resources/campaign.tres")


if __name__ == "__main__":
    build()
