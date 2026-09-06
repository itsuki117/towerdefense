"""非常用の仮効果音 WAV を合成して assets/audio/ に書き出す。

使い方 (標準ライブラリだけで動く):

    python tools/make_sfx.py

外部音源が欠けた場合でも「鳴るべき所で鳴っているか」を確認できるよう、
必要な数だけその場で合成するために残している。

**実行すると現在の CC0 効果音を仮音で上書きする。** 通常の制作では実行しないこと。
採用中の外部音源は assets/audio/SOURCES.md を参照。

音作りの方針:

- 22050 Hz / 16bit / モノラル。短いブリップばかりなので音質より容量を優先
- 三角波は輪郭が出つつ角が立たないので「撃つ・作る」、ノイズは「当たる・壊れる」に使う
- 端は必ずフェードする。切りっぱなしだとプチッというクリック音が乗る
- 音量は種類ごとに変える。連射される音（shoot / hit）を小さめにしないとうるさい
- 仕上げに 1 次のローパスを通して高い成分を削る。矩形波と生ノイズは
  ジリジリと耳に刺さるので、そのままでは聞き続けられない

"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
## 端のフェード（秒）。これより短いとクリックが残る。
FADE = 0.004

random.seed(20260905)


def _samples(duration):
    return int(RATE * duration)


def silence(duration):
    return [0.0] * _samples(duration)


def tone(duration, freq_start, freq_end=None, shape="square", decay=12.0, volume=1.0):
    """指定の長さの音を作る。freq_end を渡すと周波数がそこまで滑らかに動く。"""
    freq_end = freq_start if freq_end is None else freq_end
    out = []
    phase = 0.0
    total = _samples(duration)
    for i in range(total):
        t = i / RATE
        ratio = i / max(total - 1, 1)
        # 周波数は対数で補間する。線形だと下がり方が不自然に聞こえる。
        freq = freq_start * ((freq_end / freq_start) ** ratio)
        phase += freq / RATE
        cycle = phase % 1.0
        if shape == "square":
            value = 1.0 if cycle < 0.5 else -1.0
        elif shape == "triangle":
            value = 1.0 - 4.0 * abs(cycle - 0.5)
        elif shape == "saw":
            value = cycle * 2.0 - 1.0
        else:
            value = math.sin(cycle * math.tau)
        out.append(value * math.exp(-decay * t) * volume)
    return out


def noise(duration, decay=20.0, volume=1.0, smooth=0.0):
    """ノイズ。smooth を上げると高い成分が削れて、破裂音から風切り音に寄る。"""
    out = []
    previous = 0.0
    for i in range(_samples(duration)):
        t = i / RATE
        value = random.uniform(-1.0, 1.0)
        if smooth > 0.0:
            value = previous + (value - previous) * (1.0 - smooth)
            previous = value
        out.append(value * math.exp(-decay * t) * volume)
    return out


def lowpass(samples, amount):
    """1 次のローパス。amount が小さいほど高い成分が削れて丸くなる。"""
    out = []
    previous = 0.0
    for value in samples:
        previous += (value - previous) * amount
        out.append(previous)
    return out


def mix(*layers):
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, value in enumerate(layer):
            out[i] += value
    return out


def join(*parts):
    out = []
    for part in parts:
        out.extend(part)
    return out


def melody(notes, note_duration, shape="triangle", decay=9.0, volume=1.0):
    """音階を並べる。勝敗やウェーブ開始の合図に使う。"""
    parts = []
    for freq in notes:
        # 矩形波だけだと硬いので、1 オクターブ上のサインを薄く重ねる。
        parts.append(mix(
            tone(note_duration, freq, shape=shape, decay=decay, volume=volume),
            tone(note_duration, freq * 2.0, shape="sine", decay=decay * 1.4, volume=volume * 0.3),
        ))
    return join(*parts)


def finish(samples, peak=0.8, tone_down=0.5):
    """角を落とし、正規化して端をフェードする。書き出し直前に必ず通す。"""
    samples = lowpass(samples, tone_down)
    loudest = max((abs(v) for v in samples), default=0.0)
    if loudest > 0.0:
        gain = peak / loudest
        samples = [v * gain for v in samples]
    fade = min(_samples(FADE), len(samples) // 2)
    for i in range(fade):
        scale = i / fade
        samples[i] *= scale
        samples[-1 - i] *= scale
    return samples


def write(name, samples):
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, value)) * 32767)) for value in samples
        )
        handle.writeframes(frames)
    print("%-16s %5.2f KB" % (name + ".wav", os.path.getsize(path) / 1024.0))


def build():
    os.makedirs(OUT_DIR, exist_ok=True)

    # 連射される音。短く小さく、余韻を残さない。
    write("shoot_arrow", finish(mix(
        tone(0.09, 620.0, 300.0, shape="triangle", decay=26.0),
        noise(0.02, decay=90.0, volume=0.35, smooth=0.4),
    ), peak=0.3, tone_down=0.35))

    write("shoot_frost", finish(mix(
        tone(0.15, 900.0, 1500.0, shape="sine", decay=14.0),
        noise(0.15, decay=11.0, volume=0.45, smooth=0.75),
    ), peak=0.28, tone_down=0.3))

    write("hit", finish(mix(
        noise(0.06, decay=48.0, smooth=0.5),
        tone(0.05, 240.0, 160.0, shape="triangle", decay=40.0, volume=0.6),
    ), peak=0.24, tone_down=0.3))

    # 撃破。ノイズで壊れる感じ、低い矩形波で重さを出す。
    write("enemy_die", finish(mix(
        noise(0.26, decay=13.0, smooth=0.6),
        tone(0.24, 280.0, 80.0, shape="triangle", decay=11.0, volume=0.8),
    ), peak=0.45, tone_down=0.28))

    # 建てた合図。上がる 2 音で「成立した」感じにする。
    write("build", finish(join(
        tone(0.07, 392.0, shape="triangle", decay=16.0),
        tone(0.14, 587.0, shape="triangle", decay=11.0),
    ), peak=0.38, tone_down=0.4))

    # ライフが減った。下がる音＋わずかな揺れで嫌な感じを出す。
    write("life_lost", finish(mix(
        tone(0.42, 330.0, 130.0, shape="saw", decay=5.5),
        tone(0.42, 331.5, 131.0, shape="sine", decay=5.5, volume=0.6),
    ), peak=0.5, tone_down=0.35))

    write("wave_start", finish(
        melody([523.25, 659.25, 783.99], 0.12, shape="triangle", decay=10.0),
        peak=0.42, tone_down=0.4))
    write("victory", finish(
        melody([523.25, 659.25, 783.99, 1046.50], 0.16, shape="triangle", decay=6.5),
        peak=0.55, tone_down=0.4))
    write("defeat", finish(
        melody([392.0, 329.63, 261.63, 196.0], 0.17, shape="triangle", decay=5.0),
        peak=0.55, tone_down=0.3))


if __name__ == "__main__":
    build()
