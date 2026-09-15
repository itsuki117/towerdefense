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
## 倒されて分裂する。**湧かせるのは WaveManager の仕事**
## （敵シーンを持っているのはあちらで、敵自身は自分の増やし方を知らない）。
signal split(child_data: EnemyData, count: int, source: Enemy)

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

## 足止めされている敵が受けるダメージの割り増し。
const HELD_DAMAGE_BONUS := 0.5

## 装甲の帯を体より何倍太くするか、体の高さの何割にするか。
const ARMOR_SHELL_SCALE := 1.22
const ARMOR_SHELL_HEIGHT := 0.6

## HP 倍率を体の大きさへ何割ぶん効かせるか。
## 硬い敵がまったく同じ見た目だと、なぜ倒せないのか分からない。
## 効かせすぎると道からはみ出すので、上限も置く。
const HP_SIZE_GAIN := 0.09
const HP_SIZE_LIMIT := 1.35
## HP 倍率ぶん体色を暗くする上限。
const HP_DARKEN_LIMIT := 0.35

## 体の大きさ（半径）。EnemyData.body_scale がこれに掛かる。
const BODY_SIZE := Vector3(0.42, 0.36, 0.42)
## 跳ねる速さと、つぶれ具合。止まって見えないようにするための演出。
const HOP_SPEED := 5.0
const HOP_HEIGHT := 0.1
const SQUASH := 0.12

@export var data: EnemyData

@onready var _visual: MeshInstance3D = $Visual

var _hp: int = 1
## 硬さ (hp_scale) を掛けたあとの最大 HP。戦士の割合ダメージが参照する。
var _max_hp: int = 1
## 撃破・到達のどちらかで true。二重に signal を出さないためのガード。
var _finished: bool = false
var _material: StandardMaterial3D = null
## 波ごとの HP 倍率。見た目にも少しだけ効かせる（硬い敵は大きく・暗く）。
var _hp_scale: float = 1.0
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
##
## hp_scale は波ごとの HP 倍率（WaveEntry）。同じ敵種のまま歯応えだけを上げる。
func setup(graph: RouteGraph, enemy_data: EnemyData, hp_scale: float = 1.0) -> void:
	_graph = graph
	data = enemy_data
	_hp_scale = maxf(hp_scale, 0.1)


func _ready() -> void:
	add_to_group(&"enemy")
	if data == null or _graph == null:
		push_warning("Enemy: setup() でデータとグラフを渡してください")
		set_physics_process(false)
		return
	_max_hp = maxi(roundi(float(data.max_hp) * _hp_scale), 1)
	_hp = _max_hp
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


## 今どの辺のどこにいるか。分裂した子に同じ場所を引き継がせるために使う。
func path_state() -> Dictionary:
	return {"from": _from_node, "to": _to_node, "edge": _edge, "travelled": _travelled}


## path_state() で取った位置から歩き出す。**add_child のあとに呼ぶこと**
## （_ready が湧き口から始めてしまうので、そのあとで上書きする）。
##
## side は道の中心からの左右のずれ。同時に分かれた子が重なって 1 体に見えないよう、
## 呼ぶ側が散らして渡す。
func resume_at(state: Dictionary, side: float) -> void:
	if _graph == null or _finished:
		return
	_from_node = state.get("from", _from_node)
	_to_node = state.get("to", _to_node)
	_edge = state.get("edge", _edge)
	_travelled = state.get("travelled", _travelled)
	if _edge < 0:
		return
	_place_on_edge(_graph.edge_length(_edge))
	# 道に沿った横ずれ。進む向きの真横へ寄せる。
	var forward := _graph.position_of(_to_node) - _graph.position_of(_from_node)
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		position += forward.normalized().cross(Vector3.UP) * side


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


## 今の装甲。硬さ (hp_scale) に平方根で連れて上がる。
## 硬さと同じ倍率で上げると、後半は弱い弾が 1 ダメージ固定になって何も通らなくなる。
func _armor() -> int:
	if data == null or data.armor <= 0:
		return 0
	return maxi(roundi(float(data.armor) * sqrt(_hp_scale)), 1)


## 戦士に与えるダメージ。硬さ (hp_scale) に**平方根で**連れて上がる。
##
## 上げないと、後半は倒せないだけで殴られもしない敵になり、
## 戦士が不死身の足止め装置になってしまう。かといって硬さと同じ倍率で上げると、
## 後半の戦士が一瞬で溶けて雇う意味が消える。その中間を取っている。
func _melee_damage() -> int:
	return maxi(roundi(float(data.melee_damage) * sqrt(_hp_scale)), 1)


