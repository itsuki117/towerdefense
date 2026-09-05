@tool
extends MeshInstance3D
## 遊べる高台（プラトー）・崖・低地・遠景の山までを 1 枚のメッシュで作る地形。
##
## 板 1 枚の地面は光が一様に当たるのでどうしてものっぺりする。
## 面を割って高さと頂点カラーを揺らし、フラットシェーディングで面ごとに
## 明るさが変わるようにすることで、テクスチャ無しのまま陰影を作る。
##
## 格子は等間隔ではなく、中心ほど細かく外ほど粗くしている。
## 見下ろしカメラだと地面は 70 単位ほど先まで映るので、そこまで等間隔で
## 割ると面数が跳ね上がる。並び自体は普通の格子のままなので、隣の面と
## 頂点を共有でき、隙間（クラック）は開かない。
##
## 高台の上面はほぼ平ら（±top_relief）に保つ。道もタワーも y=0 前提で
## 置かれているので、ここを大きく波打たせるとゲーム側が壊れる。

## 生成するマップ全体の一辺（ワールド単位）。
@export var world_size: float = 150.0
## 格子の分割数。面数はこの 2 乗に比例する。
@export var grid_steps: int = 96
## 外側ほどマスを粗くする強さ。1.0 で等間隔、大きいほど細かさが中心に寄る。
@export var falloff_power: float = 2.4
## 等間隔ぶんの割合。0 にすると中心のマスが潰れるので少し混ぜておく。
@export var falloff_linear: float = 0.5
## 高台の中心。プレイエリアの真ん中に合わせる。
@export var plateau_center := Vector2(-1.0, 1.0)
## 高台の広さ（中心からの距離）。
@export var plateau_extents := Vector2(13.5, 12.5)
## 高台の角の丸み。
@export var plateau_corner: float = 5.0
## 崖の幅。ここで高台から低地まで落ちる。
@export var cliff_width: float = 2.4
## 低地までの落差。
@export var cliff_depth: float = 5.0
## 高台の上面の起伏。ゲームに影響しない範囲に留める。
@export var top_relief: float = 0.22
## 低地の丘の高さ。
@export var field_relief: float = 1.3
## 格子に見えないように頂点を横方向へずらす量（マスの大きさに対する割合）。
@export var jitter: float = 0.22

@export_group("遠景の山")
## 高台の輪郭からこれだけ離れたところから山が立ち上がる。
@export var mountain_start: float = 22.0
## 立ち上がりきるまでの距離。
@export var mountain_ramp: float = 32.0
## 山の高さ。
@export var mountain_height: float = 11.5
## この高さから上に雪を乗せる。
@export var snow_line: float = 6.0

@export_group("平らに均す場所")
## 道の周りは起伏を消す。道は地面に貼り付く板なので、下が波打っていると
## 埋まったり浮いたりして見える。
## タワーはマスごとに地面の高さへ乗せるので、均す必要は無い。
@export var flatten_radius: float = 1.9
## 均した所から起伏に戻るまでの幅。
@export var flatten_falloff: float = 1.8
@export var level_path: NodePath = ^".."

@export_group("色")
@export var grass_color := Color(0.18, 0.29, 0.17)
@export var grass_color_alt := Color(0.35, 0.48, 0.25)
@export var rock_color := Color(0.42, 0.39, 0.34)
@export var field_color := Color(0.16, 0.26, 0.22)
## 遠景の山肌。
@export var mountain_rock_color := Color(0.4, 0.43, 0.42)
## 山頂の雪。
@export var snow_color := Color(0.87, 0.91, 0.95)

@export_group("遠景のかすみ")
## Environment のフォグは近くにも掛かってしまい、遊ぶ高台まで白ませてしまう。
## そこで遠景ぶんの空気遠近は地形の頂点カラーに焼き込む。
## 高台の上（distance <= 0）には掛からないので、プレイエリアは澄んだまま。
## かすみ始める距離（高台の輪郭から）。
@export var haze_begin: float = 14.0
## 完全にかすむ距離。
@export var haze_end: float = 55.0
@export var haze_color := Color(0.63, 0.71, 0.8)
## かすみの最大の強さ。1.0 で完全に haze_color になる。
@export var haze_strength: float = 0.72
## 草地に混ぜる乾いた土の色。
@export var dry_color := Color(0.47, 0.42, 0.26)

## 再生成ボタン代わり。エディタでチェックすると作り直す。
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		_rebuild()

var _height_noise := FastNoiseLite.new()
## 高台の上面だけに掛ける細かい起伏。面ごとの陰影を作るのが目的。
var _top_noise := FastNoiseLite.new()
var _edge_noise := FastNoiseLite.new()
var _color_noise := FastNoiseLite.new()
## 遠景の山の稜線。
var _mountain_noise := FastNoiseLite.new()
## 平らに均す中心点（道の中心線＋設置マス）を XZ 平面で持つ。
var _flatten_points := PackedVector2Array()


