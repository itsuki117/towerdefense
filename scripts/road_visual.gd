extends MeshInstance3D
## 道グラフの辺ぜんぶを、地面に貼り付く土の道として 1 枚のメッシュにする。
##
## 以前は板を等間隔に並べていたが、カーブの曲がりで板が重なって
## 「灰色の帯」にしか見えなかった。断面をつないだリボンにすると、
## 幅を揺らしたり内側だけ色を変えたりできて、踏み固められた道に見える。
##
## 高さは地形から取り直して数 cm 浮かせている。地形の起伏に乗せないと、
## 土の道が地面に埋まったり浮いたりしてしまう。
## @tool にしていないのは、生成したメッシュがシーンに保存されて
## .tscn の差分が膨らむのを避けるため（実行時にだけ組み立てる）。

## 断面を取る間隔。細かいほど滑らかだが面数が増える。
@export var step: float = 0.7
## 道の基準の幅（中心から端まで）。
@export var half_width: float = 1.05
## 幅の揺らぎ。左右で独立に揺らして、直線に見えないようにする。
@export var width_variation: float = 0.22
## 地面からの浮かせ量。Z ファイティングを避ける最小限に留める。
@export var surface_offset: float = 0.035
@export var level_path: NodePath = ^".."
@export var terrain_path: NodePath = ^"../Ground"

@export_group("色")
## 踏み固められた中央。
@export var center_color := Color(0.53, 0.44, 0.32)
## 草に接する端。
@export var edge_color := Color(0.36, 0.29, 0.21)

## 断面の切り方。0.0 が中心、1.0 が端。
const CROSS_SECTION: Array[float] = [-1.0, -0.5, 0.0, 0.5, 1.0]
## 辺ごとに足す極小の高さ。分岐点では辺のリボンどうしが重なるので、
## 完全に同じ高さだとちらつく（Z ファイティング）。目に見えない差を付けて避ける。
const EDGE_STACKING := 0.0006

var _width_noise := FastNoiseLite.new()
var _shade_noise := FastNoiseLite.new()


func _ready() -> void:
	_build()


func _build() -> void:
	var level := get_node_or_null(level_path)
	if level == null or level.graph == null:
		push_warning("RoadVisual: level_path が道グラフを持つ Level を指していません")
		return
	_setup_noise()

	var graph: RouteGraph = level.graph
	var terrain := get_node_or_null(terrain_path)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 面ごとの法線にして、ローポリの地形と同じ質感に揃える。
	st.set_smooth_group(-1)
	for i in graph.route.edges.size():
		_add_edge(st, graph, i, terrain)

	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	st.set_material(material)
	mesh = st.commit()
	# 地面に貼り付いた薄い板なので、影を落とすと縁がちらつくだけ。
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 辺 1 本ぶんのリボンを張る。辺はまっすぐなので断面を等間隔に並べるだけ。
func _add_edge(st: SurfaceTool, graph: RouteGraph, edge: int, terrain: Node) -> void:
	var pair := graph.route.edges[edge]
	var from := graph.route.nodes[pair.x]
	var to := graph.route.nodes[pair.y]
	var length := graph.edge_length(edge)
	if length <= 0.001:
		return
	var forward := (to - from).normalized()
	var side := forward.cross(Vector3.UP)
	var lift := surface_offset + float(edge) * EDGE_STACKING

	# 辺の両端を道幅のぶんだけ伸ばす。伸ばさないと、直角に曲がる節の外側に
	# 三角形の欠けが残る（辺ごとに別のリボンを張っているため）。
	# 節では 2 本のリボンが重なるが、辺ごとの極小の高さ差でちらつきは出ない。
	var overhang := half_width
	var sections: Array = []
	var distance := -overhang
	var last := length + overhang
	while true:
		sections.append(_make_section(from + forward * distance, side, lift, terrain))
		if distance >= last:
			break
		distance = minf(distance + maxf(step, 0.1), last)

	for i in sections.size() - 1:
		var near: Array = sections[i]
		var far: Array = sections[i + 1]
		for span in CROSS_SECTION.size() - 1:
			_add_quad(st, near[span], near[span + 1], far[span + 1], far[span])


## 1 か所の断面。CROSS_SECTION と同じ数の「位置と色」を返す。
func _make_section(center: Vector3, side: Vector3, lift: float, terrain: Node) -> Array:
	# 左右で別の位相のノイズを使い、幅を独立に揺らす。
	var left := half_width + _width_noise.get_noise_2d(center.x, center.z) * width_variation
	var right := half_width + _width_noise.get_noise_2d(center.x + 50.0, center.z) * width_variation

	var section: Array = []
	for offset in CROSS_SECTION:
		var width := left if offset < 0.0 else right
		var point := center + side * (offset * width)
		point.y = _ground_height(terrain, point) + lift
		# 端ほど暗く、中央ほど明るい。踏み固められた跡に見せるため。
		var edge_ratio := absf(offset)
		var color := center_color.lerp(edge_color, edge_ratio * edge_ratio)
		var shade := _shade_noise.get_noise_2d(point.x, point.z) * 0.06
		section.append([point, color.lightened(shade) if shade > 0.0 else color.darkened(-shade)])
	return section


func _add_quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	# 上から見て表になる向きに並べる（逆だと裏面カリングで消える）。
	for entry in [a, c, b, a, d, c]:
		st.set_color(entry[1])
		st.add_vertex(entry[0])


func _ground_height(terrain: Node, point: Vector3) -> float:
	if terrain != null and terrain.has_method(&"height_at"):
		return terrain.height_at(point.x, point.z)
	return 0.0


func _setup_noise() -> void:
	_width_noise.seed = 71
	_width_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_width_noise.frequency = 0.35

	_shade_noise.seed = 88
	_shade_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_shade_noise.frequency = 0.6
