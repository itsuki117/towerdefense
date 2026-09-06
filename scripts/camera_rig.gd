@tool
extends Camera3D
## マップを見下ろす固定カメラ。建てたタワーをクリックすると寄って見せる。
##
## 向きを Transform3D の 9 個の数値で持つと、エディタで少し触っただけで
## 空を向いてしまい、その値がそのまま保存されてしまう。
## そこで「どこを見るか」だけを持ち、向きは位置から毎回計算する。
## @tool なので、誤って回してしまってもシーンを開き直せば元に戻る。
## 画角を変えたいときは position か look_at_target を動かす。
##
## 寄りの視点は「引きの視点と同じ方位から、少し低い角度で近づく」ように出す。
## 固定のオフセットにすると、マップのどちら側のタワーかで見え方が変わってしまう。

## このワールド座標を見る。マップのだいたい中央。
@export var look_at_target := Vector3(-2.0, 0.0, 0.0):
	set(value):
		look_at_target = value
		_aim()

@export_group("タワーへの寄り")
## タワーからカメラまでの距離。上位ティアのタワーは大きいので、
## focus_radius() を持つ相手にはその比で伸ばす（固定だと画面からはみ出す）。
@export var focus_distance: float = 4.6
## focus_distance がちょうど良い相手の大きさ。これより大きいと距離を伸ばす。
const FOCUS_BASE_RADIUS := 0.75
## 寄ったときの見下ろし角（度）。引きより低くして、砲台の形が読めるようにする。
@export var focus_elevation: float = 27.0
## 注視点をタワーの根元からどれだけ持ち上げるか。
@export var focus_look_height: float = 0.8
## 寄る・戻るのに掛ける秒数。
@export var focus_duration: float = 0.45
## タワーの当たり判定が乗っている物理レイヤー（4 番 = tower）。
@export_flags_3d_physics var tower_mask: int = 8
## クリックを拾うレイの長さ。
const RAY_LENGTH := 200.0

## 今寄っているタワー。引きの状態なら null。
var _focused: Node3D = null
## 引きの視点。シーンに書かれている位置と注視点をそのまま覚えておく。
var _home_position := Vector3.ZERO
var _home_target := Vector3.ZERO
## 補間の開始・終了と進み具合。
var _from_position := Vector3.ZERO
var _from_target := Vector3.ZERO
var _to_position := Vector3.ZERO
var _to_target := Vector3.ZERO
var _blend: float = 0.0:
	set(value):
		_blend = value
		position = _from_position.lerp(_to_position, _blend)
		look_at_target = _from_target.lerp(_to_target, _blend)

var _tween: Tween = null


func _ready() -> void:
	_home_position = position
	_home_target = look_at_target
	_aim()
	set_process_unhandled_input(not Engine.is_editor_hint())


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		# 設置マスのクリックは BuildManager が先に食べるので、ここには届かない。
		var tower := _tower_under_mouse()
		if tower != null:
			# 同じタワーをもう一度クリックしたら引きに戻す（トグル）。
			if tower == _focused:
				clear_focus()
			else:
				focus_on(tower)
			get_viewport().set_input_as_handled()
		elif _focused != null:
			# 何も無いところをクリックしたら引きに戻る。
			clear_focus()
			get_viewport().set_input_as_handled()
	elif button != null and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		# 右クリックはまず BuildManager がタワー選択の解除に使う。
		# 選択が無いときだけここへ届くので、そのときは引きに戻す。
		if _focused != null:
			clear_focus()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel") and _focused != null:
		clear_focus()


func is_focused() -> bool:
	return _focused != null


## タワーに寄る。引きのときと同じ方位から、少し低い角度で近づく。
func focus_on(target: Node3D) -> void:
	if target == null:
		return
	_focused = target
	var pivot := target.global_position
	var away := _home_position - _home_target
	var azimuth := Vector2(away.x, away.z)
	if azimuth.length() < 0.001:
		azimuth = Vector2(0.0, 1.0)
	azimuth = azimuth.normalized()
	var elevation := deg_to_rad(focus_elevation)
	var offset := Vector3(
		azimuth.x * cos(elevation), sin(elevation), azimuth.y * cos(elevation)
	) * (focus_distance * _focus_scale(target))
	_start_move(pivot + offset, pivot + Vector3.UP * focus_look_height)


## 相手の大きさに合わせた距離の倍率。大きさを申告しない相手は 1.0。
func _focus_scale(target: Node3D) -> float:
	if not target.has_method(&"focus_radius"):
		return 1.0
	var radius: float = target.call(&"focus_radius")
	return maxf(radius / FOCUS_BASE_RADIUS, 1.0)


## 引きの視点に戻す。
func clear_focus() -> void:
	if _focused == null:
		return
	_focused = null
	_start_move(_home_position, _home_target)


func _start_move(to_position: Vector3, to_target: Vector3) -> void:
	_from_position = position
	_from_target = look_at_target
	_to_position = to_position
	_to_target = to_target
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 位置と注視点を 1 本の値で動かす。別々に補間すると、
	# 途中で視線だけ先に着いてしまって不自然な振り向きになる。
	_blend = 0.0
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, ^"_blend", 1.0, focus_duration)


## マウスカーソルの下にあるタワー。なければ null。
func _tower_under_mouse() -> Node3D:
	var mouse := get_viewport().get_mouse_position()
	var from := project_ray_origin(mouse)
	var to := from + project_ray_normal(mouse) * RAY_LENGTH

	var query := PhysicsRayQueryParameters3D.create(from, to, tower_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	# 当たり判定はタワーの子として作っているので、親を返す。
	var area := hit.get("collider") as Area3D
	return area.get_parent() as Node3D if area != null else null


func _aim() -> void:
	# シーン読み込み中は setter が先に走るので、ツリーに入るまでは何もしない。
	if not is_inside_tree():
		return
	var to_target := look_at_target - global_position
	# 真上や真下からだと up ベクトルと平行になり look_at が失敗する。
	if Vector2(to_target.x, to_target.z).length() < 0.001:
		return
	look_at(look_at_target, Vector3.UP)
