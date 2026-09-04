extends Node3D
## 守る対象のクリスタル。台座・結晶・明かりをまとめて手続きで組み立てる。
##
## 円錐 1 本だと「とりあえず置いた三角」に見えてしまうので、
## 面を不揃いに割った結晶を大小 3 本立てて、岩の台座に生やしている。
## ゆっくり回して上下させることで、止まった画面でもここだけ動いて目を引く。

## 結晶の本数（1 本目が主役、以降は脇の小さい結晶）。
@export var shard_count: int = 4
@export var main_height: float = 2.3
@export var main_radius: float = 0.5
## 回転の速さ（ラジアン毎秒）。
@export var spin_speed: float = 0.4
## 上下に揺れる幅と速さ。
@export var bob_height: float = 0.07
@export var bob_speed: float = 1.3
@export var terrain_path: NodePath = ^"../Ground"

@export_group("色")
@export var tip_color := Color(0.62, 0.92, 1.0)
@export var base_color := Color(0.08, 0.26, 0.6)
@export var plinth_color := Color(0.29, 0.28, 0.27)

## 結晶を並べる角度と大きさ（角度, 中心からの距離, 大きさの倍率, 傾き）。
const SHARD_LAYOUT: Array = [
	[0.0, 0.0, 1.0, 0.0],
	[1.9, 0.82, 0.58, 0.26],
	[4.3, 0.9, 0.44, -0.3],
	[3.1, 0.72, 0.3, 0.18],
]

var _shards: Node3D = null
var _shard_base_y: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	var ground_y := _ground_height()
	_build_plinth(ground_y)

	_shards = Node3D.new()
	_shards.name = "Shards"
	_shard_base_y = ground_y + 0.42
	_shards.position.y = _shard_base_y
	add_child(_shards)
	_build_shards()

	var light := OmniLight3D.new()
	light.name = "Glow"
	light.position = Vector3(0.0, ground_y + 1.1, 0.0)
	light.light_color = Color(0.6, 0.86, 1.0)
	light.light_energy = 1.0
	light.omni_range = 5.5
	light.shadow_enabled = false
	add_child(light)


func _process(delta: float) -> void:
	if _shards == null:
		return
	_time += delta
	_shards.rotation.y += spin_speed * delta
	_shards.position.y = _shard_base_y + sin(_time * bob_speed) * bob_height


func _build_shards() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 面ごとの法線にしないと結晶のカットが出ない。
	st.set_smooth_group(-1)
	for i in mini(shard_count, SHARD_LAYOUT.size()):
		var layout: Array = SHARD_LAYOUT[i]
		var angle := float(layout[0])
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * float(layout[1])
		var basis := Basis(Vector3(cos(angle + PI * 0.5), 0.0, sin(angle + PI * 0.5)), float(layout[3]))
		_add_shard(st, Transform3D(basis, offset), float(layout[2]), i)
	st.generate_normals()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.metallic = 0.15
	material.roughness = 0.18
	material.emission_enabled = true
	material.emission = Color(0.36, 0.78, 1.0)
	# グロー（Environment 側）が拾う明るさ。ここだけ画面で光って見える。
	material.emission_energy_multiplier = 0.7

	var shard := MeshInstance3D.new()
	shard.name = "Shard"
	shard.mesh = st.commit()
	shard.material_override = material
	_shards.add_child(shard)


## 結晶 1 本。下の尖り・腰・肩・先端の 4 段で、面を不揃いに割る。
func _add_shard(st: SurfaceTool, placement: Transform3D, scale_factor: float, salt: int) -> void:
	var sides := 6
	var height := main_height * scale_factor
	var radius := main_radius * scale_factor

	var waist: Array[Vector3] = []
	var shoulder: Array[Vector3] = []
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		# 半径を辺ごとにずらして、正六角形に見えないようにする。
		var wobble := 0.86 + _hash(float(i) + float(salt) * 7.0) * 0.24
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		waist.append(direction * radius * wobble + Vector3.UP * height * 0.24)
		shoulder.append(direction * radius * wobble * 0.62 + Vector3.UP * height * 0.7)
	var bottom := Vector3.DOWN * height * 0.2
	var apex := Vector3.UP * height

	for i in sides:
		var next := (i + 1) % sides
		_add_face(st, placement, height, [bottom, waist[next], waist[i]])
		_add_face(st, placement, height, [waist[i], waist[next], shoulder[next]])
		_add_face(st, placement, height, [waist[i], shoulder[next], shoulder[i]])
		_add_face(st, placement, height, [shoulder[i], shoulder[next], apex])


func _add_face(st: SurfaceTool, placement: Transform3D, height: float, points: Array) -> void:
	for point in points:
		var local: Vector3 = point
		# 下ほど濃く、先ほど明るく。1 本の中に濃淡があると氷らしく見える。
		var ratio := clampf(local.y / maxf(height, 0.01), 0.0, 1.0)
		st.set_color(base_color.lerp(tip_color, ratio * ratio))
		st.add_vertex(placement * local)


func _build_plinth(ground_y: float) -> void:
	var sides := 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		var wobble := 0.82 + _hash(float(i) * 3.7) * 0.36
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		lower.append(direction * 1.25 * wobble + Vector3.DOWN * 0.35)
		# 縁の高さも辺ごとにずらす。真上から見て正多角形に見えると作り物っぽい。
		upper.append(direction * 0.82 * wobble + Vector3.UP * (0.2 + _hash(float(i) * 8.1) * 0.16))

	var top := Vector3.UP * 0.36
	for i in sides:
		var next := (i + 1) % sides
		_add_plinth_face(st, [lower[i], lower[next], upper[next]], 0.0)
		_add_plinth_face(st, [lower[i], upper[next], upper[i]], 0.0)
		_add_plinth_face(st, [upper[i], upper[next], top], 0.08)

	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	st.set_material(material)

	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	plinth.mesh = st.commit()
	plinth.position.y = ground_y
	add_child(plinth)


func _add_plinth_face(st: SurfaceTool, points: Array, lighten: float) -> void:
	for point in points:
		var shade: float = _hash(point.x * 5.1 + point.z * 3.3) * 0.07
		st.set_color(plinth_color.lightened(lighten + shade))
		st.add_vertex(point)


func _ground_height() -> float:
	var terrain := get_node_or_null(terrain_path)
	if terrain != null and terrain.has_method(&"height_at"):
		return terrain.height_at(global_position.x, global_position.z)
	return 0.0


## 引数から決まる 0〜1 の値。毎回同じ形になるようにするため。
func _hash(value: float) -> float:
	var raw := sin(value * 12.9898) * 43758.5453
	return raw - floor(raw)
