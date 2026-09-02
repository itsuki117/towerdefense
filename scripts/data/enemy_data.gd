class_name EnemyData
extends Resource
## 敵 1 種類ぶんのステータス。
##
## 敵シーンは 1 つだけ用意し、種類の差は「シーンではなくこの Resource」で作る。
## 色とスケールもデータ側に持たせているので、.tres を増やすだけで見た目違いの敵が増える。

@export var display_name: String = "Enemy"
## 最大 HP。
@export var max_hp: int = 10
## 移動速度 (m/秒)。Path3D 上の progress をこの速度で進める。
@export_range(0.5, 20.0, 0.1) var speed: float = 2.5
## 撃破時にプレイヤーへ入るゴールド。
@export var gold_value: int = 5
## 拠点に到達されたときに減るライフ。
@export var damage: int = 1
@export var body_color: Color = Color(0.35, 0.75, 0.4)
@export_range(0.1, 2.0, 0.05) var body_scale: float = 1.0