func _init() -> void:
	_setup_noise()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_setup_noise()
	_collect_flatten_points()

	var steps := maxi(grid_steps, 8)
	var axis := _build_axis(steps)
	# 先に格子の頂点を決めてから三角形を張る。隣り合う面が同じ頂点を
	# 共有しないと、ずらした分だけ隙間（クラック）が開いてしまう。
	var points: Array[Vector3] = []
	var colors: Array[Color] = []
	points.resize((steps + 1) * (steps + 1))
	colors.resize((steps + 1) * (steps + 1))
	for iz in steps + 1:
		for ix in steps + 1:
			var x := axis[ix]
			var z := axis[iz]
			# 外周は動かさない。動かすとマップの縁がギザギザに欠ける。
			var on_border := ix == 0 or iz == 0 or ix == steps or iz == steps
			if not on_border:
				# ずらす量はその場所のマスの大きさに比例させる。
				# 中心の細かいマスで大きくずらすと面が裏返ってしまう。
				var gap := minf(axis[ix + 1] - axis[ix], axis[iz + 1] - axis[iz])
				x += _jitter_at(ix, iz, 0.0) * jitter * gap
				z += _jitter_at(ix, iz, 37.0) * jitter * gap
			var index := iz * (steps + 1) + ix
			points[index] = Vector3(x, _height_at(x, z), z)
			colors[index] = _color_at(x, z, points[index].y)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# スムーズグループを切って面ごとの法線にする（ローポリのファセット表現）。
	st.set_smooth_group(-1)
	for iz in steps:
		for ix in steps:
			var i00 := iz * (steps + 1) + ix
			var i10 := i00 + 1
			var i01 := i00 + steps + 1
			var i11 := i01 + 1
			_add_triangle(st, points, colors, i00, i11, i01)
			_add_triangle(st, points, colors, i00, i10, i11)
	st.generate_normals()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	st.set_material(material)
	mesh = st.commit()


func _add_triangle(
	st: SurfaceTool, points: Array[Vector3], colors: Array[Color], a: int, b: int, c: int
) -> void:
	for index in [a, b, c]:
		st.set_color(colors[index])
		st.add_vertex(points[index])


func _setup_noise() -> void:
	_height_noise.seed = 1337
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_height_noise.frequency = 0.06

	_top_noise.seed = 4242
	_top_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_top_noise.frequency = 0.5

	_edge_noise.seed = 24
	_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_edge_noise.frequency = 0.045

	_color_noise.seed = 909
	_color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_color_noise.frequency = 0.12

	_mountain_noise.seed = 5150
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_mountain_noise.frequency = 0.042


## 高台の輪郭（角丸の長方形）からの符号付き距離。負なら高台の上。
func _plateau_distance(x: float, z: float) -> float:
	var local := Vector2(x, z) - plateau_center
	var q := Vector2(
		absf(local.x) - plateau_extents.x + plateau_corner,
		absf(local.y) - plateau_extents.y + plateau_corner
	)
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var distance := outside + minf(maxf(q.x, q.y), 0.0) - plateau_corner
	# 輪郭そのものを揺らして、角丸長方形だと分からないようにする。
	return distance + _edge_noise.get_noise_2d(x, z) * 1.6


func _height_at(x: float, z: float) -> float:
	var distance := _plateau_distance(x, z)
	if distance <= 0.0:
		return _top_height(x, z)

	var hills := _height_noise.get_noise_2d(x * 0.8, z * 0.8) * field_relief
	var ground := -cliff_depth + hills + _mountain_at(x, z, distance)
	var t := clampf(distance / maxf(cliff_width, 0.01), 0.0, 1.0)
	# 崖から離れきったところは高台の高さを出す必要がない。
	# 平坦化の距離判定が重いので、必要な範囲だけで回す。
	if t >= 1.0:
		return ground
	# 崖はイーズを掛けて、上端で肩・下端で裾が付くようにする。
	var eased := t * t * (3.0 - 2.0 * t)
	return lerpf(_top_height(x, z), ground, eased)


## 高台の上面の高さ。道と設置マスの周りは平らに均す。
func _top_height(x: float, z: float) -> float:
	return _top_noise.get_noise_2d(x, z) * top_relief * (1.0 - _flatten_weight(x, z))


