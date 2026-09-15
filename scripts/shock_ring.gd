class_name ShockRing
extends MeshInstance3D
## 着弾の衝撃波。地面と水平に広がって消える輪。
##
## 爆発（砲弾）とレールガンの着弾で使う。**巻き込みの範囲がそのまま見える**ので、
## 「どこまで巻き込んだか」がプレイヤーに伝わる——数値を UI に出さずに済ませるための絵。
##
## Burst（立方体を撒く粒）と違って 1 枚しか出ないので、こちらは透明度で消してよい
## （半透明の描画順が問題になるのは、重なった粒が大量にあるとき）。

## 広がりきるまでの時間。着弾の一瞬だけ見えればよいので短くする。
const LIFETIME := 0.28
## 輪の太さ（外径に対する割合）。太すぎると円盤に見える。
const THICKNESS_RATIO := 0.16
## 出るときの大きさ（最終半径に対する割合）。
const START_RATIO := 0.25

static var _shared_mesh: TorusMesh = null


## radius は広がりきったときの半径 (m)。巻き込みの半径をそのまま渡す想定。
static func spawn(source: Node, at: Vector3, color: Color, radius: float) -> void:
	if source == null or not source.is_inside_tree() or radius <= 0.0:
		return
	var container := source.get_tree().get_first_node_in_group(&"effect_container")
	if container == null:
		return

	var ring := ShockRing.new()
	ring.mesh = _ring_mesh()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.set_surface_override_material(0, material)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(ring)
	# 地面に少し浮かせる。着弾点そのものだと地形に埋まって欠ける。
	ring.global_position = at + Vector3.UP * 0.08
	ring.scale = Vector3.ONE * radius * START_RATIO
	ring._expand(material, radius)


## 広がりながら薄くなる。
func _expand(material: StandardMaterial3D, radius: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, ^"scale", Vector3.ONE * radius, LIFETIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(material, ^"albedo_color:a", 0.0, LIFETIME) \
		.set_trans(Tween.TRANS_SINE)
	tween.finished.connect(queue_free)


## 半径 1 の輪。大きさは scale 側で掛けるので、形は 1 つで足りる。
static func _ring_mesh() -> TorusMesh:
	if _shared_mesh == null:
		_shared_mesh = TorusMesh.new()
		_shared_mesh.outer_radius = 1.0
		_shared_mesh.inner_radius = 1.0 - THICKNESS_RATIO
		_shared_mesh.rings = 24
		_shared_mesh.ring_segments = 5
	return _shared_mesh
