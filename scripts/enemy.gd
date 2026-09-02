class_name Enemy
extends PathFollow3D
## 固定ルートを進む敵。
##
## ルート追従は Path3D + PathFollow3D に任せ、このスクリプトは progress を進めるだけ。
## v1.0 では経路探索を行わない（GDD の Non-Goals）。
## 生成側 (WaveManager) が Path3D の直下に add_child すること。

## 撃破された。引数は獲得ゴールド。
signal died(gold_value: int)
## 拠点に到達した。引数はライフ減少量。
signal reached_end(damage: int)

## 減速中の体色。元の色にこの色を混ぜて、効いていることを見て分かるようにする。
const SLOW_TINT := Color(0.45, 0.75, 1.0)
const SLOW_TINT_STRENGTH := 0.55

@export var data: EnemyData

@onready var _visual: MeshInstance3D = $Visual

var _hp: int = 1
## 撃破・到達のどちらかで true。二重に signal を出さないためのガード。
var _finished: bool = false
var _material: StandardMaterial3D = null
## 現在の速度倍率。1.0 で等速。
var _slow_factor: float = 1.0
var _slow_remaining: float = 0.0


func _ready() -> void:
	add_to_group(&"enemy")
	# 終点でループさせず、progress_ratio を 1.0 で止める。
	loop = false
	rotation_mode = PathFollow3D.ROTATION_Y

	if data == null:
		push_warning("Enemy: EnemyData が未設定です")
		return
	_hp = data.max_hp
	_apply_visual()


func _physics_process(delta: float) -> void:
	if _finished or data == null:
		return
	_update_slow(delta)
	progress += data.speed * _slow_factor * delta
	if progress_ratio >= 1.0:
		_finish(true)


func take_damage(amount: int) -> void:
	if _finished:
		return
	_hp -= amount
	if _hp <= 0:
		_finish(false)


## 減速を受ける。より強い減速が優先され、同じ強さなら持続時間だけが伸びる。
## （弱い減速で強い減速を上書きしてしまわないようにする）
func apply_slow(factor: float, duration: float) -> void:
	if _finished:
		return
	if factor > _slow_factor:
		return
	_slow_factor = clampf(factor, 0.05, 1.0)
	_slow_remaining = maxf(_slow_remaining, duration)
	_refresh_color()


func _update_slow(delta: float) -> void:
	if _slow_remaining <= 0.0:
		return
	_slow_remaining -= delta
	if _slow_remaining <= 0.0:
		_slow_factor = 1.0
		_refresh_color()


## ゴールへの近さ (0.0〜1.0)。タワーのターゲット選択に使う。
func get_goal_progress() -> float:
	return progress_ratio


func _finish(reached_goal: bool) -> void:
	_finished = true
	remove_from_group(&"enemy")
	if data == null:
		queue_free()
		return
	if reached_goal:
		reached_end.emit(data.damage)
	else:
		died.emit(data.gold_value)
	queue_free()


func _apply_visual() -> void:
	_visual.scale = Vector3.ONE * data.body_scale
	# 敵ごとに色を変えるので、マテリアルはインスタンスごとに作る。
	_material = StandardMaterial3D.new()
	_visual.set_surface_override_material(0, _material)
	_refresh_color()


func _refresh_color() -> void:
	if _material == null or data == null:
		return
	if _slow_factor < 1.0:
		_material.albedo_color = data.body_color.lerp(SLOW_TINT, SLOW_TINT_STRENGTH)
	else:
		_material.albedo_color = data.body_color
