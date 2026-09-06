class_name BuildManager
extends Node
## タワーの選択からグリッドへの設置までを受け持つ。
##
## v1.0 は決め打ちの設置マス 10 個に Area3D を置き、レイを当てて掴んでいた。
## グリッドになるとマスは 100 個近くになるので、**マスごとの当たり判定は持たない**。
## クリックした場所は「カメラのレイと高台の上面 (y=0) の交点」から割り出し、
## そこがどのマスかを計算で求める。当たり判定を並べても得られるものが無い。
##
## 支払いは必ず GameState.spend_gold() を通し、足りなければ設置自体が起きない。

signal selection_changed(data: TowerData)

const RAY_LENGTH := 200.0
## 設置したときに舞う土煙の色。
const DUST_COLOR := Color(0.58, 0.53, 0.44)
## 建てた場所からこの距離にある小物はどける。マスの半分より少し広め。
const PROP_CLEAR_RADIUS := 1.2

## 専用シーンを持たないタワー用のシーン。TowerData.tower_scene があればそちらを使う。
@export var default_tower_scene: PackedScene
@export var camera_path: NodePath
@export var towers_parent_path: NodePath

var _camera: Camera3D = null
var _towers_parent: Node3D = null
var _selected: TowerData = null
var _grid: BuildGrid = null
var _view: Node = null
## カーソルが乗っているマス。_has_hover が false なら盤面の外。
var _hovered := Vector2i.ZERO
var _has_hover: bool = false


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_towers_parent = get_node_or_null(towers_parent_path) as Node3D
	if _camera == null or _towers_parent == null or default_tower_scene == null:
		push_error("BuildManager: camera_path / towers_parent_path / default_tower_scene を設定してください")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return

	var level := Level.find(self)
	if level == null or level.grid == null:
		push_error("BuildManager: 盤面を持つ Level が見つかりません")
		set_physics_process(false)
		return
	_grid = level.grid
	_view = level.get_node_or_null(^"BuildGridView")


func get_selected() -> TowerData:
	return _selected


func select_tower(data: TowerData) -> void:
	if _selected == data:
		return
	_selected = data
	selection_changed.emit(_selected)


func clear_selection() -> void:
	select_tower(null)


## 指定のマスに、今選んでいるタワーを建てる。建てられたら true。
##
## 入力からも検証ツールからもここを通す。ゴールドの支払いと盤面の更新を
## 1 か所にまとめておかないと、どちらかだけが進んだ状態になりうる。
func build_at(cell: Vector2i) -> bool:
	if _selected == null or _grid == null or not _grid.is_free(cell):
		return false

	# 支払った結果ゴールドが足りなくなると UI 側が選択を解除しにくるので、
	# 使う TowerData は支払いより前にローカルへ退避しておく。
	var data := _selected
	# 支払いに失敗したら（＝ゴールド不足）タワーは生成しない。
	if not GameState.spend_gold(data.cost):
		return false

	# モデルを持つタワーは自分専用のシーンを指定できる。
	var scene := data.tower_scene if data.tower_scene != null else default_tower_scene
	var tower := scene.instantiate() as Tower
	if tower == null:
		return false
	tower.data = data
	_towers_parent.add_child(tower)
	# 地形には起伏があるので、マスの中心の地面の高さに乗せる。
	tower.global_position = _grid.placement_of(cell)
	# 位置が決まってから、守る区間をグラフに教える（敵の経路選択に効く）。
	tower.register_threat()
	_grid.occupy(cell, tower)
	if _view != null:
		_view.refresh()

	_clear_props_around(tower.global_position)

	Burst.spawn(self, tower.global_position + Vector3.UP * 0.15, Burst.Kind.DUST, DUST_COLOR)
	Sfx.play(&"build", -4.0)
	return true


## 建てた場所の岩や茂みをどける。地面をならして建てたように見せるため。
func _clear_props_around(point: Vector3) -> void:
	for node in get_tree().get_nodes_in_group(&"prop_scatter"):
		node.call(&"clear_around", point, PROP_CLEAR_RADIUS)


func _physics_process(_delta: float) -> void:
	_refresh_hover()


func _unhandled_input(event: InputEvent) -> void:
	# UI 上のクリックは Button が先に食べるので、ここには届かない。
	var button_event := event as InputEventMouseButton
	if button_event != null and button_event.pressed:
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			# 置けないマスのクリックは握り潰さない。
			# タワーに寄るカメラ側が受け取れなくなるため。
			if _has_hover and _grid.is_free(_hovered) and build_at(_hovered):
				get_viewport().set_input_as_handled()
		elif button_event.button_index == MOUSE_BUTTON_RIGHT:
			# 選んでいるものが無いときは握り潰さない。
			# 「右クリックで 1 つ戻る」をカメラの寄りにも使えるようにするため。
			if _selected != null:
				clear_selection()
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		clear_selection()


## カーソルの下のマスを求めて、カーソル表示を更新する。
func _refresh_hover() -> void:
	if _selected == null or _grid == null:
		_has_hover = false
		if _view != null:
			_view.hide_cursor()
		return

	# Plane.intersects_ray は Vector3 か null を返すので、型は明示しておく
	# （:= だと Variant から推論することになり、警告がエラー扱いになる）。
	var point: Variant = _ground_point_under_mouse()
	if point == null:
		_has_hover = false
		if _view != null:
			_view.hide_cursor()
		return

	_hovered = BuildGrid.cell_at(point as Vector3)
	_has_hover = _grid.is_buildable(_hovered)
	if _view == null:
		return
	if not _has_hover:
		_view.hide_cursor()
	else:
		_view.set_cursor(_hovered, _grid.is_free(_hovered) and GameState.can_afford(_selected.cost))


## カメラのレイと高台の上面の交点。盤面の外なら null。
##
## 上面は起伏があるが振れ幅は数 cm なので、y=0 の平面との交点で足りる
## （見下ろし角でずれるのはマスの 1 割ほど）。
func _ground_point_under_mouse() -> Variant:
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var direction := _camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, direction)
