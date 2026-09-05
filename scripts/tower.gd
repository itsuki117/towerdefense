class_name Tower
extends Node3D
## 射程内の敵を自動で狙い撃つタワー。
##
## ターゲットは「ゴールに一番近い敵」＝ progress_ratio が最大の敵。
## 一番近い敵を狙うより漏れが減り、タワーディフェンスの定石でもある。

## クリック判定を乗せる物理レイヤー（4 番 = tower）。カメラがこれを撃つ。
const CLICK_LAYER := 8
## クリック判定の大きさ。タワーの土台から砲塔までをざっくり覆う。
const CLICK_RADIUS := 0.75
const CLICK_HEIGHT := 1.7
## 足元に敷く石の土台。
const PAD_SIZE := Vector3(0.82, 0.16, 0.82)
const PAD_COLOR := Color(0.34, 0.32, 0.3)

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
	_add_click_area()
	_add_ground_pad()


func _physics_process(_delta: float) -> void:
	_current_target = _find_target()
	if _current_target != null:
		_aim_at(_current_target)


## 射程内で最もゴールに近い敵を返す。いなければ null。
##
## 分岐があると「どれだけ進んだか」では順位が付かないので、
## A* が選んだ経路の残り距離で比べる（小さいほどゴールに近い）。
func _find_target() -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for area in _range_area.get_overlapping_areas():
		var enemy := area.get_parent() as Enemy
		if enemy == null:
			continue
		var distance := enemy.get_distance_to_goal()
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## 自分が守っている区間を道グラフに教える。
##
## 設置してから呼ぶこと。_ready の時点ではまだ BuildManager が位置を入れておらず、
## global_position が原点のままなので、どの区間を守っているか計算できない。
func register_threat() -> void:
	if data == null:
		return
	var level := Level.find(self)
	if level == null or level.graph == null:
		return
	var graph := level.graph
	for edge in graph.route.edges.size():
		var covered := graph.covered_length(edge, global_position, data.attack_range)
		if covered > 0.0:
			graph.add_threat(edge, covered)


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

	# 砲身の前方 = Muzzle の -Z。砲塔を look_at で回しているのでそのまま使える。
	var forward := -_muzzle.global_transform.basis.z
	Burst.spawn(self, _muzzle.global_position, Burst.Kind.MUZZLE, data.body_color, forward)
	Sfx.play(data.shoot_sfx, -10.0)


## 弾はタワーの子にしない（タワーが消えても飛んでいる弾が巻き込まれないように）。
##
## 置き場所はグループで探す。current_scene やツリーの形に依存させると、
## シーンを別の形で読み込んだときに黙って壊れる。
func _projectile_parent() -> Node:
	var container := get_tree().get_first_node_in_group(&"projectile_container")
	return container if container != null else get_parent()


## 足元の石の土台。
##
## グリッドに置くようになって、地面の起伏の上に直接建つようになった。
## 土台を敷くと足元の傾きが目立たなくなり、置いた場所も読み取りやすい。
func _add_ground_pad() -> void:
	var pad := MeshInstance3D.new()
	pad.name = "GroundPad"
	pad.mesh = LowPoly.blob(PAD_SIZE, PAD_COLOR, 0.12)
	pad.position.y = -PAD_SIZE.y * 0.5
	# 傾いた地面に少し埋まるので、影は落とさないほうが締まって見える。
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)


## カメラが「どのタワーがクリックされたか」を知るための当たり判定。
##
## タワーのシーンは 3 つあるので、それぞれに置くより実行時に足すほうが
## 形も大きさも 1 か所で決まる。当たるのはカメラのレイだけ
## （collision_mask = 0 なので、このエリア自身は何も検知しない）。
func _add_click_area() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = CLICK_RADIUS
	shape.height = CLICK_HEIGHT

	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = CLICK_HEIGHT * 0.5

	var area := Area3D.new()
	area.name = "ClickArea"
	area.collision_layer = CLICK_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.add_child(collision)
	add_child(area)


## 専用モデルを持つタワーはモデル側のマテリアルをそのまま使うので何もしない。
## プリミティブ表示のタワー（Turret/Head がある）だけ TowerData の色で塗る。
func _apply_visual() -> void:
	var head := get_node_or_null(^"Turret/Head") as MeshInstance3D
	if head == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.body_color
	head.set_surface_override_material(0, mat)
