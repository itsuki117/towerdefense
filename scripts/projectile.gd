class_name Projectile
extends Area3D
## タワーが撃つ弾。ターゲットを追尾し、到達したらダメージを与えて消える。
##
## 追尾で必ず当たるため衝突判定は使わず、距離で命中を判定している
## （撃った瞬間に外れが確定しないので、弾速を演出として自由に決められる）。

const HIT_RADIUS := 0.3
const MAX_LIFETIME := 4.0
## 敵の中心あたりを狙うための高さオフセット。
const TARGET_HEIGHT_OFFSET := 0.4

var _target: Node3D = null
## 撃ったタワーの TowerData。ダメージも追加効果もここから読む。
var _data: TowerData = null
var _speed: float = 18.0
var _life: float = MAX_LIFETIME


## 個別の数値ではなく TowerData ごと持たせる。効果が増えても引数を足さずに済み、
## 弾は「撃った側のデータどおりに当たる」だけの役割で保てる。
func launch(target: Node3D, tower_data: TowerData) -> void:
	_target = target
	_data = tower_data
	_speed = tower_data.projectile_speed


func _physics_process(delta: float) -> void:
	_life -= delta
	# ターゲットが先に倒れた場合は不発として消える。
	if _life <= 0.0 or _data == null or not is_instance_valid(_target):
		queue_free()
		return

	var aim := _target.global_position + Vector3.UP * TARGET_HEIGHT_OFFSET
	var to_target := aim - global_position
	var step := _speed * delta

	if to_target.length() <= maxf(step, HIT_RADIUS):
		_hit()
		queue_free()
		return

	global_position += to_target.normalized() * step


func _hit() -> void:
	Burst.spawn(self, global_position, Burst.Kind.HIT, _data.body_color)
	# 追加効果を先に入れる。take_damage で敵が撃破処理に入ると、
	# その後の apply_slow は無視されるため。
	if _data.effect == TowerData.Effect.SLOW and _target.has_method(&"apply_slow"):
		_target.apply_slow(_data.slow_factor, _data.slow_duration)
	if _target.has_method(&"take_damage"):
		_target.take_damage(_data.damage)