## 手が空いている（まだ誰にも止められていない）か。
func can_be_engaged() -> bool:
	return not _finished and _blocker == null


## 波ごとの硬さを掛けたあとの最大 HP。
func scaled_max_hp() -> int:
	return _max_hp


## この敵に掛かっている波ごとの硬さ。分裂した子へ引き継ぐために使う。
func hp_scale() -> float:
	return _hp_scale


## 今、戦士に足止めされているか。タワーの狙いを決めるのに使う。
func is_blocked() -> bool:
	return _blocker != null and is_instance_valid(_blocker)


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
	_blocker.call(&"take_damage", _melee_damage())


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
	nearest.call(&"take_damage", _melee_damage())


func take_damage(amount: int) -> void:
	if _finished:
		return
	# 足止めされている敵は的が大きい。戦士の仕事を「自分で倒す」ではなく
	# **タワーに倒させる**に寄せるための割り増し。同じゴールドならタワーのほうが
	# 強い状態が続いていたので、戦士がタワーの火力を増やす形にした。
	if is_blocked():
		amount = maxi(roundi(float(amount) * (1.0 + HELD_DAMAGE_BONUS)), 1)
	# 装甲は**割り増しのあと**に引く。的が大きいことと硬いことは別の話なので、
	# 順番を逆にすると装甲のぶんまで割り増しが乗ってしまう。
	amount = maxi(amount - _armor(), 1)
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
	var size := _size_scale()
	_visual.position.y = BODY_SIZE.y + lift * HOP_HEIGHT * size
	_visual.scale = Vector3(squash, stretch, squash) * size


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
		# 分裂は**倒されたときだけ**。通り抜けた敵まで増えると際限が無くなる。
		# queue_free より前に流すので、受け手はまだこの敵の位置を読める。
		if data.split_into != null and data.split_count > 0:
			split.emit(data.split_into, data.split_count, self)
		died.emit(data.gold_value)
	queue_free()


func _apply_visual() -> void:
	# 球のままだと表面がのっぺりするので、面を粗く割った塊にする。
	# 色は頂点カラーではなく albedo_color 側で掛けて、メッシュは色違いで使い回す。
	_visual.mesh = LowPoly.blob(BODY_SIZE, Color.WHITE, 0.1)
	_visual.position.y = BODY_SIZE.y
	_visual.scale = Vector3.ONE * _size_scale()
	# 敵ごとに色を変えるので、マテリアルはインスタンスごとに作る。
	_material = LowPoly.vertex_color_material()
	_visual.set_surface_override_material(0, _material)
	_add_armor_shell()
	_refresh_color()


## 装甲持ちにかぶせる殻。**硬い敵は見た目でも硬く**しないと、
## なぜ弾が通らないのか分からない。体より一回り大きい塊を重ねるだけ。
func _add_armor_shell() -> void:
	if data.armor <= 0:
		return
	var shell := MeshInstance3D.new()
	shell.name = "ArmorShell"
	# 体をすっぽり覆うのではなく、**腰まわりの帯**にする。全部覆うと元の体色が
	# 見えなくなって敵種が分からなくなるし、上に乗せると帽子に見えた。
	shell.mesh = LowPoly.blob(
		Vector3(BODY_SIZE.x * ARMOR_SHELL_SCALE, BODY_SIZE.y * ARMOR_SHELL_HEIGHT,
			BODY_SIZE.z * ARMOR_SHELL_SCALE),
		Color.WHITE, 0.16, 7.0
	)
	# 体と同じ原点。_visual の squash がそのまま殻にも掛かる。
	var material := LowPoly.vertex_color_material()
	material.albedo_color = data.armor_color
	shell.set_surface_override_material(0, material)
	_visual.add_child(shell)


## HP 倍率ぶん大きくした体の倍率。
func _size_scale() -> float:
	return data.body_scale * minf(1.0 + (_hp_scale - 1.0) * HP_SIZE_GAIN, HP_SIZE_LIMIT)


func _refresh_color() -> void:
	if _material == null or data == null:
		return
	# 硬い敵は暗く沈ませる。数値を出さずに「これは固い」を伝えるため。
	var color := data.body_color.darkened(
		minf((_hp_scale - 1.0) * 0.12, HP_DARKEN_LIMIT)
	)
	if _slow_factor < 1.0:
		color = color.lerp(SLOW_TINT, SLOW_TINT_STRENGTH)
	# フラッシュは減速の色にも上書きで乗せる。当たった事実のほうを優先して見せる。
	if _flash_remaining > 0.0:
		color = color.lerp(FLASH_COLOR, _flash_remaining / FLASH_TIME * FLASH_STRENGTH)
	_material.albedo_color = color
