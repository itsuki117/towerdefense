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


func _init(route_data: RouteData) -> void:
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


## from から次に進むべき節。分岐が無ければ道なりの節が返る。
func next_node(from: int) -> int:
	return int(_search(from)[1])


## from からゴールまで、選ばれた経路の実際の長さ（コストではなく距離）。
## タワーが「ゴールに一番近い敵」を選ぶのに使う。
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
