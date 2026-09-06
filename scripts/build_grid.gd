class_name BuildGrid
extends RefCounted
## タワーを置ける盤面。ステージごとに、地形と道から「置けるマス」を割り出す。
##
## v1.0 は設置マスを手で 10 個置いていたが、置ける場所を決め打ちすると
## ステージを増やすたびに座標を用意することになる。地形（高台の内側か）と
## 道（近すぎず、離れすぎていないか）から機械的に出せば、
## 道を描くだけでマスが付いてくる。
##
## 置けるのは**道沿いの 1 マスぶん**だけ。高台じゅうに置けるようにすると、
## 射程の届かない奥にも建てられてしまい、盤面が広いだけで選ぶ楽しさにならない。
##
## マスに対応するノードは作らない。100 マス近くあるので Area3D を並べると
## 重くなるし、当たり判定も要らない（クリック位置は地面との交点から割り出す）。
## 見た目は BuildGridView が MultiMesh でまとめて描く。

## 1 マスの大きさ。タワーの土台（半径 0.8）が収まり、隣と干渉しない幅。
const CELL := 2.0
## 道の中心線から空ける距離。道の半幅 1.05 ＋ 土台 0.8 に余裕を足した値。
const ROAD_CLEARANCE := 2.0
## 道の中心線からここまでしか置けない。**道沿い 1 マスぶんだけ**にするための上限。
##
## マスの半分を足しているのは、道がマスの線に重なっているかどうかで
## 帯の幅が変わってしまうため。道がマスの中心線上にあるときは距離 2.0 の列だけ、
## 半マスずれているときは距離 3.0 の列だけが残り、どちらでも 1 列になる。
const ROAD_MAX_DISTANCE := ROAD_CLEARANCE + CELL * 0.5
## 高台の輪郭から内側へこれだけ入っていないと置けない。
## 崖の肩に建てると足元が斜面になって浮いて見える。
const PLATEAU_MARGIN := 1.8
## 拠点のまわりはクリスタルの見た目と重なるので空ける。
const BASE_CLEARANCE := 2.2

## 置けるマスの一覧。
var cells: Array[Vector2i] = []

## マス -> 建っているタワー。
var _towers: Dictionary = {}
## 置けるマスをすばやく引くための集合（cells と同じ中身）。
var _buildable: Dictionary = {}
## マスの中心の地面の高さ。地形は起伏があるので、置くときに使う。
var _heights: Dictionary = {}
## マスから道の中心線までの距離。近い順に並べるのに使う。
var _road_distance: Dictionary = {}


## 地形と道からマスを割り出す。
##
## terrain には plateau_distance_at() と height_at() を持つノード、
## graph にはその道グラフを渡す。
func _init(terrain: Node, graph: RouteGraph, extents: Vector2, center: Vector2) -> void:
	if terrain == null or graph == null:
		return
	var road := graph.sample_points(0.5)
	var goal := graph.position_of(graph.goal)

	var min_x := int(floor((center.x - extents.x) / CELL))
	var max_x := int(ceil((center.x + extents.x) / CELL))
	var min_z := int(floor((center.y - extents.y) / CELL))
	var max_z := int(ceil((center.y + extents.y) / CELL))

	for iz in range(min_z, max_z + 1):
		for ix in range(min_x, max_x + 1):
			var cell := Vector2i(ix, iz)
			var point := center_of(cell)
			if terrain.plateau_distance_at(point.x, point.z) > -PLATEAU_MARGIN:
				continue
			if Vector2(point.x - goal.x, point.z - goal.z).length() < BASE_CLEARANCE:
				continue
			# 道から離れたマスは置けない。射程の届かない奥に建てられても
			# 意味が無く、盤面が広いだけで選ぶ楽しさにならない。
			var road_distance := _distance_to_road(point, road)
			if road_distance < ROAD_CLEARANCE or road_distance > ROAD_MAX_DISTANCE:
				continue
			point.y = terrain.height_at(point.x, point.z)
			cells.append(cell)
			_buildable[cell] = true
			_heights[cell] = point.y
			_road_distance[cell] = road_distance

	# 道に近い順に並べておく。射程が届くマスから先に出てくるので、
	# 検証ツールが「上から順に建てる」だけでまともな配置になる。
	cells.sort_custom(func(a, b): return _road_distance[a] < _road_distance[b])


## マスの中心（ワールド座標）。y は置くときに _heights から入れ直す。
static func center_of(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * CELL, 0.0, float(cell.y) * CELL)


## ワールド座標がどのマスに入るか。
static func cell_at(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / CELL), roundi(point.z / CELL))


## タワーを置く位置。地形の高さに乗せる。
func placement_of(cell: Vector2i) -> Vector3:
	var point := center_of(cell)
	point.y = float(_heights.get(cell, 0.0))
	return point


func is_buildable(cell: Vector2i) -> bool:
	return _buildable.has(cell)


func is_occupied(cell: Vector2i) -> bool:
	return _towers.has(cell)


## 空いていて置けるマスか。
func is_free(cell: Vector2i) -> bool:
	return is_buildable(cell) and not is_occupied(cell)


func occupy(cell: Vector2i, tower: Node) -> void:
	_towers[cell] = tower


func tower_at(cell: Vector2i) -> Node:
	return _towers.get(cell)


## 空いているマスの一覧。検証ツールが順に建てるのに使う。
func free_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells:
		if not is_occupied(cell):
			result.append(cell)
	return result


## そのマスから道の中心線までの最短距離。
func _distance_to_road(point: Vector3, road: PackedVector3Array) -> float:
	var flat := Vector2(point.x, point.z)
	var nearest := INF
	for sample in road:
		nearest = minf(nearest, flat.distance_squared_to(Vector2(sample.x, sample.z)))
	return sqrt(nearest)


## そのマスから道までの距離。近いほど射程が道に届く。
func road_distance(cell: Vector2i) -> float:
	return float(_road_distance.get(cell, INF))
