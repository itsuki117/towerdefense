class_name Projectile
extends Area3D
## タワーが撃つ弾。ターゲットを追尾し、到達したらダメージを与えて消える。
##
## 追尾で必ず当たるため衝突判定は使わず、距離で命中を判定している
## （撃った瞬間に外れが確定しないので、弾速も弾道も演出として自由に決められる）。
##
## **見た目と飛び方は TowerData.shot で決まる**（BOLT / SHELL / ORB / BEAM）。
## 段ごとに色と大きさも変えるので、弾を見ただけでどのタワーの何段目かが分かる。
## BEAM だけは弾を飛ばさず、Tower 側が即着弾させる（下の apply_hit を直接呼ぶ）。

const HIT_RADIUS := 0.3
const MAX_LIFETIME := 4.0
## 敵の中心あたりを狙うための高さオフセット。
const TARGET_HEIGHT_OFFSET := 0.4
## 山なりに飛ぶ弾（SHELL）が持ち上がる高さ。飛距離に比例させる。
##
## 固定値にすると、近くの敵へ撃ったときだけ不自然に高く跳ね上がる。
const ARC_RATIO := 0.18
const ARC_MAX := 1.6
## ORB がゆっくり回る速さ (度/秒)。氷の塊が漂う感じを出すためだけのもの。
const ORB_SPIN := 120.0
## 巻き込みを持たない弾の着弾で出す輪の半径 (m)。当たった場所を読ませるだけの大きさ。
const RING_MIN_RADIUS := 0.7
## 爆発のあとに残る煙の色。弾の色に染めると煙に見えないので、灰色で固定する。
const SMOKE_COLOR := Color(0.32, 0.3, 0.29)

## メッシュとマテリアルの置き場。形は種類ごと、色は色ごとに使い回す。
## 後半の波では毎秒数十発飛ぶので、そのたびに作ると細かいゴミが増える。
static var _shared: Dictionary = {}

var _target: Node3D = null
## 撃ったタワーの TowerData。ダメージも追加効果もここから読む。
var _data: TowerData = null
var _speed: float = 18.0
var _life: float = MAX_LIFETIME
## 弾道の計算に使う「山を付ける前の位置」。当たり判定もこちらで見る。
var _flat_position := Vector3.ZERO
## 撃った地点から的までの距離。山なりの弾がどこまで進んだかを測る物差し。
var _travel_total: float = 1.0
var _visual: Node3D = null


## 個別の数値ではなく TowerData ごと持たせる。効果が増えても引数を足さずに済み、
## 弾は「撃った側のデータどおりに当たる」だけの役割で保てる。
func launch(target: Node3D, tower_data: TowerData) -> void:
	_target = target
	_data = tower_data
	_speed = tower_data.projectile_speed
	_flat_position = global_position
	if target != null:
		_travel_total = maxf(global_position.distance_to(target.global_position), 0.01)
	_apply_shot_style()


## 種類・色・大きさを弾の見た目に反映する。
func _apply_shot_style() -> void:
	_visual = get_node_or_null(^"Visual")
	if _visual == null or _data == null:
		return
	# BEAM は線（BeamFx）が弾の代わりなので、弾そのものは見せない。
	# ただし**飛んでいること自体は他の段と同じ**——的が先に倒れれば無駄弾になる。
	if _data.shot == TowerData.Shot.BEAM:
		_visual.visible = false
		return
	var mesh_instance := _visual as MeshInstance3D
	if mesh_instance != null:
		mesh_instance.mesh = _shot_mesh(_data.shot)
		mesh_instance.set_surface_override_material(0, _shot_material(_data.shot_color))
	_visual.scale = Vector3.ONE * _data.shot_scale


func _physics_process(delta: float) -> void:
	_life -= delta
	# ターゲットが先に倒れた場合は不発として消える。
	if _life <= 0.0 or _data == null or not is_instance_valid(_target):
		queue_free()
		return

	var aim := _target.global_position + Vector3.UP * TARGET_HEIGHT_OFFSET
	var to_target := aim - _flat_position
	var step := _speed * delta

	if to_target.length() <= maxf(step, HIT_RADIUS):
		# 飛んできた向きをそのまま渡す（火花を撃った方向へ抜けさせるため）。
		apply_hit(self, _data, _target, global_position, to_target.normalized())
		queue_free()
		return

	_flat_position += to_target.normalized() * step
	var previous := global_position
	global_position = _flat_position + Vector3.UP * _arc_height(to_target.length())
	_face_travel(previous, delta)


## 山なりの弾が今どれだけ持ち上がっているか。まっすぐ飛ぶ弾は常に 0。
##
## 進んだ割合を sin で 0 → 1 → 0 と動かすだけ。放物線を解かないのは、
## 的が動くので「撃った時点の解」が途中で合わなくなるため。
func _arc_height(remaining: float) -> float:
	if _data.shot != TowerData.Shot.SHELL:
		return 0.0
	var progress := clampf(1.0 - remaining / _travel_total, 0.0, 1.0)
	return sin(progress * PI) * minf(_travel_total * ARC_RATIO, ARC_MAX)


