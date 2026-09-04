class_name BuildManager
extends Node
## タワーの選択から設置可能マスへの設置までを受け持つ。
##
## マスのクリック判定はビューポートのピッキング設定に依存しないよう、
## カメラからのレイキャストを自前で撃っている（設定に左右されず追いやすい）。
## 支払いは必ず GameState.spend_gold() を通し、足りなければ設置自体が起きない。

signal selection_changed(data: TowerData)

## BuildSpot が乗っている物理レイヤー（3 番 = build_spot）。
const BUILD_SPOT_MASK := 4
const RAY_LENGTH := 200.0
## 設置したときに舞う土煙の色。
const DUST_COLOR := Color(0.58, 0.53, 0.44)

## 専用シーンを持たないタワー用のシーン。TowerData.tower_scene があればそちらを使う。
@export var default_tower_scene: PackedScene
@export var camera_path: NodePath
@export var towers_parent_path: NodePath

var _camera: Camera3D = null
var _towers_parent: Node3D = null
var _selected: TowerData = null
var _hovered: BuildSpot = null


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_towers_parent = get_node_or_null(towers_parent_path) as Node3D
	if _camera == null or _towers_parent == null or default_tower_scene == null:
		push_error("BuildManager: camera_path / towers_parent_path / default_tower_scene を設定してください")
		set_physics_process(false)
		set_process_unhandled_input(false)


func get_selected() -> TowerData:
	return _selected


func select_tower(data: TowerData) -> void:
	if _selected == data:
		return
	_selected = data
	selection_changed.emit(_selected)


func clear_selection() -> void:
	select_tower(null)


func _physics_process(_delta: float) -> void:
	_hovered = _spot_under_mouse()
	_refresh_highlights()


func _unhandled_input(event: InputEvent) -> void:
	# UI 上のクリックは Button が先に食べるので、ここには届かない。
	var button_event := event as InputEventMouseButton
	if button_event != null and button_event.pressed:
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			# 埋まったマスのクリックはここで握り潰さない。
			# タワーに寄るカメラ側が受け取れなくなるため。
			if _hovered != null and not _hovered.is_occupied():
				_try_build(_hovered)
				get_viewport().set_input_as_handled()
		elif button_event.button_index == MOUSE_BUTTON_RIGHT:
			# 選んでいるものが無いときは握り潰さない。
			# 「右クリックで 1 つ戻る」をカメラの寄りにも使えるようにするため。
			if _selected != null:
				clear_selection()
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		clear_selection()


## マウスカーソルの下にある設置可能マス。なければ null。
func _spot_under_mouse() -> BuildSpot:
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var to := from + _camera.project_ray_normal(mouse) * RAY_LENGTH

	var query := PhysicsRayQueryParameters3D.create(from, to, BUILD_SPOT_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.get("collider") as BuildSpot


func _refresh_highlights() -> void:
	var has_selection := _selected != null
	for node in get_tree().get_nodes_in_group(&"build_spot"):
		var spot := node as BuildSpot
		if spot == null:
			continue
		if spot == _hovered and has_selection:
			if GameState.can_afford(_selected.cost):
				spot.set_highlight(BuildSpot.Highlight.VALID)
			else:
				spot.set_highlight(BuildSpot.Highlight.INVALID)
		else:
			spot.set_highlight(BuildSpot.Highlight.IDLE)


func _try_build(spot: BuildSpot) -> void:
	if _selected == null or spot.is_occupied():
		return

	# 支払った結果ゴールドが足りなくなると UI 側が選択を解除しにくるので、
	# 使う TowerData は支払いより前にローカルへ退避しておく。
	var data := _selected
	# 支払いに失敗したら（＝ゴールド不足）タワーは生成しない。
	if not GameState.spend_gold(data.cost):
		return

	# モデルを持つタワーは自分専用のシーンを指定できる。
	var scene := data.tower_scene if data.tower_scene != null else default_tower_scene
	var tower := scene.instantiate() as Tower
	if tower == null:
		return
	tower.data = data
	_towers_parent.add_child(tower)
	tower.global_position = spot.global_position
	spot.place_tower(tower)
	Burst.spawn(spot, spot.global_position + Vector3.UP * 0.15, Burst.Kind.DUST, DUST_COLOR)
	Sfx.play(&"build", -4.0)
