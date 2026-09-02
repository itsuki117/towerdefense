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
var _damage: int = 0
var _speed: float = 18.0
var _life: float = MAX_LIFETIME


func launch(target: Node3D, damage: int, speed: float) -> void:
	_target = target
	_damage = damage
	_speed = speed


func _physics_process(delta: float) -> void:
	_life -= delta
	# ターゲットが先に倒れた場合は不発として消える。
	if _life <= 0.0 or not is_instance_valid(_target):
		queue_free()
		return

	var aim := _target.global_position + Vector3.UP * TARGET_HEIGHT_OFFSET
	var to_target := aim - global_position
	var step := _speed * delta

	if to_target.length() <= maxf(step, HIT_RADIUS):
		if _target.has_method(&"take_damage"):
			_target.take_damage(_damage)
		queue_free()
		return

	global_position += to_target.normalized() * step
