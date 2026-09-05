class_name Enemy
extends Node3D
## 道グラフを辿ってクリスタルを目指す敵。
##
## v1.0 では Path3D + PathFollow3D に乗せていたが、道が分岐を持つグラフに
## なったので自前で辺を渡り歩く。**節に着くたびに A* でゴールまでの経路を出し、
## 次に進む辺を選ぶ**（RouteGraph）。タワーに守られた区間はコストが高いので、
## 守りの薄い枝があればそちらへ回る。
##
## 自軍の戦士に掴まれると足を止めて殴り合う。**掴めるのは 1 体につき 1 人**で、
## 手が空いている戦士がいなければ素通りする。ただし素通りするときも、
## すぐ横にいる戦士は歩きながら殴る（_strike_passing）。これが無いと
## 足止めしない役職＝弓兵が一切傷つかず、前列を用意する理由が無くなる。
##
## 生成側 (WaveManager) が setup() でグラフと種別を渡してから add_child すること。

## 撃破された。引数は獲得ゴールド。
signal died(gold_value: int)
## 拠点に到達した。引数はライフ減少量。
signal reached_end(damage: int)

## 減速中の体色。元の色にこの色を混ぜて、効いていることを見て分かるようにする。
const SLOW_TINT := Color(0.45, 0.75, 1.0)
const SLOW_TINT_STRENGTH := 0.55

## 被弾したときに一瞬混ぜる色と、その持続時間。
## 弾が当たったことを、HP バーを出さずに分からせるための表現。
const FLASH_COLOR := Color(1.0, 0.96, 0.85)
const FLASH_TIME := 0.13
## 真っ白まで飛ばすと元の色が分からなくなるので、混ぜる上限を決める。
const FLASH_STRENGTH := 0.8

## 素通りするときに戦士へ手が届く距離。掴む距離より短くして、
## 「本当にすれ違ったとき」だけ当たるようにする。
const PASSING_REACH := 0.85

## 体の大きさ（半径）。EnemyData.body_scale がこれに掛かる。
const BODY_SIZE := Vector3(0.42, 0.36, 0.42)
## 跳ねる速さと、つぶれ具合。止まって見えないようにするための演出。
const HOP_SPEED := 5.0
const HOP_HEIGHT := 0.1
const SQUASH := 0.12

@export var data: EnemyData

@onready var _visual: MeshInstance3D = $Visual

var _hp: int = 1
## 撃破・到達のどちらかで true。二重に signal を出さないためのガード。
var _finished: bool = false
var _material: StandardMaterial3D = null
## 現在の速度倍率。1.0 で等速。
var _slow_factor: float = 1.0
var _slow_remaining: float = 0.0
## 跳ねる演出用の時間。個体ごとにずらして、群れが同時に跳ねないようにする。
var _hop_time: float = 0.0
## 被弾フラッシュの残り時間。
var _flash_remaining: float = 0.0

var _graph: RouteGraph = null
## 今いる辺（_from_node から _to_node へ）と、その辺をどれだけ進んだか。
var _from_node: int = 0
var _to_node: int = 0
var _edge: int = -1
var _travelled: float = 0.0
## 足止めしてきた戦士。null なら前進中。
var _blocker: Node = null
var _attack_cooldown: float = 0.0


## グラフと種別を渡す。add_child より前に呼ぶこと。
func setup(graph: RouteGraph, enemy_data: EnemyData) -> void:
	_graph = graph
	data = enemy_data


func _ready() -> void:
	add_to_group(&"enemy")
	if data == null or _graph == null:
		push_warning("Enemy: setup() でデータとグラフを渡してください")
		set_physics_process(false)
		return
	_hp = data.max_hp
	_hop_time = randf() * TAU
	_start_at(_graph.spawn_node())
	_apply_visual()


func _physics_process(delta: float) -> void:
	if _finished or data == null:
		return
	_update_slow(delta)
	_update_hop(delta)
	_update_flash(delta)

	# 掴まれている間は進まない。相手が倒れたら勝手に解ける。
	if _blocker != null and not is_instance_valid(_blocker):
		_blocker = null
	if _blocker != null:
		_fight(delta)
		return
	_strike_passing(delta)
	_advance(data.speed * _slow_factor * delta)


## 道の上を distance だけ進める。節をまたぐときは A* で次の辺を選ぶ。
func _advance(distance: float) -> void:
	_travelled += distance
	var length := _graph.edge_length(_edge)
	# 1 フレームで節を 2 つ以上またぐこともあるので while で回す。
	while _travelled >= length:
		_travelled -= length
		if _to_node == _graph.goal:
			_finish(true)
			return
		if not _step_to(_graph.next_node(_to_node, _from_node)):
			_finish(true)
			return
		length = _graph.edge_length(_edge)
	_place_on_edge(length)


func _start_at(node: int) -> void:
	_from_node = node
	_edge = -1
	_travelled = 0.0
	if not _step_to(_graph.next_node(node)):
		# 進む先が無い＝グラフが壊れている。到達扱いにして片付ける。
		_finish(true)
		return
	_place_on_edge(_graph.edge_length(_edge))


