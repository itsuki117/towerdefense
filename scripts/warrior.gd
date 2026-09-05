class_name Warrior
extends Node3D
## クリスタルから出て道を遡り、敵とぶつかったら足を止めて戦う自軍ユニット。
##
## **経路探索は要らない。** 道グラフを「ゴールから遠ざかる向き」に辿るだけ
## (RouteGraph.next_node_away)。行き先を選ぶ理由があるのは敵のほうで、
## 戦士は前へ出ていくだけなので、敵の A* をそのまま使い回さない。
##
## **1 人が足止めできる敵は 1 体。** 手が空いている戦士がいなければ敵は素通りする。
## この規則だと「何人出したか」がそのまま止められる数になり、
## 画面を見ただけで何が起きているか分かる。
##
## 生成側 (WarriorManager) が setup() でグラフと種別を渡してから add_child すること。

## 倒れた。雇い直しの判断は WarriorManager 側でする。
signal died

const BODY_SIZE := Vector3(0.3, 0.44, 0.3)
## 道の中心から左右へ散らす幅。道の半幅より内側に収める。
const SIDE_SPREAD := 0.55
const HEAD_SIZE := Vector3(0.2, 0.18, 0.2)
## 被弾したときに一瞬混ぜる色と、その持続時間。敵と同じ見せ方に揃える。
const FLASH_COLOR := Color(1.0, 0.96, 0.85)
const FLASH_TIME := 0.13
const FLASH_STRENGTH := 0.8

@export var data: WarriorData

@onready var _visual: Node3D = $Visual

var _graph: RouteGraph = null
var _hp: int = 1
var _finished: bool = false
var _material: StandardMaterial3D = null
## 今いる辺（_from_node から _to_node へ）と、その辺をどれだけ進んだか。
var _from_node: int = 0
var _to_node: int = 0
var _edge: int = -1
var _travelled: float = 0.0
## これ以上前に出られない（湧き口まで来た）。
var _at_front: bool = false
## 道の中心からの左右のずれ。同時に雇うと全員が同じ位置に重なるので、
## 個体ごとに散らして横並びに見せる。
var _side_offset: float = 0.0
## 足止めしている敵。null なら前進中。
var _target: Enemy = null
var _attack_cooldown: float = 0.0
var _flash_remaining: float = 0.0


## グラフと種別を渡す。add_child より前に呼ぶこと。
func setup(graph: RouteGraph, warrior_data: WarriorData) -> void:
	_graph = graph
	data = warrior_data


func _ready() -> void:
	add_to_group(&"warrior")
	if data == null or _graph == null:
		push_warning("Warrior: setup() でデータとグラフを渡してください")
		set_physics_process(false)
		return
	_hp = data.max_hp
	_side_offset = randf_range(-SIDE_SPREAD, SIDE_SPREAD)
	_build_visual()
	# 拠点（＝敵のゴール）から出て、道を遡っていく。
	_start_at(_graph.goal)


func _physics_process(delta: float) -> void:
	if _finished or data == null:
		return
	_update_flash(delta)

	if _target != null and not is_instance_valid(_target):
		# 相手が倒れた。また前へ出る。
		_target = null
	if _target == null:
		_look_for_target()
	if _target != null:
		_fight(delta)
		return
	if not _at_front:
		_advance(data.move_speed * delta)


## 射程ならぬ足止め範囲に入った、まだ誰にも止められていない敵を掴む。
func _look_for_target() -> void:
	var best: Enemy = null
	var best_distance := data.engage_radius
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.can_be_engaged():
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	if best != null and best.engage(self):
		_target = best
		# 掴んだ相手のほうを向く。止まって殴り合っているのが分かるように。
		_face(best.global_position)


func _fight(delta: float) -> void:
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.0 / maxf(data.attack_rate, 0.01)
	_target.take_damage(data.damage)


func take_damage(amount: int) -> void:
	if _finished:
		return
	_flash_remaining = FLASH_TIME
	_refresh_color()
	_hp -= amount
	if _hp <= 0:
		_fall()


func _fall() -> void:
	_finished = true
	remove_from_group(&"warrior")
	if _target != null and is_instance_valid(_target):
		# 掴んでいた敵を放してやらないと、その敵が永久に止まったままになる。
		_target.release()
	Burst.spawn(self, global_position + Vector3.UP * BODY_SIZE.y, Burst.Kind.DEATH, data.body_color)
	Sfx.play(&"enemy_die", -6.0)
	died.emit()
	queue_free()


## 道の上を distance だけ進める。節に着いたらゴールと逆向きの隣へ乗り換える。
func _advance(distance: float) -> void:
	_travelled += distance
	var length := _graph.edge_length(_edge)
	while _travelled >= length:
		_travelled -= length
		var next := _graph.next_node_away(_to_node, _from_node)
		if next < 0:
			# 湧き口まで来た。ここで敵を待つ。
			_travelled = length
			_at_front = true
			break
		_step_to(next)
		length = _graph.edge_length(_edge)
	_place_on_edge(length)


func _start_at(node: int) -> void:
	_from_node = node
	_edge = -1
	_travelled = 0.0
	var next := _graph.next_node_away(node)
	if next < 0 or not _step_to(next):
		_at_front = true
		position = _graph.position_of(node)
		return
	_place_on_edge(_graph.edge_length(_edge))


func _step_to(next: int) -> bool:
	var current := _to_node if _edge >= 0 else _from_node
	var edge := _graph.edge_between(current, next)
	if edge < 0:
		return false
	_from_node = current
	_to_node = next
	_edge = edge
	return true


func _place_on_edge(length: float) -> void:
	var from := _graph.position_of(_from_node)
	var to := _graph.position_of(_to_node)
	var center := from.lerp(to, clampf(_travelled / maxf(length, 0.0001), 0.0, 1.0))
	var forward := to - from
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		center += forward.normalized().cross(Vector3.UP) * _side_offset
	position = center
	_face(to)


func _face(target: Vector3) -> void:
	var forward := target - position
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		look_at(position + forward, Vector3.UP)


func _update_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining = maxf(_flash_remaining - delta, 0.0)
	_refresh_color()


## 胴と頭の 2 つの塊で作る。敵と同じ作り方なので見た目の質感が揃う。
func _build_visual() -> void:
	_material = LowPoly.vertex_color_material()

	var body := MeshInstance3D.new()
	body.mesh = LowPoly.blob(BODY_SIZE, Color.WHITE, 0.08)
	body.set_surface_override_material(0, _material)
	_visual.add_child(body)

	var head := MeshInstance3D.new()
	head.mesh = LowPoly.blob(HEAD_SIZE, Color.WHITE, 0.06, 13.0)
	head.position.y = BODY_SIZE.y * 1.7
	head.set_surface_override_material(0, _material)
	_visual.add_child(head)

	_refresh_color()


func _refresh_color() -> void:
	if _material == null or data == null:
		return
	var color := data.body_color
	if _flash_remaining > 0.0:
		color = color.lerp(FLASH_COLOR, _flash_remaining / FLASH_TIME * FLASH_STRENGTH)
	_material.albedo_color = color
