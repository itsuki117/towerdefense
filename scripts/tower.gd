class_name Tower
extends Node3D
## 射程内の敵を自動で狙い撃つタワー。
##
## ターゲットは「ゴールに一番近い敵」＝ progress_ratio が最大の敵。
## 一番近い敵を狙うより漏れが減り、タワーディフェンスの定石でもある。

@export var data: TowerData
@export var projectile_scene: PackedScene

@onready var _turret: Node3D = $Turret
@onready var _muzzle: Marker3D = $Turret/Muzzle
@onready var _range_area: Area3D = $Range
@onready var _range_shape: CollisionShape3D = $Range/CollisionShape3D
@onready var _fire_timer: Timer = $FireTimer

var _current_target: Enemy = null


func _ready() -> void:
	if data == null:
		push_warning("Tower: TowerData が未設定です")
		set_physics_process(false)
		return

	# 射程は data 側の値が正。シーンの半径は編集時の目安でしかない。
	# シーンの SubResource はインスタンス間で共有されるので、必ず新しい形状を作る。
	var shape := SphereShape3D.new()
	shape.radius = data.attack_range
	_range_shape.shape = shape

	_fire_timer.wait_time = 1.0 / maxf(data.fire_rate, 0.01)
	_fire_timer.timeout.connect(_on_fire_timer_timeout)
	_fire_timer.start()

	_apply_visual()


func _physics_process(_delta: float) -> void:
	_current_target = _find_target()
	if _current_target != null:
		_aim_at(_current_target)


## 射程内で最もゴールに近い敵を返す。いなければ null。
func _find_target() -> Enemy:
	var best: Enemy = null
	var best_progress := -1.0
	for area in _range_area.get_overlapping_areas():
		var enemy := area.get_parent() as Enemy
		if enemy == null:
			continue
		var progress := enemy.get_goal_progress()
		if progress > best_progress:
			best_progress = progress
			best = enemy
	return best


func _aim_at(target: Enemy) -> void:
	# 砲身は水平に回すだけにして、上下の首振りはしない。
	var look_target := target.global_position
	look_target.y = _turret.global_position.y
	if _turret.global_position.distance_to(look_target) > 0.01:
		_turret.look_at(look_target, Vector3.UP)


func _on_fire_timer_timeout() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		return
	_shoot(_current_target)


func _shoot(target: Enemy) -> void:
	if projectile_scene == null:
		return
	var projectile := projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	_projectile_parent().add_child(projectile)
	projectile.global_position = _muzzle.global_position
	projectile.launch(target, data)


## 弾はタワーの子にしない（タワーが消えても飛んでいる弾が巻き込まれないように）。
func _projectile_parent() -> Node:
	var root := get_tree().current_scene
	var container := root.get_node_or_null(^"Projectiles")
	return container if container != null else root


func _apply_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.body_color
	($Turret/Head as MeshInstance3D).set_surface_override_material(0, mat)
