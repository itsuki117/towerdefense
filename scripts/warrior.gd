class_name Warrior
extends Node3D
## クリスタルから出て道を遡り、敵を捉えたら足を止めて戦う自軍ユニット。
##
## **経路探索は要らない。** 道グラフを「ゴールから遠ざかる向き」に辿るだけ
## (RouteGraph.next_node_away)。行き先を選ぶ理由があるのは敵のほうで、
## 戦士は前へ出ていくだけなので、敵の A* をそのまま使い回さない。
##
## **道に居座ると、その道は敵に嫌われる。** 戦士は道の上に立つので、
## 立っている辺の経路コストを上げる（`WarriorData.threat_length`）。
## 分かれ道の片方に置けば流れをもう一方へ寄せられる——タワーにはできない仕事。
##
## **拠点から advance_limit までしか前に出ない。** 湧き口まで出て行かせると
## タワーの傘の外で戦うことになり、雇うほど弱くなる（検証で実測した）。
## 手前で止まれば、タワーの射程の中に敵を縛り付ける仕事になる。
##
## **役職の違いは block_capacity と attack_range で作る**（WarriorData）。
## 敵 1 体を掴めるのは 1 人だけなので、盾兵が 2 体を抱えている間は
## 衛兵がその 2 体に手を出せない。誰が誰を持つかが自然に分かれる。
## 掴まない役職（弓兵）は敵を素通りさせるが、そのぶん殴られもしない
## ——前列が崩れて敵とすれ違うまでは（Enemy._strike_passing）。
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
## 近接の一撃で体ごと前へ踏み込ませる量と時間。
## 「戦士が攻撃しているか分かりにくい」という指摘への対応
## ——ダメージは _fight() で即座に決着するので、ここは見た目だけの後付け。
const LUNGE_DISTANCE := 0.16
const LUNGE_TIME := 0.18
## 弓兵の矢が飛ぶ時間。当たり判定は持たず、見た目が追いつくだけの短い便宜。
const ARROW_TRAVEL_TIME := 0.12
const ARROW_SIZE := Vector3(0.05, 0.05, 0.45)

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
## これ以上前に出られない（湧き口まで来た、または前進の上限に達した）。
var _at_front: bool = false
## 拠点から道なりに進んだ距離。advance_limit と比べる。
var _advanced: float = 0.0
## 道の中心からの左右のずれ。同時に雇うと全員が同じ位置に重なるので、
## 個体ごとに散らして横並びに見せる。
var _side_offset: float = 0.0
## 今かかっている敵。1 体でも抱えていれば足を止める。
## 掴む役職なら block_capacity 体まで、掴まない役職なら狙っている 1 体。
var _targets: Array[Enemy] = []
var _attack_cooldown: float = 0.0
var _flash_remaining: float = 0.0
## 今コストを上乗せしている辺と、その量。倒れたら戻す。
var _threatened_edge: int = -1
var _threat_amount: float = 0.0
## 踏み込みアニメの進行中のもの。攻撃レートが速い役職で重ねて張ると
## 前のぶんが飛んで見た目が跳ねるので、張り直す前に必ず止める。
var _lunge_tween: Tween = null


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

	_drop_lost_targets()
	if _targets.size() < _wanted_targets():
		_look_for_targets()
	if not _targets.is_empty():
		_fight(delta)
		return
	if not _at_front:
		_advance(data.move_speed * delta)


## 今かかっている敵の数。検証ツールが役職の切り分けを数えるのに使う。
func held_count() -> int:
	return _targets.size()


## 足止めするか。しない役職（弓兵）は敵を掴まず、素通りさせる。
func blocks() -> bool:
	return data != null and data.block_capacity > 0


## 同時にかかれる敵の数。掴まない役職も狙いは 1 体持つ。
func _wanted_targets() -> int:
	return maxi(data.block_capacity, 1)


## 倒された・拠点へ抜けた相手をリストから外す。
func _drop_lost_targets() -> void:
	for i in range(_targets.size() - 1, -1, -1):
		if not is_instance_valid(_targets[i]):
			_targets.remove_at(i)


