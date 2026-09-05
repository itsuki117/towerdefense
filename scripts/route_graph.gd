class_name RouteGraph
extends RefCounted
## RouteData を走れる形にしたもの。分岐でどちらへ進むかを A* で決める。
##
## **辺のコストは動く。** タワーの射程に入っている区間はコストが上がるので、
## 敵は守りの薄い枝を通ろうとする。ゴールの位置も辺の長さも固定なのに
## コストまで固定だと、A* は毎回同じ答えを返して分岐を作った意味が無くなる。
##
## 節は多くても数十個なので、開集合は配列の線形探索で足りる
## （優先度付きキューを持ち込むほどの規模ではない）。
## そのかわり同じフレームで何度も呼ばれる（敵がまとまって節に着く）ので、
## コストが変わるまでは結果を使い回す。

## 1 単位ぶんの区間がタワーに守られているときに足すコスト。
## 大きいほど敵が守りを避けて回り道する。長さと同じ単位で効くので、
## 1.0 なら「守られた 1m は守られていない 2m と同じ重さ」になる。
const THREAT_WEIGHT := 1.0

## 分岐でどれだけ「安いほう」に寄せるか。
##
## **必ず最安の枝を選ぶと、分岐があっても全部の敵が同じ道を通ってしまう。**
## そこでコストが安い枝ほど選ばれやすい抽選にしている。
## 0 なら完全な五分五分、大きいほど安いほうへ集まる。
## 2.0 だと、コストが 2 倍違う枝へ行く敵は 1/4 になる。
const BRANCH_SHARPNESS := 2.0

var route: RouteData = null
var goal: int = 0

## 節番号 -> [[つながる節, 辺番号], ...]
var _adjacency: Dictionary = {}
## 辺ごとの長さと、タワーに守られているぶんの追加コスト。
var _lengths := PackedFloat32Array()
var _penalties := PackedFloat32Array()
## コストが変わるたびに増える。キャッシュを捨てる目印。
var _version: int = 0
## 節番号 -> [version, 次の節, ゴールまでのコスト, ゴールまでの距離]
var _cache: Dictionary = {}
## 分岐の抽選に使う乱数。**種を固定している。**
## 同じ配置なら同じ流れになるので、バランス検証を繰り返しても結果がぶれない。
var _rng := RandomNumberGenerator.new()


func _init(route_data: RouteData) -> void:
	_rng.seed = 20260905
	route = route_data
	if route == null:
		return
	goal = route.goal_node
	_lengths.resize(route.edges.size())
	_penalties.resize(route.edges.size())
	for i in route.edges.size():
		var edge := route.edges[i]
		_lengths[i] = route.nodes[edge.x].distance_to(route.nodes[edge.y])
		_penalties[i] = 0.0
		_adjacency.get_or_add(edge.x, []).append([edge.y, i])
		_adjacency.get_or_add(edge.y, []).append([edge.x, i])


func node_count() -> int:
	return route.nodes.size() if route != null else 0


func position_of(node: int) -> Vector3:
	return route.nodes[node] if _has(node) else Vector3.ZERO


func spawn_node() -> int:
	return route.spawn_node if route != null else 0


func edge_length(edge: int) -> float:
	return _lengths[edge] if edge >= 0 and edge < _lengths.size() else 0.0


## 経路探索に使う重み。長さ＋守られているぶん。
func edge_cost(edge: int) -> float:
	if edge < 0 or edge >= _lengths.size():
		return INF
	return _lengths[edge] + _penalties[edge]


## a と b をつなぐ辺の番号。つながっていなければ -1。
func edge_between(a: int, b: int) -> int:
	for link in _adjacency.get(a, []):
		if int(link[0]) == b:
			return int(link[1])
	return -1


## タワーが守っているぶんのコストを足す。タワーを建てるたびに呼ばれる。
func add_threat(edge: int, covered_length: float) -> void:
	if edge < 0 or edge >= _penalties.size() or covered_length <= 0.0:
		return
	_penalties[edge] += covered_length * THREAT_WEIGHT
	# コストが変わったので、貯めておいた経路は捨てる。
	_version += 1


## その辺のどれだけの長さが範囲に入っているか。タワー側から使う。
##
## 直線の区間を一定間隔で見て、範囲に入っている点の数を数えるだけにしている。
## 円と線分の交差を厳密に解いてもよいが、コストの重み付けに使うだけなので
## この精度で足りるし、辺が曲線になっても同じコードで通る。
func covered_length(edge: int, center: Vector3, radius: float, step: float = 0.5) -> float:
	if edge < 0 or edge >= _lengths.size():
		return 0.0
	var pair := route.edges[edge]
	var from := route.nodes[pair.x]
	var to := route.nodes[pair.y]
	var length := _lengths[edge]
	if length <= 0.0:
		return 0.0
	var covered := 0.0
	var distance := 0.0
	while distance <= length:
		var point := from.lerp(to, distance / length)
		if Vector2(point.x - center.x, point.z - center.z).length() <= radius:
			covered += step
		distance += step
	return minf(covered, length)


## from から次に進む節を選ぶ。previous には来た節を渡す（引き返さないため）。
##
## 分岐が無ければ道なりの節が返る。分岐があるときは、ゴールまでのコストが
## 安い枝ほど選ばれやすい抽選になる。**必ず最安を選ぶと全部の敵が同じ道を
## 通ってしまう**ので、守りの薄い枝に多く流しつつ、厚い枝にもいくらか流す。
func next_node(from: int, previous: int = -1) -> int:
	var links: Array = _adjacency.get(from, [])
	if links.is_empty():
		return goal

	# [節, その節を通ったときのゴールまでのコスト]
	var candidates: Array = []
	var cheapest := INF
	for link in links:
		var neighbour := int(link[0])
		# 来た道へは戻らない。ただし行き止まりなら戻るしかない。
		if neighbour == previous and links.size() > 1:
			continue
		var total: float = edge_cost(int(link[1])) + cost_to_goal(neighbour)
		if is_inf(total):
			continue
		candidates.append([neighbour, total])
		cheapest = minf(cheapest, total)

	if candidates.is_empty():
		return previous if previous >= 0 else goal
	if candidates.size() == 1:
		return int(candidates[0][0])
	return _pick_weighted(candidates, cheapest)


