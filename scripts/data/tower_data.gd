class_name TowerData
extends Resource
## タワー 1 種類ぶんのステータス。
##
## EnemyData と同じ方針で、タワーシーンは 1 つ・差分は .tres で表現する。

## 追加効果。SLOW の適用はステップ6（2 種類目のタワー）で実装する。
enum Effect { NONE, SLOW }

@export var display_name: String = "Tower"
## 設置コスト（ゴールド）。
@export var cost: int = 50
## 1 発あたりのダメージ。
@export var damage: int = 4
## 射程 (m)。Area3D の SphereShape3D 半径に反映される。
@export_range(1.0, 20.0, 0.5) var attack_range: float = 6.0
## 発射レート (発/秒)。
@export_range(0.1, 10.0, 0.1) var fire_rate: float = 1.5
## 弾速 (m/秒)。
@export var projectile_speed: float = 18.0
@export var effect: Effect = Effect.NONE
@export var body_color: Color = Color(0.85, 0.72, 0.35)