## 攻撃範囲に入った敵を、空いているぶんだけ捉える。
##
## 掴む役職は「まだ誰にも掴まれていない敵」だけを取る。掴まない役職は
## 掴み合いに参加しないので、すでに前列が抱えている敵でも狙ってよい
## （むしろ前列が抱えている敵を撃つのが仕事）。
func _look_for_targets() -> void:
	var candidates: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Enemy
		if enemy == null or _targets.has(enemy):
			continue
		if blocks() and not enemy.can_be_engaged():
			continue
		if global_position.distance_to(enemy.global_position) > data.attack_range:
			continue
		candidates.append(enemy)
	# 近い順に取る。遠くの敵を先に掴むと、目の前を素通りされて不自然に見える。
	candidates.sort_custom(_closer_to_me)

	var wanted := _wanted_targets()
	for enemy in candidates:
		if _targets.size() >= wanted:
			break
		if blocks() and not enemy.engage(self):
			continue
		_targets.append(enemy)

	if not _targets.is_empty():
		# 相手のほうを向く。止まって戦っているのが分かるように。
		_face(_targets[0].global_position)


func _closer_to_me(a: Enemy, b: Enemy) -> bool:
	return global_position.distance_squared_to(a.global_position) \
		< global_position.distance_squared_to(b.global_position)


## 抱えている中の 1 体だけを殴る。盾兵は 2 体を止めても倒す速さは変わらない
## ——止めるのが仕事で、倒すのは別の役職の仕事、という切り分けをここで作る。
func _fight(delta: float) -> void:
	_face(_targets[0].global_position)
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.0 / maxf(data.attack_rate, 0.01)
	var target := _targets[0]
	target.take_damage(attack_damage(target))
	_play_attack_vfx(target)


## 相手に与えるダメージ。**固定ぶん ＋ 相手の最大 HP の割合ぶん**に、武器強化を掛ける。
##
## 割合を混ぜているのは、波が進んで敵が硬くなっても戦士が置いていかれないようにするため。
## 固定ダメージだけだと、同じゴールドならタワーのほうが強い状態が最後まで直らなかった。
## 武器強化が倍率なのは、素のダメージが小さい役職ほど伸びを小さくするため
## （盾兵が強化で殲滅役になってしまわないように）。
func attack_damage(target: Enemy) -> int:
	var amount := float(data.damage)
	if data.damage_percent > 0.0 and target != null:
		amount += float(target.scaled_max_hp()) * data.damage_percent
	return maxi(roundi(amount * GameState.weapon_multiplier()), 1)


## 攻撃した瞬間の見せ方。ダメージ自体は take_damage() で即座に決着しているので、
## ここは「殴った／撃った」を目で追えるようにするだけの後付けの演出。
## 弓兵は距離があるので矢を飛ばし、近接は体ごと踏み込ませる。
func _play_attack_vfx(target: Enemy) -> void:
	var aim := target.global_position + Vector3.UP * (BODY_SIZE.y * 0.6)
	if data.gear == WarriorData.Gear.BOW:
		_spawn_arrow(global_position + Vector3.UP * (BODY_SIZE.y * 0.9), aim)
	else:
		_lunge()
	Burst.spawn(self, aim, Burst.Kind.HIT, data.gear_color)


## 見た目だけの矢。当たり判定は持たず、_fight() で確定済みの結果に追いつくだけ。
func _spawn_arrow(from: Vector3, to: Vector3) -> void:
	var container := get_tree().get_first_node_in_group(&"effect_container")
	if container == null:
		return
	var arrow := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = ARROW_SIZE
	arrow.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = data.gear_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.set_surface_override_material(0, material)
	container.add_child(arrow)
	arrow.global_position = from
	arrow.look_at(to, Vector3.UP)
	var tween := arrow.create_tween()
	tween.tween_property(arrow, ^"global_position", to, ARROW_TRAVEL_TIME)
	tween.finished.connect(arrow.queue_free)


