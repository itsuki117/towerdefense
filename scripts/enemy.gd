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

@export var data: EnemyData

@onready var _visual: MeshInstance3D = $Visual

var _hp: int = 1
## 撃破・到達のどちらかで true。二重に signal を出さないためのガード。
var _finished: bool = false


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
	progress += data.speed * delta
	if progress_ratio >= 1.0:
		_finish(true)


func take_damage(amount: int) -> void:
	if _finished:
		return
	_hp -= amount
	if _hp <= 0:
		_finish(false)


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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.body_color
	_visual.set_surface_override_material(0, mat)