## from からゴールと逆向きに進む節を選ぶ。自軍の戦士が前線へ出ていくのに使う。
##
## 「ゴールまでのコストが今より大きくなる隣」を選べば道を遡れる。
## 候補が複数（分岐）あるときは等確率で選び、戦士が枝に散るようにする。
## 敵の抽選と違って寄せる理由が無い（守りの薄い側へ行きたいのは敵のほう）。
func next_node_away(from: int, previous: int = -1) -> int:
	var here := cost_to_goal(from)
	var candidates: Array = []
	for link in _adjacency.get(from, []):
		var neighbour := int(link[0])
		if neighbour == previous:
			continue
		if cost_to_goal(neighbour) > here:
			candidates.append(neighbour)
	if candidates.is_empty():
		return -1
	return int(candidates[_rng.randi_range(0, candidates.size() - 1)])


## コストが安い枝ほど重い抽選。重みは (最安 / その枝) ^ BRANCH_SHARPNESS。
##
## 比で見るので、道の長さが変わっても偏り方は変わらない。
## コストが同じなら重みも同じ＝五分五分になる。
func _pick_weighted(candidates: Array, cheapest: float) -> int:
	var weights := PackedFloat32Array()
	var total := 0.0
	for entry in candidates:
		var weight := pow(cheapest / maxf(float(entry[1]), 0.0001), BRANCH_SHARPNESS)
		weights.append(weight)
		total += weight

	var roll := _rng.randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return int(candidates[i][0])
	return int(candidates[candidates.size() - 1][0])


## その節からゴールまでの最小コスト。A* の結果で、抽選の重み付けに使う。
func cost_to_goal(from: int) -> float:
	return float(_search(from)[2])


## from からゴールまで、最安の経路の実際の長さ（コストではなく距離）。
##
## 抽選で別の枝へ行く敵もいるので厳密な残り距離ではないが、
## タワーが「ゴールに一番近い敵」を選ぶための優先度としてはこれで足りる。
func distance_to_goal(from: int) -> float:
	return float(_search(from)[3])


## A* で from からゴールまでの経路を求める。
## 戻り値は [version, 次の節, ゴールまでのコスト, ゴールまでの距離]。
func _search(from: int) -> Array:
	var cached: Array = _cache.get(from, [])
	if cached.size() == 4 and int(cached[0]) == _version:
		return cached

	var result := [_version, goal, 0.0, 0.0]
	if not _has(from) or from == goal:
		_cache[from] = result
		return result

	var came_from := {}
	var best_cost := {from: 0.0}
	# 開集合。節が数十個なので、最小値は線形に探せば足りる。
	var open := [from]
	var found := false
	while not open.is_empty():
		var current := _pop_best(open, best_cost)
		if current == goal:
			found = true
			break
		for link in _adjacency.get(current, []):
			var neighbour := int(link[0])
			var candidate: float = float(best_cost[current]) + edge_cost(int(link[1]))
			if candidate < float(best_cost.get(neighbour, INF)):
				best_cost[neighbour] = candidate
				came_from[neighbour] = current
				if not open.has(neighbour):
					open.append(neighbour)
	if not found:
		push_warning("RouteGraph: 節 %d からゴールへ行けません" % from)
		_cache[from] = result
		return result

	# ゴールから逆にたどって「次の 1 歩」と実距離を出す。
	var step := goal
	var distance := 0.0
	while came_from.has(step) and int(came_from[step]) != from:
		var previous := int(came_from[step])
		distance += edge_length(edge_between(previous, step))
		step = previous
	distance += edge_length(edge_between(from, step))

	result = [_version, step, float(best_cost[goal]), distance]
	_cache[from] = result
	return result


## 開集合から f 値（実コスト＋見積もり）が最小の節を取り出す。
##
## 見積もりはゴールまでの直線距離。辺のコストは「長さ＋0 以上の追加」なので
## 直線距離を下回ることはなく、A* が最短を取り逃がさない（許容的な見積もり）。
func _pop_best(open: Array, best_cost: Dictionary) -> int:
	var goal_position := position_of(goal)
	var best_index := 0
	var best_score := INF
	for i in open.size():
		var node := int(open[i])
		var score: float = float(best_cost.get(node, INF)) + position_of(node).distance_to(goal_position)
		if score < best_score:
			best_score = score
			best_index = i
	var picked := int(open[best_index])
	open.remove_at(best_index)
	return picked


## 道の中心線を一定間隔で点にしたもの。
## 地形を平らに均す判定と、小物を道から避ける判定に使う。
func sample_points(step: float = 0.6) -> PackedVector3Array:
	var points := PackedVector3Array()
	if route == null:
		return points
	for i in route.edges.size():
		var pair := route.edges[i]
		var from := route.nodes[pair.x]
		var to := route.nodes[pair.y]
		var length := _lengths[i]
		var distance := 0.0
		while distance <= length:
			points.append(from.lerp(to, distance / maxf(length, 0.0001)))
			distance += step
		points.append(to)
	return points


func _has(node: int) -> bool:
	return route != null and node >= 0 and node < route.nodes.size()