## 近接の一撃で体ごと前へ小さく踏み込む。look_at で -Z が正面になっているので、
## _visual のローカル Z を前後させるだけで向きに関係なく前に出せる。
func _lunge() -> void:
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	_visual.position.z = 0.0
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(_visual, ^"position:z", -LUNGE_DISTANCE, LUNGE_TIME * 0.4) \
		.set_trans(Tween.TRANS_SINE)
	_lunge_tween.tween_property(_visual, ^"position:z", 0.0, LUNGE_TIME * 0.6)


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
	# 居座りをやめるので、上げていた経路コストを戻す。
	_clear_threat()
	# 掴んでいた敵を放してやらないと、その敵が永久に止まったままになる。
	if blocks():
		for enemy in _targets:
			if is_instance_valid(enemy):
				enemy.release()
	_targets.clear()
	Burst.spawn(self, global_position + Vector3.UP * BODY_SIZE.y, Burst.Kind.DEATH, data.body_color)
	Sfx.play(&"enemy_die", -6.0)
	died.emit()
	queue_free()


## 道の上を distance だけ進める。節に着いたらゴールと逆向きの隣へ乗り換える。
func _advance(distance: float) -> void:
	_advanced += distance
	if _advanced >= data.advance_limit:
		# タワーの傘の外まで出ない。前線はここまで。
		distance -= _advanced - data.advance_limit
		_advanced = data.advance_limit
		_at_front = true
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
	_clear_threat()
	_from_node = current
	_to_node = next
	_edge = edge
	_apply_threat()
	return true


## 今いる辺を「守られている」ことにする。敵の枝選びに効く。
func _apply_threat() -> void:
	if _threatened_edge >= 0 or _edge < 0 or data == null or data.threat_length <= 0.0:
		return
	# 辺より長くは守れない。短い辺に立ったときに効きすぎないようにする。
	_threat_amount = minf(data.threat_length, _graph.edge_length(_edge))
	_threatened_edge = _edge
	_graph.add_threat(_threatened_edge, _threat_amount)


func _clear_threat() -> void:
	if _threatened_edge < 0:
		return
	_graph.remove_threat(_threatened_edge, _threat_amount)
	_threatened_edge = -1
	_threat_amount = 0.0


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


## 胴と頭の 2 つの塊 ＋ 装備 1 つ。敵と同じ作り方なので見た目の質感が揃う。
##
## 見下ろしの引きでは顔も装備の細部も読めないので、**役職はシルエットで分ける**。
## 盾は横に広く、剣は斜めに、弓は体から上下へはみ出させてある。
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

	_visual.add_child(_build_gear())
	_visual.scale = Vector3.ONE * data.body_scale
	_refresh_color()


## 装備。look_at で -Z が正面になるので、前は -Z 側。
func _build_gear() -> MeshInstance3D:
	var gear := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = data.gear_color
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var box := BoxMesh.new()
	match data.gear:
		WarriorData.Gear.SHIELD:
			# 体より広い板を正面に構える。見下ろすと横に広い壁として読める。
			box.size = Vector3(0.62, 0.58, 0.09)
			gear.position = Vector3(0.0, 0.46, -0.3)
		WarriorData.Gear.BOW:
			# 縦に長い弓。**体の輪郭の外**へ出す。体に重ねると見下ろしでは
			# 頭の上に少し覗くだけになり、地面を背にしないと形が読めない。
			box.size = Vector3(0.1, 1.0, 0.1)
			gear.position = Vector3(0.44, 0.55, 0.0)
			gear.rotation.z = deg_to_rad(-20.0)
		_:
			# 剣。斜めに構えて、静止していても向きが読めるようにする。
			box.size = Vector3(0.1, 0.68, 0.1)
			gear.position = Vector3(0.28, 0.58, -0.1)
			gear.rotation.x = deg_to_rad(-32.0)
	gear.mesh = box
	gear.set_surface_override_material(0, material)
	return gear


func _refresh_color() -> void:
	if _material == null or data == null:
		return
	var color := data.body_color
	if _flash_remaining > 0.0:
		color = color.lerp(FLASH_COLOR, _flash_remaining / FLASH_TIME * FLASH_STRENGTH)
	_material.albedo_color = color
