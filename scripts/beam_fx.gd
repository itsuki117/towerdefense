class_name BeamFx
extends MeshInstance3D
## レールガンの光線。`TowerData.Shot.BEAM` のタワーが撃った瞬間だけ残る線。
##
## 弾を飛ばさない（撃った瞬間に当たっている）ので、当たり判定も追尾も持たない。
## 出したあとは自分で細くなって消える。
##
## **透明度ではなく太さで消す。** Burst と同じ理由で、半透明の描画順を
## 気にせずに済むため（GL Compatibility では重なった半透明が入れ替わる）。

## 出てから消えるまでの時間。撃った瞬間が見えれば十分なので短くする。
const LIFETIME := 0.18
## 線の太さ (m)。
const THICKNESS := 0.09

static var _shared_mesh: BoxMesh = null


## from から to へ 1 本の線を出す。置き場は Burst と同じくグループで探すので、
## 撃ったタワーが消えても線だけは残って消える。
static func spawn(source: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if source == null or not source.is_inside_tree():
		return
	var container := source.get_tree().get_first_node_in_group(&"effect_container")
	if container == null:
		return
	var length := from.distance_to(to)
	if length < 0.01:
		return

	var beam := BeamFx.new()
	beam.mesh = _beam_mesh()
	beam.set_surface_override_material(0, _beam_material(color))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	container.add_child(beam)
	# 中点に置いて的のほうを向け、奥行きだけ距離ぶん伸ばす。
	beam.global_position = (from + to) * 0.5
	beam.look_at(to, Vector3.UP)
	beam.scale = Vector3(1.0, 1.0, length)
	beam._fade()


## 太さだけを絞って消す。奥行き（= 距離）はそのまま残す。
func _fade() -> void:
	var tween := create_tween()
	tween.tween_property(self, ^"scale:x", 0.0, LIFETIME).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(self, ^"scale:y", 0.0, LIFETIME).set_trans(Tween.TRANS_QUAD)
	tween.finished.connect(queue_free)


## 奥行き 1 の角柱。伸ばして使うので、長さは scale 側で掛ける。
static func _beam_mesh() -> BoxMesh:
	if _shared_mesh == null:
		_shared_mesh = BoxMesh.new()
		_shared_mesh.size = Vector3(THICKNESS, THICKNESS, 1.0)
	return _shared_mesh


static func _beam_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