## 進んでいる向きへ弾を向ける。まっすぐ飛ぶ弾でも、山なりの弾が
## 落ち際に下を向くのが分かるようにしたいので、実際の移動量から決める。
func _face_travel(previous: Vector3, delta: float) -> void:
	if _visual == null:
		return
	if _data.shot == TowerData.Shot.ORB:
		_visual.rotate_y(deg_to_rad(ORB_SPIN) * delta)
		return
	var travel := global_position - previous
	if travel.length_squared() > 0.000001:
		look_at(global_position + travel, Vector3.UP)


## 着弾処理。演出と巻き込みの入口をここ 1 か所にまとめてある。
##
## 追加効果を先に入れるのは、take_damage で敵が撃破処理に入ると
## その後の apply_slow が無視されるため。
static func apply_hit(
	source: Node, data: TowerData, target: Node3D, at: Vector3, forward := Vector3.ZERO
) -> void:
	if data == null:
		return
	_impact_fx(source, data, at, forward)
	_hit_one(data, target, data.damage)
	if data.splash_radius > 0.0:
		_splash(source, data, target, at)


## 着弾の見せ方。**弾の種類ごとに変える**——同じ爆発を使い回すと、
## 段を分けた意味（何が当たったのか分かる）が着弾の瞬間に消えてしまう。
static func _impact_fx(source: Node, data: TowerData, at: Vector3, forward: Vector3) -> void:
	# 輪は巻き込みの範囲をそのまま見せる。単体攻撃の弾でも、炸裂するものには
	# 小さい輪を出す（当たった位置が読めるので、撃ち合いの手応えが出る）。
	var ring := data.splash_radius if data.splash_radius > 0.0 else RING_MIN_RADIUS
	match data.shot:
		TowerData.Shot.SHELL:
			Burst.spawn(source, at, Burst.Kind.BLAST, data.shot_color, Vector3.ZERO, data.shot_scale)
			Burst.spawn(source, at, Burst.Kind.SMOKE, SMOKE_COLOR, Vector3.ZERO, data.shot_scale)
			ShockRing.spawn(source, at, data.shot_color, ring)
		TowerData.Shot.BEAM:
			# 火花は撃った向きへ抜ける。貫いた感じを出すため。
			Burst.spawn(source, at, Burst.Kind.SPARK, data.shot_color, forward, data.shot_scale)
			Burst.spawn(
				source, at, Burst.Kind.BLAST, data.shot_color, Vector3.ZERO, data.shot_scale * 0.8
			)
			ShockRing.spawn(source, at, data.shot_color, ring)
		TowerData.Shot.ORB:
			# 氷は砕ける。破片を少し大きめに撒いて、輪は淡く広げる。
			Burst.spawn(
				source, at, Burst.Kind.HIT, data.shot_color, Vector3.ZERO, data.shot_scale * 1.4
			)
			ShockRing.spawn(source, at, data.shot_color, ring * 0.8)
		_:
			Burst.spawn(source, at, Burst.Kind.HIT, data.shot_color, Vector3.ZERO, data.shot_scale)


## 巻き込み。狙われた 1 体は上で処理済みなので、ここでは周りだけを見る。
static func _splash(source: Node, data: TowerData, target: Node3D, at: Vector3) -> void:
	var amount := maxi(roundi(float(data.damage) * data.splash_falloff), 1)
	var radius_squared := data.splash_radius * data.splash_radius
	for node in source.get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null or enemy == target:
			continue
		if enemy.global_position.distance_squared_to(at) > radius_squared:
			continue
		_hit_one(data, enemy, amount)


static func _hit_one(data: TowerData, target: Node3D, amount: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if data.effect == TowerData.Effect.SLOW and target.has_method(&"apply_slow"):
		target.apply_slow(data.slow_factor, data.slow_duration)
	if target.has_method(&"take_damage"):
		target.take_damage(amount)


## 種類ごとの弾の形。大きさは shot_scale で掛けるので、ここでは 1 倍の形だけ作る。
static func _shot_mesh(shot: TowerData.Shot) -> Mesh:
	var key := "mesh_%d" % shot
	if _shared.has(key):
		return _shared[key]
	var mesh: Mesh
	match shot:
		TowerData.Shot.BOLT:
			# 細長い矢弾。look_at で -Z が前になるので、Z を伸ばす。
			var bolt := BoxMesh.new()
			bolt.size = Vector3(0.07, 0.07, 0.42)
			mesh = bolt
		TowerData.Shot.ORB:
			var orb := SphereMesh.new()
			orb.radius = 0.16
			orb.height = 0.32
			orb.radial_segments = 6
			orb.rings = 3
			mesh = orb
		_:
			# 砲弾。粗く割った球にして、飛んでいる間も面の向きで転がりが見える。
			var shell := SphereMesh.new()
			shell.radius = 0.13
			shell.height = 0.26
			shell.radial_segments = 7
			shell.rings = 4
			mesh = shell
	_shared[key] = mesh
	return mesh


## 弾の色。段ごとに違う色を使うので、色そのものを鍵にして使い回す。
static func _shot_material(color: Color) -> StandardMaterial3D:
	var key := "mat_%s" % color.to_html(false)
	if _shared.has(key):
		return _shared[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_shared[key] = material
	return material
