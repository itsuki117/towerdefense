class_name BuildSpot
extends Area3D
## タワーを 1 つだけ置ける設置可能マス。
##
## クリック判定は BuildManager からのレイキャストに任せているので、
## このノードは「レイに当たる形」と「今どういう状態かの見た目」だけを持つ。

enum Highlight { IDLE, VALID, INVALID }

const COLOR_IDLE := Color(0.92, 0.94, 0.98, 0.22)
## 選択中のタワーを置ける。
const COLOR_VALID := Color(0.35, 0.9, 0.45, 0.55)
## ゴールドが足りない。
const COLOR_INVALID := Color(0.9, 0.3, 0.3, 0.5)

@onready var _pad: MeshInstance3D = $Pad

var tower: Tower = null

var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"build_spot")
	# マスごとに色を変えるので、マテリアルはインスタンスごとに作る。
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = COLOR_IDLE
	_pad.set_surface_override_material(0, _material)


func is_occupied() -> bool:
	return tower != null


func place_tower(new_tower: Tower) -> void:
	tower = new_tower
	# 埋まったマスはもう選べないので、パッドは消す。
	_pad.visible = false


func set_highlight(state: Highlight) -> void:
	if is_occupied():
		return
	match state:
		Highlight.VALID:
			_material.albedo_color = COLOR_VALID
		Highlight.INVALID:
			_material.albedo_color = COLOR_INVALID
		_:
			_material.albedo_color = COLOR_IDLE