## 今いる節から next へ、辺を 1 本ぶん乗り換える。つながっていなければ false。
func _step_to(next: int) -> bool:
	# まだ辺に乗っていない（湧いた直後）なら _from_node が今いる節。
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
	position = from.lerp(to, clampf(_travelled / maxf(length, 0.0001), 0.0, 1.0))
	var forward := to - from
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		# 進む向きへ体を向ける。PathFollow3D の rotation_mode の代わり。
		look_at(position + forward, Vector3.UP)


## 手が空いている（まだ誰にも止められていない）か。
func can_be_engaged() -> bool:
	return not _finished and _blocker == null


## 戦士が足止めを始める。すでに掴まれていたら false。
func engage(warrior: Node) -> bool:
	if not can_be_engaged():
		return false
	_blocker = warrior
	return true


## 掴んでいた戦士が倒れたときに呼ばれる。また歩き出す。
func release() -> void:
	_blocker = null


func _fight(delta: float) -> void:
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.0 / maxf(data.attack_rate, 0.01)
	_blocker.call(&"take_damage", data.melee_damage)


## 止められていないときに、すぐ横の戦士を歩きながら殴る。
## 足は止めない——止めてしまうと足止めしない役職が足止め役になってしまう。
func _strike_passing(delta: float) -> void:
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	var nearest: Node3D = null
	var nearest_distance := PASSING_REACH
	for node in get_tree().get_nodes_in_group(&"warrior"):
		var warrior := node as Node3D
		if warrior == null:
			continue
		var distance := global_position.distance_to(warrior.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = warrior
	if nearest == null:
		# 空振りに冷却を使わない。次のフレームでまた探す。
		_attack_cooldown = 0.0
		return
	_attack_cooldown = 1.0 / maxf(data.attack_rate, 0.01)
	nearest.call(&"take_damage", data.melee_damage)


func take_damage(amount: int) -> void:
	if _finished:
		return
	_flash_remaining = FLASH_TIME
	_refresh_color()
	Sfx.play(&"hit", -7.0)
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


## ゴールまでの残り距離。タワーのターゲット選択に使う（小さいほど優先）。
##
## v1.0 では PathFollow3D の progress_ratio を使っていたが、分岐があると
## 「どれだけ進んだか」では順位が付かない。A* が選んだ経路の残り距離なら、
## どの枝を通っていても同じものさしで比べられる。
func get_distance_to_goal() -> float:
	if _graph == null:
		return INF
	return _graph.distance_to_goal(_to_node) + maxf(_graph.edge_length(_edge) - _travelled, 0.0)


## 被弾フラッシュを時間で戻す。
func _update_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining = maxf(_flash_remaining - delta, 0.0)
	_refresh_color()


func _update_slow(delta: float) -> void:
	if _slow_remaining <= 0.0:
		return
	_slow_remaining -= delta
	if _slow_remaining <= 0.0:
		_slow_factor = 1.0
		_refresh_color()


## 遅くなるほど跳ねる間隔も伸びる。減速が効いていることが動きでも分かる。
func _update_hop(delta: float) -> void:
	_hop_time += delta * HOP_SPEED * _slow_factor
	var lift := absf(sin(_hop_time))
	var squash := 1.0 - lift * SQUASH
	var stretch := 1.0 + lift * SQUASH
	_visual.position.y = BODY_SIZE.y + lift * HOP_HEIGHT * data.body_scale
	_visual.scale = Vector3(squash, stretch, squash) * data.body_scale


func _finish(reached_goal: bool) -> void:
	_finished = true
	remove_from_group(&"enemy")
	# 掴まれたまま消えると、戦士が倒した相手を待ち続けてしまう。
	_blocker = null
	if data == null:
		queue_free()
		return
	if reached_goal:
		Sfx.play(&"life_lost")
		reached_end.emit(data.damage)
	else:
		# エフェクトは自分の子にしない。queue_free で巻き込まれてしまう。
		Burst.spawn(self, _visual.global_position, Burst.Kind.DEATH, data.body_color)
		Sfx.play(&"enemy_die", -4.0)
		died.emit(data.gold_value)
	queue_free()


func _apply_visual() -> void:
	# 球のままだと表面がのっぺりするので、面を粗く割った塊にする。
	# 色は頂点カラーではなく albedo_color 側で掛けて、メッシュは色違いで使い回す。
	_visual.mesh = LowPoly.blob(BODY_SIZE, Color.WHITE, 0.1)
	_visual.position.y = BODY_SIZE.y
	_visual.scale = Vector3.ONE * data.body_scale
	# 敵ごとに色を変えるので、マテリアルはインスタンスごとに作る。
	_material = LowPoly.vertex_color_material()
	_visual.set_surface_override_material(0, _material)
	_refresh_color()


func _refresh_color() -> void:
	if _material == null or data == null:
		return
	var color := data.body_color
	if _slow_factor < 1.0:
		color = color.lerp(SLOW_TINT, SLOW_TINT_STRENGTH)
	# フラッシュは減速の色にも上書きで乗せる。当たった事実のほうを優先して見せる。
	if _flash_remaining > 0.0:
		color = color.lerp(FLASH_COLOR, _flash_remaining / FLASH_TIME * FLASH_STRENGTH)
	_material.albedo_color = color
