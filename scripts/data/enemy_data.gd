class_name EnemyData
extends Resource
## 敵 1 種類ぶんのステータス。
##
## 敵シーンは 1 つだけ用意し、種類の差は「シーンではなくこの Resource」で作る。
## 色とスケールもデータ側に持たせているので、.tres を増やすだけで見た目違いの敵が増える。

@export var display_name: String = "Enemy"
## 最大 HP。
@export var max_hp: int = 10
## 1 発ごとに差し引く装甲。**HP を増やすのとは効き方が違う。**
##
## HP を増やすと「弱い弾をたくさん」でも「強い弾を少し」でも同じだけ効くが、
## 装甲は 1 発ごとに引かれるので、**弱い弾を連射するほど損**になる。
## タワーの段を上げる理由（1 発が重くなる）を作るための数値。
## 波ごとの硬さ (WaveEntry.hp_scale) には平方根で連れて上がる。
@export var armor: int = 0
## 移動速度 (m/秒)。Path3D 上の progress をこの速度で進める。
@export_range(0.5, 20.0, 0.1) var speed: float = 2.5
## 撃破時にプレイヤーへ入るゴールド。
@export var gold_value: int = 5
## 拠点に到達されたときに減るライフ。
@export var damage: int = 1
## 足止めしてきた戦士に与えるダメージ。
@export var melee_damage: int = 4
## 戦士への攻撃レート (回/秒)。
@export_range(0.1, 5.0, 0.1) var attack_rate: float = 1.0
@export var body_color: Color = Color(0.35, 0.75, 0.4)
@export_range(0.1, 2.0, 0.05) var body_scale: float = 1.0
## 装甲を持つ敵にかぶせる殻の色。armor が 0 なら使われない。
@export var armor_color: Color = Color(0.62, 0.66, 0.72)

@export_group("分裂")
## 倒されたときに湧く子の種別。null なら分裂しない。
##
## **範囲攻撃への答えとして足した。** 固まったところを爆発でまとめて消せるように
## なったぶん、「まとめて消すと的が増える」敵を用意して釣り合いを戻している。
## 拠点に到達したときは分裂しない（通り抜けた敵が増え続けてしまう）。
@export var split_into: EnemyData
## 何体に分かれるか。
@export_range(0, 4, 1) var split_count: int = 2
