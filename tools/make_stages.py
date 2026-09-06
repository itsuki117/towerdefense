"""ステージの .tres（道・設置マス・ウェーブ）を書き出す。

使い方 (標準ライブラリだけで動く):

    python tools/make_stages.py

道は座標の塊なので、手で .tres を書くと必ず数字を間違える。
ここで一度に組み立てて、**書き出す前に必ず検算する**:

- 節が高台（プラトー）の内側に収まっているか
- 辺が短すぎないか（節が重なっていると道のリボンが破綻する）

タワーを置けるマスは地形と道から実行時に割り出すので（BuildGrid）、
ここでは道だけを決める。

検算に落ちたら書き出さずに止まる。座標をいじったらこのスクリプトを回す。

道の形は絵に描いたとおり、直線と直角だけで作る。
ステージが進むほど道は長くなるが、**長い道はタワーが撃てる時間が増えるぶん
むしろ易しくなる**。難度はウェーブ側で作ること（バランスの取り直しは §16.4-6）。
"""

import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE_DIR = os.path.join(ROOT, "resources", "stages")

## 辺の最小の長さ。これより短いと道のリボンが破綻する。
MIN_EDGE_LENGTH = 2.0
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
# waves: 使う wave_XX.tres の番号。**tools/make_waves.py が出す番号と揃えること**
#        （波の中身はあちらの表が持っている）。

STAGES = [
    {
        "file": "stage_01",
        "name": "ステージ 1 — 尾根の道",
        # v1.0 と同じ道。既存のバランス基準（タワー3本→波5敗北）を
        # そのまま生かすため、1 面目だけは形を変えない。
        "nodes": [(-11, -9), (-3, -9), (-3, 0), (6, 0), (6, 8), (0, 8)],
        "waves": [1, 2, 3, 4, 5, 6, 7, 8],
        "lives": 20,
        "reward": 2000,
    },
    {
        "file": "stage_02",
        "name": "ステージ 2 — 回り込む道",
        # 絵の 2 枚目。外周をぐるりと回してからクリスタルへ入る。
        "nodes": [(-12, -9), (-3, -9), (-3, -2), (8, -2), (8, 6), (0, 6), (0, 8)],
        "waves": [9, 10, 11, 12, 13, 14, 15, 16],
        "lives": 20,
        "reward": 3400,
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
        "waves": [17, 18, 19, 20, 21, 22, 23, 24, 25, 26],
        "lives": 20,
        "reward": 0,
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

    for a, b in segments:
        if math.hypot(b[0] - a[0], b[1] - a[1]) < MIN_EDGE_LENGTH:
            problems.append("辺 %s-%s が短すぎる" % (a, b))
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
    wave_refs = ", ".join('ExtResource("%d_wave")' % (i + 3) for i in range(len(waves)))
    lines += [
        '',
        '[resource]',
        'script = ExtResource("1_stage_data")',
        'display_name = "%s"' % stage["name"],
        'route = ExtResource("2_route")',
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
        print("%-10s 節 %2d / 辺 %2d / 全長 %5.1f  %s"
              % (stage["file"], len(nodes), len(edges), length,
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
