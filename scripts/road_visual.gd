extends MeshInstance3D
## 親の Path3D のカーブに沿って、地面に貼り付く土の道を 1 枚のメッシュで作る。
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
@export var terrain_path: NodePath = ^"../../Ground"

@export_group("色")
## 踏み固められた中央。
@export var center_color := Color(0.53, 0.44, 0.32)
## 草に接する端。
@export var edge_color := Color(0.36, 0.29, 0.21)

## 断面の切り方。0.0 が中心、1.0 が端。
const CROSS_SECTION: Array[float] = [-1.0, -0.5, 0.0, 0.5, 1.0]

var _width_noise := FastNoiseLite.new()
var _shade_noise := FastNoiseLite.new()


func _ready() -> void:
	_build()


func _build() -> void:
	var path := get_parent() as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		push_warning("RoadVisual: 親が Path3D でないか、カーブが未設定です")
		return
	_setup_noise()

	var terrain := get_node_or_null(terrain_path)
	var curve := path.curve
	var total_length := curve.get_baked_length()
	var sections: Array = []
	var distance := 0.0
	while true:
		sections.append(_make_section(curve, minf(distance, total_length), terrain))
		if distance >= total_length:
			break
		distance = minf(distance + maxf(step, 0.1), total_length)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 面ごとの法線にして、ローポリの地形と同じ質感に揃える。
	st.set_smooth_group(-1)
	for i in sections.size() - 1:
		var near: Array = sections[i]
		var far: Array = sections[i + 1]
		for span in CROSS_SECTION.size() - 1:
			_add_quad(st, near[span], near[span + 1], far[span + 1], far[span])

	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	st.set_material(material)
	mesh = st.commit()
	# 地面に貼り付いた薄い板なので、影を落とすと縁がちらつくだけ。
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 1 か所の断面。CROSS_SECTION と同じ数の「位置と色」を返す。
func _make_section(curve: Curve3D, distance: float, terrain: Node) -> Array:
	var center := curve.sample_baked(distance)
	var ahead := curve.sample_baked(minf(distance + 0.2, curve.get_baked_length()))
	var forward := ahead - center
	forward.y = 0.0
	if forward.length() < 0.0001:
		forward = Vector3.FORWARD
	var side := forward.normalized().cross(Vector3.UP)

	# 左右で別の位相のノイズを使い、幅を独立に揺らす。
	var left := half_width + _width_noise.get_noise_2d(distance, 0.0) * width_variation
	var right := half_width + _width_noise.get_noise_2d(distance, 50.0) * width_variation

	var section: Array = []
	for offset in CROSS_SECTION:
		var width := left if offset < 0.0 else right
		var point := center + side * (offset * width)
		point.y = _ground_height(terrain, point) + surface_offset
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
