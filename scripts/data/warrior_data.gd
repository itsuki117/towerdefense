class_name WarriorData
extends Resource
## 自軍ユニット 1 種類ぶんのステータス。
##
## EnemyData / TowerData と同じ方針で、シーンは 1 つ・差分は .tres で表現する。
## 役職を増やすときはここに .tres を足すだけで済ませたい（§16.4-5）。

@export var display_name: String = "戦士"
## 雇用コスト（ゴールド）。タワーと同じ経済から出す。
@export var cost: int = 40
@export var max_hp: int = 40
## 1 回の攻撃で与えるダメージ。
@export var damage: int = 5
## 攻撃レート (回/秒)。
@export_range(0.1, 5.0, 0.1) var attack_rate: float = 1.2
## 道の上を進む速さ (m/秒)。
@export_range(0.5, 10.0, 0.1) var move_speed: float = 3.0
## この距離まで近づいた敵を足止めする。
@export_range(0.5, 5.0, 0.1) var engage_radius: float = 1.1
@export var body_color: Color = Color(0.82, 0.78, 0.68)
