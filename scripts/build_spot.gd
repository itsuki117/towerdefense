class_name BuildSpot
extends Area3D
## タワーを 1 つだけ置ける設置可能マス。
##
## クリック判定は BuildManager からのレイキャストに任せているので、
## このノードは「レイに当たる形」と「今どういう状態かの見た目」だけを持つ。
##
## 見た目は「石の土台（Pad）＋状態を示す縁（Ring）」の 2 段構え。
## 半透明の板だけだと草の上に水たまりが浮いているように見えてしまうため、
## 土台は普通に陰影の付く石にして、色が変わるのは縁だけにしている。

enum Highlight { IDLE, VALID, INVALID }

const COLOR_IDLE := Color(0.86, 0.88, 0.92, 0.35)
## 選択中のタワーを置ける。
const COLOR_VALID := Color(0.4, 1.0, 0.5, 0.85)
## ゴールドが足りない。
const COLOR_INVALID := Color(1.0, 0.35, 0.32, 0.8)

@onready var _pad: MeshInstance3D = $Pad
@onready var _ring: MeshInstance3D = $Ring

var tower: Tower = null

var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"build_spot")
	# マスごとに色を変えるので、マテリアルはインスタンスごとに作る。
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = COLOR_IDLE
	_ring.set_surface_override_material(0, _material)


func is_occupied() -> bool:
	return tower != null


func place_tower(new_tower: Tower) -> void:
	tower = new_tower
	# もう選べないので状態を示す縁だけ消す。石の土台はタワーの足場として残す。
	_ring.visible = false


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
