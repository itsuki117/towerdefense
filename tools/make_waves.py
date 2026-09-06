"""ウェーブの .tres を書き出す。

使い方 (標準ライブラリだけで動く):

    python tools/make_waves.py

波は「敵種 × 数 × 出現間隔」の組でしかないので、手で .tres を書くと
数字がステージをまたいで揃わなくなる。ここで 1 つの表にまとめて出す。

**ステージ 1 の 8 波は v1.0 と同じ数値**。既存のバランス基準
（タワー 3 本 → 波 5〜6 で敗北）をそのまま生かすため、ここは触らない。

敵の HP は EnemyData 側にあって波に依存しないので、**難度は数・間隔・
はやい敵の比率だけで作る**。後半ほど数を増やし、間隔を詰め、はやい敵を混ぜる。

**書き出す前に必ず検算する**:

- ステージの中で「敵の総数」が波ごとに増えているか（後半が楽にならないこと）
- 出現間隔が下限を割っていないか（同時に出る数が増えすぎて描画が持たない）
- ステージをまたいで初手が前ステージの最終波を超えていないか（落差の確認）

検算に落ちたら書き出さずに止まる。
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WAVE_DIR = os.path.join(ROOT, "resources", "waves")

## 出現間隔の下限。これを割ると同時に出る数が跳ね上がる。
MIN_INTERVAL = 0.3

# --- 波の定義 -----------------------------------------------------------------
# 1 波 = {
#   "normal": (数, 間隔),
#   "fast":   (数, 間隔, 遅らせる秒) または None,
#   "hp":     HP 倍率,
#   "delay":  次の波までの秒,
# }
#
# fast の start_delay は「通常の敵が先に出て、そこへ速い敵が追い付く」形を作るためのもの。
# 0 にすると全部が同時に出てきて、速い敵を混ぜた意味が薄れる。
#
# **後半の難度は数ではなく HP 倍率で作る。** 数だけで上げると画面を埋め尽くす
# 物量にしかならず、描画も重くなる。獲得ゴールドは倍率で増えないので、
# 後半ほど 1 ゴールドあたりの HP が重くなり、稼ぎの伸びも自然に抑えられる。

STAGES = {
    # ステージ 1 — v1.0 と同じ数値。HP 倍率も 1.0 のまま。触らないこと。
    1: [
        {"normal": (4, 1.2), "fast": None, "hp": 1.0, "delay": 6.0},
        {"normal": (6, 1.1), "fast": None, "hp": 1.0, "delay": 6.0},
        {"normal": (8, 1.0), "fast": None, "hp": 1.0, "delay": 5.5},
        {"normal": (10, 0.95), "fast": (3, 0.8, 3.0), "hp": 1.0, "delay": 5.5},
        {"normal": (16, 0.8), "fast": (7, 0.7, 3.0), "hp": 1.0, "delay": 5.0},
        {"normal": (23, 0.7), "fast": (11, 0.6, 3.0), "hp": 1.0, "delay": 5.0},
        {"normal": (32, 0.55), "fast": (18, 0.5, 2.5), "hp": 1.0, "delay": 4.5},
        {"normal": (42, 0.5), "fast": (25, 0.4, 2.5), "hp": 1.0, "delay": 4.0},
    ],
    # ステージ 2 — 敵の**数はステージ 1 とほぼ同じ**にして、硬さだけを上げる。
    #
    # 数で難度を作ると獲得ゴールドも一緒に増えてしまい、盤面を埋めるだけで勝ててしまう
    # （実測: 全マスに最上位タワーを建てるとライフを 1 も失わなかった）。
    # 数を据え置けば 1 ステージの収入もほぼ据え置きになり、
    # 「安いタワーで数を並べるか、高いタワーを少なく置くか」の選択が生きる。
    #
    # **序盤は必ず軽く始める。** ステージが変わると設置はリセットされるので、
    # 1 波目は「盤面がほぼ空」で受けることになる。前ステージの終盤の重さで
    # 始めると、建て直す前に押し切られる（実測: 波 3 で敗北した）。
    2: [
        {"normal": (6, 1.1), "fast": (2, 1.0, 3.0), "hp": 1.2, "delay": 5.5},
        {"normal": (9, 1.0), "fast": (3, 0.9, 3.0), "hp": 1.3, "delay": 5.5},
        {"normal": (12, 0.95), "fast": (5, 0.85, 3.0), "hp": 1.4, "delay": 5.0},
        {"normal": (15, 0.9), "fast": (7, 0.8, 2.5), "hp": 1.6, "delay": 5.0},
        {"normal": (18, 0.85), "fast": (9, 0.75, 2.5), "hp": 1.8, "delay": 4.5},
        {"normal": (21, 0.8), "fast": (12, 0.7, 2.5), "hp": 2.0, "delay": 4.5},
        {"normal": (25, 0.7), "fast": (15, 0.6, 2.0), "hp": 2.1, "delay": 4.0},
        {"normal": (29, 0.65), "fast": (19, 0.55, 2.0), "hp": 2.3, "delay": 4.0},
    ],
    # ステージ 3 — 最終ステージ。分かれ道なので敵が 2 手に散る（＝守りが薄まる）。
    # 波数も 10 に増やして、持ちこたえる長さそのものも難度にしている。
    # ここでも数は増やさず、硬さで上げる。序盤を軽くするのはステージ 2 と同じ理由。
    3: [
        {"normal": (8, 1.0), "fast": (3, 0.9, 2.5), "hp": 2.6, "delay": 5.5},
        {"normal": (11, 0.95), "fast": (5, 0.85, 2.5), "hp": 2.8, "delay": 5.0},
        {"normal": (14, 0.9), "fast": (7, 0.8, 2.5), "hp": 3, "delay": 5.0},
        {"normal": (17, 0.85), "fast": (9, 0.75, 2.0), "hp": 3.2, "delay": 4.5},
        {"normal": (20, 0.8), "fast": (11, 0.7, 2.0), "hp": 3.4, "delay": 4.5},
        {"normal": (23, 0.75), "fast": (14, 0.65, 2.0), "hp": 3.6, "delay": 4.5},
        {"normal": (26, 0.7), "fast": (17, 0.6, 2.0), "hp": 3.9, "delay": 4.0},
        {"normal": (30, 0.65), "fast": (20, 0.55, 1.5), "hp": 4.1, "delay": 4.0},
        {"normal": (34, 0.6), "fast": (24, 0.5, 1.5), "hp": 4.1, "delay": 3.5},
        {"normal": (40, 0.55), "fast": (29, 0.45, 1.5), "hp": 4.3, "delay": 3.5},
    ],
}


def wave_numbers(stage):
    """そのステージの波が wave_XX.tres の何番になるか。ステージ順に連番。"""
    start = 1
    for number in sorted(STAGES):
        if number == stage:
            return list(range(start, start + len(STAGES[stage])))
        start += len(STAGES[number])
    return []


# --- 検算 ---------------------------------------------------------------------

def total_enemies(wave):
    total = wave["normal"][0]
    if wave["fast"] is not None:
        total += wave["fast"][0]
    return total


## 撃破ゴールド（EnemyData の gold_value）。**数を据え置く方針の確認に使う。**
GOLD_NORMAL = 9
GOLD_FAST = 13


def stage_gold(stage):
    total = 0
    for wave in STAGES[stage]:
        total += wave["normal"][0] * GOLD_NORMAL
        if wave["fast"] is not None:
            total += wave["fast"][0] * GOLD_FAST
    return total


def weight(wave):
    """波の重さ。数だけだと HP 倍率で上げた波を「軽くなった」と誤判定する。"""
    return total_enemies(wave) * wave["hp"]


def verify():
    problems = []
    for stage in sorted(STAGES):
        waves = STAGES[stage]
        for i, wave in enumerate(waves):
            if wave["normal"][1] < MIN_INTERVAL:
                problems.append("ステージ %d 波 %d: 通常の間隔が下限を割っている" % (stage, i + 1))
            if wave["fast"] is not None and wave["fast"][1] < MIN_INTERVAL:
                problems.append("ステージ %d 波 %d: 速い敵の間隔が下限を割っている" % (stage, i + 1))
            if i > 0 and weight(wave) <= weight(waves[i - 1]):
                problems.append(
                    "ステージ %d 波 %d: 波の重さが前の波より増えていない" % (stage, i + 1)
                )
            if i > 0 and wave["hp"] < waves[i - 1]["hp"]:
                problems.append("ステージ %d 波 %d: HP 倍率が下がっている" % (stage, i + 1))
    for stage in sorted(STAGES)[1:]:
        previous = STAGES[stage - 1][-1]
        first = STAGES[stage][0]
        if weight(first) > weight(previous):
            problems.append(
                "ステージ %d の初手が前ステージの最終波より重い（落差が無い）" % stage
            )
        if first["hp"] < previous["hp"]:
            problems.append("ステージ %d の初手で HP 倍率が下がっている" % stage)
    return problems


# --- 書き出し -----------------------------------------------------------------

def _float(value):
    # Godot は "4" を int として読むので、float の欄には必ず小数点を残す。
    return "%g" % value if value != int(value) else "%.1f" % value


def entry_text(name, resource_id, count, interval, start_delay, hp_scale):
    lines = [
        '[sub_resource type="Resource" id="Resource_entry_%s"]' % name,
        'script = ExtResource("2_wave_entry")',
        'enemy_data = ExtResource("%s")' % resource_id,
        "count = %d" % count,
        "spawn_interval = %s" % _float(interval),
    ]
    if start_delay > 0.0:
        lines.append("start_delay = %s" % _float(start_delay))
    if hp_scale != 1.0:
        lines.append("hp_scale = %s" % _float(hp_scale))
    return "\n".join(lines)


def wave_text(wave):
    header = [
        '[gd_resource type="Resource" script_class="WaveData" load_steps=%d format=3]'
        % (5 if wave["fast"] is not None else 4),
        "",
        '[ext_resource type="Script" path="res://scripts/data/wave_data.gd" id="1_wave_data"]',
        '[ext_resource type="Script" path="res://scripts/data/wave_entry.gd" id="2_wave_entry"]',
        '[ext_resource type="Resource" path="res://resources/enemies/enemy_normal.tres" id="3_enemy_normal"]',
    ]
    if wave["fast"] is not None:
        header.append(
            '[ext_resource type="Resource" path="res://resources/enemies/enemy_fast.tres"'
            ' id="4_enemy_fast"]'
        )
    body = ["", entry_text(
        "normal", "3_enemy_normal", wave["normal"][0], wave["normal"][1], 0.0, wave["hp"]
    )]
    refs = ['SubResource("Resource_entry_normal")']
    if wave["fast"] is not None:
        count, interval, delay = wave["fast"]
        body += ["", entry_text("fast", "4_enemy_fast", count, interval, delay, wave["hp"])]
        refs.append('SubResource("Resource_entry_fast")')
    tail = [
        "",
        "[resource]",
        'script = ExtResource("1_wave_data")',
        "entries = [%s]" % ", ".join(refs),
        "next_wave_delay = %s" % _float(wave["delay"]),
        "",
    ]
    return "\n".join(header + body + tail)


def build():
    problems = verify()
    for stage in sorted(STAGES):
        numbers = wave_numbers(stage)
        counts = " ".join("%d" % total_enemies(w) for w in STAGES[stage])
        weights = " ".join("%.0f" % weight(w) for w in STAGES[stage])
        print("ステージ %d  波 %d 本 (wave_%02d〜%02d)"
              % (stage, len(numbers), numbers[0], numbers[-1]))
        print("    敵の数: %s" % counts)
        print("    重さ  : %s" % weights)
        print("    ステージ合計: 敵 %d 体 / 撃破ゴールド 約 %d G"
              % (sum(total_enemies(w) for w in STAGES[stage]), stage_gold(stage)))
    if problems:
        for problem in problems:
            print("    - " + problem)
        raise SystemExit("検算に失敗したので書き出していない。数値を直すこと。")

    os.makedirs(WAVE_DIR, exist_ok=True)
    for stage in sorted(STAGES):
        for number, wave in zip(wave_numbers(stage), STAGES[stage]):
            path = os.path.join(WAVE_DIR, "wave_%02d.tres" % number)
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(wave_text(wave))
    print("書き出した: resources/waves/ (%d 本)" % sum(len(w) for w in STAGES.values()))
    print("※ ステージ側の波の割り当ては tools/make_stages.py を回すこと")


if __name__ == "__main__":
    build()
