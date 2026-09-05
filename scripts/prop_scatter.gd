extends MultiMeshInstance3D
## 岩・木・茂みを地形の上にばら撒く。
##
## 平らな面に光が一様に当たるのが「のっぺり」の正体なので、
## 影を落とす小物を散らして陰影の情報量を増やすのが狙い。
## MultiMesh なので何十個置いてもドローコールは 1 回。
##
## 道・設置マス・拠点の上には置かない（置くとプレイの邪魔になる）。
## 配置は seed 固定の乱数なので、起動するたびに同じ絵になる。

enum Kind {
	ROCK,  ## ごつごつした岩。
	TREE,  ## 幹＋円錐の葉。
	BUSH,  ## 岩を潰して緑にした低い茂み。
}

## どこに撒くか。
enum Region {
	PLATEAU,  ## 高台の上（プレイエリア）。道とマスを避ける。
	FIELD,  ## 高台の外の低地。遠景を埋める。
	ROADSIDE,  ## 道の脇。道の縁を石で縁取って、帯に見えないようにする。
}

@export var kind: Kind = Kind.ROCK
@export var region: Region = Region.PLATEAU
@export var count: int = 24
@export var rng_seed: int = 1
## 大きさのばらつき（最小倍率, 最大倍率）。
@export var scale_range := Vector2(0.7, 1.3)
## 小物どうしの最低距離。
@export var min_spacing: float = 1.4
## 道の中心線から空ける距離。
@export var path_clearance: float = 1.9
## ROADSIDE のとき、道の中心線からこの範囲（最小, 最大）に置く。
@export var road_band := Vector2(1.15, 1.6)
## ばら撒く範囲（中心からの距離）。0 なら region ごとの既定値を使う。
@export var spread: float = 0.0
## FIELD のとき、高台の輪郭からこれだけ離す。島の足元を空けて輪郭を見せる。
@export var field_margin: float = 1.5

@export_group("参照")
@export var terrain_path: NodePath = ^"../../Ground"
@export var level_path: NodePath = ^"../.."
## この位置の周りは空けておく（拠点クリスタルなど）。
@export var keep_out_points: Array[Vector3] = []
@export var keep_out_radius: float = 2.5

## 1 個置くのに何回まで場所を引き直すか。
const MAX_ATTEMPTS_PER_PROP := 30

var _rng := RandomNumberGenerator.new()
## 置いた小物の姿勢。タワーを建てたときに一部を取り除いて張り直すので持っておく。
var _placed: Array[Transform3D] = []


func _ready() -> void:
	add_to_group(&"prop_scatter")
	_rng.seed = rng_seed
	var terrain := get_node_or_null(terrain_path)
	if terrain == null or not terrain.has_method(&"height_at"):
		push_warning("PropScatter: terrain_path が Terrain を指していません")
		return

	for point in _pick_positions(terrain):
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * _rng.randf_range(scale_range.x, scale_range.y))
		_placed.append(Transform3D(basis, point))
	_refresh()


## タワーを建てた場所の小物をどける。
##
## 盤面がグリッドになって「どこにでも建つ」ようになったので、置ける場所から
## 小物を避けておくことができない（避けると高台から小物が消える）。
## 建てたときにその場を片付けるほうが、地面をならして建てたようにも見える。
func clear_around(center: Vector3, radius: float) -> void:
	var kept: Array[Transform3D] = []
	var flat := Vector2(center.x, center.z)
	for transform in _placed:
		if flat.distance_to(Vector2(transform.origin.x, transform.origin.z)) > radius:
			kept.append(transform)
	if kept.size() == _placed.size():
		return
	_placed = kept
	_refresh()


func _refresh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = multimesh.mesh if multimesh != null else _build_mesh()
	mm.instance_count = _placed.size()
	for i in _placed.size():
		mm.set_instance_transform(i, _placed[i])
	multimesh = mm


func _pick_positions(terrain: Node) -> Array[Vector3]:
	var road := _road_points()
	var half := spread if spread > 0.0 else (30.0 if region == Region.FIELD else 15.0)

	var placed: Array[Vector3] = []
	for _i in count:
		for _attempt in MAX_ATTEMPTS_PER_PROP:
			var x := _rng.randf_range(-half, half)
			var z := _rng.randf_range(-half, half)
			if not _is_allowed(terrain, road, placed, x, z):
				continue
			placed.append(Vector3(x, terrain.height_at(x, z), z))
			break
	return placed


func _is_allowed(
	terrain: Node, road: PackedVector2Array, placed: Array[Vector3], x: float, z: float
) -> bool:
	var distance: float = terrain.plateau_distance_at(x, z)
	if region == Region.FIELD:
		if distance < field_margin:
			return false
	elif distance > -1.2:
		# 崖の肩に生やすと宙に浮いて見えるので、少し内側に留める。
		return false

	var point := Vector2(x, z)
	for keep_out in keep_out_points:
		if point.distance_to(Vector2(keep_out.x, keep_out.z)) < keep_out_radius:
			return false
	for placed_point in placed:
		if point.distance_to(Vector2(placed_point.x, placed_point.z)) < min_spacing:
			return false
	if region == Region.FIELD:
		return true

	var nearest_road := INF
	for road_point in road:
		nearest_road = minf(nearest_road, point.distance_squared_to(road_point))
	nearest_road = sqrt(nearest_road)
	if region == Region.ROADSIDE:
		return nearest_road >= road_band.x and nearest_road <= road_band.y
	return nearest_road >= path_clearance


## 道の中心線を一定間隔で点にしたもの。距離判定はこの点との距離で足りる。
func _road_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var level := get_node_or_null(level_path)
	if level == null or not level.has_method(&"road_points"):
		return points
	for point in level.road_points(0.5):
		points.append(Vector2(point.x, point.z))
	return points


func _build_mesh() -> Mesh:
	match kind:
		Kind.TREE:
			return _build_tree()
		Kind.BUSH:
			return LowPoly.blob(Vector3(0.44, 0.3, 0.44), Color(0.19, 0.31, 0.18), 0.13)
		_:
			return LowPoly.blob(Vector3(0.42, 0.36, 0.42), Color(0.4, 0.38, 0.36), 0.15)


## 幹と葉を別サーフェスにした木。MultiMesh は複数サーフェスのメッシュも扱える。
func _build_tree() -> Mesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.15
	trunk.height = 0.9
	trunk.radial_segments = 5
	trunk.rings = 0

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	LowPoly.append_shape(st, trunk, Vector3(0.0, 0.45, 0.0), Color(0.29, 0.21, 0.16))
	st.generate_normals()
	st.set_material(LowPoly.vertex_color_material())
	var mesh := st.commit()

	# 葉は円錐を 3 段。上ほど小さくして、シルエットにギザギザを作る。
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaves.set_smooth_group(-1)
	var tiers := [
		[0.95, 1.0, 0.85, Color(0.20, 0.36, 0.21)],
		[0.75, 1.55, 0.75, Color(0.24, 0.42, 0.24)],
		[0.5, 2.05, 0.7, Color(0.28, 0.48, 0.26)],
	]
	for tier in tiers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = float(tier[0])
		cone.height = float(tier[2])
		cone.radial_segments = 6
		cone.rings = 0
		LowPoly.append_shape(leaves, cone, Vector3(0.0, float(tier[1]), 0.0), tier[3])
	leaves.generate_normals()
	leaves.set_material(LowPoly.vertex_color_material())
	return leaves.commit(mesh)