## 遠景の山の高さ。高台から離れるほど高くなる。
func _mountain_at(x: float, z: float, distance: float) -> float:
	if distance <= mountain_start:
		return 0.0
	var ramp := clampf((distance - mountain_start) / maxf(mountain_ramp, 0.01), 0.0, 1.0)
	ramp = ramp * ramp * (3.0 - 2.0 * ramp)
	# ノイズの絶対値を反転すると、丸い丘ではなく尖った稜線になる。
	var ridge := 1.0 - absf(_mountain_noise.get_noise_2d(x, z))
	ridge = pow(ridge, 2.4)
	# 稜線だけだと同じ高さの山が並ぶので、大きなうねりで高低差を付ける。
	var broad := _mountain_noise.get_noise_2d(x * 0.3, z * 0.3) * 0.5 + 0.5
	return ramp * mountain_height * ridge * (0.35 + broad * 0.9)


func _color_at(x: float, z: float, height: float) -> Color:
	var distance := _plateau_distance(x, z)
	# 大きなむらと細かいむらを重ねる。1 種類だけだと均一な水玉模様に見える。
	var tint := _color_noise.get_noise_2d(x, z) * 0.42 + _color_noise.get_noise_2d(x * 3.4, z * 3.4) * 0.12
	tint = clampf(tint + 0.5, 0.0, 1.0)
	if distance <= 0.0:
		var grass := grass_color.lerp(grass_color_alt, tint)
		# 明るいほうへ振り切ったところだけ乾いた土色を混ぜ、平面の単調さを崩す。
		return grass.lerp(dry_color, clampf((tint - 0.66) * 2.2, 0.0, 1.0))
	var t := clampf(distance / maxf(cliff_width, 0.01), 0.0, 1.0)
	# 崖の途中は岩、下りきったら低地の草に戻す。
	var slope := 1.0 - absf(t * 2.0 - 1.0)
	var base := grass_color.lerp(field_color, t)
	var color := base.lerp(rock_color, minf(slope * 1.4, 1.0))
	color = color.lerp(Color.BLACK, maxf(-height, 0.0) * 0.02)
	# 低地より高いところは山。高さで岩肌 → 雪へ移す。
	var above_field := height + cliff_depth
	if above_field > 3.0:
		# 裾は草のまま残す。全部を岩色にすると遠景がガレ場に見えてしまう。
		color = color.lerp(mountain_rock_color, clampf((above_field - 3.0) / 8.0, 0.0, 1.0))
		color = color.lerp(snow_color, clampf((height - snow_line) / 3.5, 0.0, 1.0))
	# 遠いほど空気の色に寄せる。2 乗して、手前は掛からないようにする。
	var haze := clampf((distance - haze_begin) / maxf(haze_end - haze_begin, 0.01), 0.0, 1.0)
	return color.lerp(haze_color, haze * haze * haze_strength)


## 格子の 1 軸ぶんの座標。中心を細かく、外を粗くした並びを返す。
func _build_axis(steps: int) -> PackedFloat32Array:
	var axis := PackedFloat32Array()
	axis.resize(steps + 1)
	var half := world_size * 0.5
	for i in steps + 1:
		var u := float(i) / float(steps) * 2.0 - 1.0
		var a := absf(u)
		var shaped := falloff_linear * a + (1.0 - falloff_linear) * pow(a, falloff_power)
		axis[i] = signf(u) * shaped * half
	return axis


## 格子番号から決まる -1〜1 の値。毎回同じ結果になるので隙間が開かない。
func _jitter_at(ix: int, iz: int, salt: float) -> float:
	var value := sin(float(ix) * 12.9898 + float(iz) * 78.233 + salt) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0


## 道の中心線を集める。均す判定はこの点との距離だけで足りる。
func _collect_flatten_points() -> void:
	_flatten_points = PackedVector2Array()
	# エディタでは Level（@tool ではない）のメソッドを呼べず、そもそも走らせる
	# ステージも決まっていない。道を均さない素の島として見せる。
	if Engine.is_editor_hint():
		return
	var level := get_node_or_null(level_path)
	if level != null and level.has_method(&"road_points"):
		for point in level.road_points():
			_flatten_points.append(Vector2(point.x, point.z))


## 1.0 なら完全に平ら、0.0 なら起伏そのまま。
func _flatten_weight(x: float, z: float) -> float:
	var point := Vector2(x, z)
	var nearest := INF
	for center in _flatten_points:
		nearest = minf(nearest, point.distance_squared_to(center))
		if nearest <= flatten_radius * flatten_radius:
			return 1.0
	nearest = sqrt(nearest)
	var t := clampf((nearest - flatten_radius) / maxf(flatten_falloff, 0.01), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)


## 指定した位置の地面の高さ。小物を置くスクリプトから使う。
func height_at(x: float, z: float) -> float:
	if _flatten_points.is_empty():
		_collect_flatten_points()
	return _height_at(x, z)


## 高台の輪郭からの距離。負なら高台の上。
func plateau_distance_at(x: float, z: float) -> float:
	return _plateau_distance(x, z)
