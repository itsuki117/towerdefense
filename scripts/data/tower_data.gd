class_name TowerData
extends Resource
## タワー 1 種類ぶんのステータス。
##
## EnemyData と同じ方針で、タワーシーンは 1 つ・差分は .tres で表現する。

## 追加効果。命中時に Projectile が適用する。
enum Effect { NONE, SLOW }

@export var display_name: String = "Tower"
## このタワー専用のシーン。Blender で作ったモデルを持つタワーはここで指定する。
## null なら BuildManager の default_tower_scene（プリミティブ表示）が使われ、
## 見た目は body_color だけで差を付ける。
@export var tower_scene: PackedScene
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
## effect が SLOW のときの速度倍率。0.5 なら敵の移動速度が半分になる。
@export_range(0.05, 1.0, 0.05) var slow_factor: float = 0.5
## 減速が続く秒数。effect が SLOW のときだけ意味を持つ。
@export_range(0.1, 10.0, 0.1) var slow_duration: float = 1.5
@export var body_color: Color = Color(0.85, 0.72, 0.35)
## 発射音の名前。Sfx.LIBRARY のキーを指す。
@export var shoot_sfx: StringName = &"shoot_arrow"
