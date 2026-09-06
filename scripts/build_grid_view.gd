extends Node3D
## 置けるマスの見せ方。盤面そのもの（BuildGrid）は Level が持っている。
##
## 置けるのは道沿いの 1 マスぶんだけなので、**盤面は常に出しておく**。
## 数が絞られていて画面の邪魔にならず、出しっぱなしのほうが
## 「どこに置けるか」を探さずに済む。カーソルの光だけがタワー選択に連動する。
##
## マスは MultiMesh で一度に描く。マスごとにノードを作るとステージを切り替える
## たびに作り直すことになるうえ、当たり判定も要らない
## （クリック位置は地面との交点から割り出している）。

## マスの板の大きさ。マスいっぱいだと隣とくっついて格子に見えないので少し縮める。
const PAD_SCALE := 0.86
## 地面から浮かせる量。道のリボンより上に出す。
const LIFT := 0.05
## カーソルをマスの板よりさらに浮かせる量。
const CURSOR_LIFT := 0.03

## 置けるマスの色（薄く出す）。
const COLOR_FREE := Color(0.85, 0.92, 1.0, 0.18)
## カーソルが乗っていて、買えるマス。
## 草の上の緑は沈むので、白に寄せた明るい色を濃いめに乗せる。
const COLOR_VALID := Color(0.72, 1.0, 0.78, 0.85)
## ゴールドが足りない、または置けないマス。
const COLOR_INVALID := Color(1.0, 0.42, 0.38, 0.8)

var _pads: MultiMeshInstance3D = null
var _cursor: MeshInstance3D = null
var _cursor_material: StandardMaterial3D = null
var _grid: BuildGrid = null


func _ready() -> void:
	_pads = MultiMeshInstance3D.new()
	_pads.name = "Pads"
	_pads.material_override = _make_material(COLOR_FREE)
	add_child(_pads)

	_cursor_material = _make_material(COLOR_VALID)
	_cursor = MeshInstance3D.new()
	_cursor.name = "Cursor"
	_cursor.mesh = _pad_mesh(1.0)
	_cursor.material_override = _cursor_material
	_cursor.visible = false
	add_child(_cursor)

	var level := Level.find(self)
	if level != null:
		_grid = level.grid
	_rebuild_pads()


## カーソルを 1 マスに合わせる。buildable が false なら赤く出す。
func set_cursor(cell: Vector2i, buildable: bool) -> void:
	if _grid == null:
		return
	_cursor.visible = true
	_cursor.position = _grid.placement_of(cell) + Vector3.UP * (LIFT + CURSOR_LIFT)
	_cursor_material.albedo_color = COLOR_VALID if buildable else COLOR_INVALID


func hide_cursor() -> void:
	_cursor.visible = false


## 建った後など、空きマスが変わったら呼ぶ。
func refresh() -> void:
	_rebuild_pads()


func _rebuild_pads() -> void:
	if _grid == null:
		return
	var free := _grid.free_cells()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _pad_mesh(PAD_SCALE)
	multimesh.instance_count = free.size()
	for i in free.size():
		var point := _grid.placement_of(free[i]) + Vector3.UP * LIFT
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, point))
	_pads.multimesh = multimesh


func _pad_mesh(scale_factor: float) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * BuildGrid.CELL * scale_factor
	# QuadMesh は XY 平面に立って生まれるので、寝かせて地面に敷く。
	quad.orientation = PlaneMesh.FACE_Y
	return quad


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 地面の陰影に影響されず、盤面として均一に読めるようにする。
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
