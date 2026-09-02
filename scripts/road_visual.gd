extends MultiMeshInstance3D
## 親の Path3D のカーブに沿ってタイルを並べ、敵の通り道を見せる。
##
## Blender 製の道アセットが用意できたらこの手続き生成ごと差し替える想定。
## MultiMesh なので何百枚並べてもドローコールは 1 回。
## @tool にしていないのは、生成した MultiMesh がシーンに保存されて
## .tscn の差分が膨らむのを避けるため（実行時にだけ組み立てる）。

@export var tile_spacing: float = 0.55
@export var tile_size: Vector3 = Vector3(2.0, 0.06, 1.0)
@export var tile_color: Color = Color(0.45, 0.38, 0.31)
## 地面との Z ファイティングを避けるための浮かせ量。
@export var ground_offset: float = 0.02


func _ready() -> void:
	_build()


func _build() -> void:
	var path := get_parent() as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		push_warning("RoadVisual: 親が Path3D でないか、カーブが未設定です")
		return

	var curve := path.curve
	var total_length := curve.get_baked_length()
	var spacing := maxf(tile_spacing, 0.05)
	var count := int(total_length / spacing) + 1

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = tile_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tile_color
	tile_mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tile_mesh
	mm.instance_count = count

	var height_offset := Vector3(0.0, ground_offset + tile_size.y * 0.5, 0.0)
	for i in count:
		var distance := minf(float(i) * spacing, total_length)
		var point := curve.sample_baked(distance)
		var ahead := curve.sample_baked(minf(distance + 0.1, total_length))
		var forward := ahead - point
		forward.y = 0.0

		var tile_basis := Basis.IDENTITY
		if forward.length() > 0.0001:
			tile_basis = Basis.looking_at(forward.normalized(), Vector3.UP)
		mm.set_instance_transform(i, Transform3D(tile_basis, point + height_offset))

	multimesh = mm
