class_name Burst
extends CPUParticles3D
## 小さな立方体を撒く使い捨てのエフェクト。
##
## 呼ぶ側は `Burst.spawn(container, position, Burst.Kind.DEATH, color)` の 1 行だけ。
## 撒いたあとは自分で消えるので、後始末を呼ぶ側が持たない。
##
## GPUParticles ではなく CPUParticles を使っているのは、GL Compatibility
## レンダラ（Web 書き出しの前提）で確実に動くのがこちらだから。
## 数十個の立方体を数秒撒くだけなので、CPU でも負荷は問題にならない。
##
## メッシュとマテリアルは 1 つだけ作って全インスタンスで共有する。
## 撃破のたびに作り直すと、後半の波でゴミが大量に出る。

enum Kind {
	HIT,  ## 弾が当たった。小さく散る。
	DEATH,  ## 敵が壊れた。大きめに、重力で落ちる。
	MUZZLE,  ## 砲口。砲身の向きへ短く吹く。
	DUST,  ## タワーを建てた。足元から低く広がる。
}

## 種類ごとの設定。粒の数 / 初速 / 寿命 / 大きさ / 広がり(度) / 重力。
const PRESETS := {
	Kind.HIT: [8, 2.6, 0.32, 0.06, 180.0, 6.0],
	Kind.DEATH: [15, 3.2, 0.6, 0.1, 180.0, 9.5],
	Kind.MUZZLE: [6, 3.0, 0.2, 0.055, 32.0, 1.0],
	Kind.DUST: [14, 1.6, 0.55, 0.08, 95.0, 5.0],
}

## メッシュと縮小カーブの置き場。インスタンス間で使い回す。
static var _shared: Dictionary = {}

var kind: Kind = Kind.HIT


## エフェクトを 1 つ出す。
##
## source は出どころのノード（自分自身を渡せばよい）。world_position は
## ワールド座標。forward を渡すとその向きへ吹く（砲口など向きが要るものだけ）。
##
## 置き場はグループで探し、source の子にはしない。撃った敵やタワーが
## 消えたときに、出したエフェクトまで巻き込まれて消えてしまうため。
static func spawn(
	source: Node,
	world_position: Vector3,
	kind_value: Kind,
	color_value: Color,
	forward: Vector3 = Vector3.ZERO
) -> void:
	if source == null or not source.is_inside_tree():
		return
	var container := source.get_tree().get_first_node_in_group(&"effect_container")
	if container == null:
		return
	var burst := Burst.new()
	burst.kind = kind_value
	burst.color = color_value
	container.add_child(burst)
	burst.global_position = world_position
	# CPUParticles の direction はノードのローカル基準なので、
	# 向きを付けたいときはノードごと回す。
	if forward.length_squared() > 0.0001:
		burst.global_basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	burst.emitting = true
	burst._free_when_done()


func _init() -> void:
	# 一度に撒いて終わり。撒き続けるエフェクトはこのクラスでは扱わない。
	one_shot = true
	explosiveness = 1.0
	emitting = false
	# 撒いたあとの粒は発生源に付いていかない。
	local_coords = false


func _ready() -> void:
	var preset: Array = PRESETS[kind]
	amount = int(preset[0])
	lifetime = float(preset[2])
	spread = float(preset[4])
	gravity = Vector3(0.0, -float(preset[5]), 0.0)
	initial_velocity_min = float(preset[1]) * 0.5
	initial_velocity_max = float(preset[1])
	# 粒ごとに大きさを散らす。全部同じだと作り物っぽくなる。
	scale_amount_min = float(preset[3]) * 0.6
	scale_amount_max = float(preset[3])
	# 飛びながら縮んで消える。透明度ではなく大きさで消すと、
	# 半透明の描画順を気にしなくて済む。
	scale_amount_curve = _shrink_curve()
	angular_velocity_min = -220.0
	angular_velocity_max = 220.0
	mesh = _cube_mesh()

	# 砲口だけは上ではなくノードの前方（spawn で回した向き）へ吹く。
	direction = Vector3.FORWARD if kind == Kind.MUZZLE else Vector3.UP


func _free_when_done() -> void:
	# SceneTree のタイマーは既定でポーズを無視するので、
	# 勝敗画面でツリーが止まっていても取り残されない。
	await get_tree().create_timer(lifetime * 1.4 + 0.1).timeout
	queue_free()


## 立方体 1 個ぶんのメッシュ。粒ごとの色は CPUParticles から頂点カラーで届く。
func _cube_mesh() -> Mesh:
	if _shared.has(&"cube"):
		return _shared[&"cube"]
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	cube.material = material
	_shared[&"cube"] = cube
	return cube


func _shrink_curve() -> Curve:
	if _shared.has(&"shrink"):
		return _shared[&"shrink"]
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.65, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	_shared[&"shrink"] = curve
	return curve
