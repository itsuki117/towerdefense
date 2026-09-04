class_name Enemy
extends PathFollow3D
## 固定ルートを進む敵。
##
## ルート追従は Path3D + PathFollow3D に任せ、このスクリプトは progress を進めるだけ。
## v1.0 では経路探索を行わない（GDD の Non-Goals）。
## 生成側 (WaveManager) が Path3D の直下に add_child すること。

## 撃破された。引数は獲得ゴールド。
signal died(gold_value: int)
## 拠点に到達した。引数はライフ減少量。
signal reached_end(damage: int)

## 減速中の体色。元の色にこの色を混ぜて、効いていることを見て分かるようにする。
const SLOW_TINT := Color(0.45, 0.75, 1.0)
const SLOW_TINT_STRENGTH := 0.55

## 被弾したときに一瞬混ぜる色と、その持続時間。
## 弾が当たったことを、HP バーを出さずに分からせるための表現。
const FLASH_COLOR := Color(1.0, 0.96, 0.85)
const FLASH_TIME := 0.13
## 真っ白まで飛ばすと元の色が分からなくなるので、混ぜる上限を決める。
const FLASH_STRENGTH := 0.8

## 体の大きさ（半径）。EnemyData.body_scale がこれに掛かる。
const BODY_SIZE := Vector3(0.42, 0.36, 0.42)
## 跳ねる速さと、つぶれ具合。止まって見えないようにするための演出。
const HOP_SPEED := 5.0
const HOP_HEIGHT := 0.1
const SQUASH := 0.12

@export var data: EnemyData

@onready var _visual: MeshInstance3D = $Visual

var _hp: int = 1
## 撃破・到達のどちらかで true。二重に signal を出さないためのガード。
var _finished: bool = false
var _material: StandardMaterial3D = null
## 現在の速度倍率。1.0 で等速。
var _slow_factor: float = 1.0
var _slow_remaining: float = 0.0
## 跳ねる演出用の時間。個体ごとにずらして、群れが同時に跳ねないようにする。
var _hop_time: float = 0.0
## 被弾フラッシュの残り時間。
var _flash_remaining: float = 0.0


func _ready() -> void:
	add_to_group(&"enemy")
	# 終点でループさせず、progress_ratio を 1.0 で止める。
	loop = false
	rotation_mode = PathFollow3D.ROTATION_Y

	if data == null:
		push_warning("Enemy: EnemyData が未設定です")
		return
	_hp = data.max_hp
	_hop_time = randf() * TAU
	_apply_visual()


func _physics_process(delta: float) -> void:
	if _finished or data == null:
		return
	_update_slow(delta)
	_update_hop(delta)
	_update_flash(delta)
	progress += data.speed * _slow_factor * delta
	if progress_ratio >= 1.0:
		_finish(true)


func take_damage(amount: int) -> void:
	if _finished:
		return
	_flash_remaining = FLASH_TIME
	_refresh_color()
	Sfx.play(&"hit", -7.0)
	_hp -= amount
	if _hp <= 0:
		_finish(false)


## 減速を受ける。より強い減速が優先され、同じ強さなら持続時間だけが伸びる。
## （弱い減速で強い減速を上書きしてしまわないようにする）
func apply_slow(factor: float, duration: float) -> void:
	if _finished:
		return
	if factor > _slow_factor:
		return
	_slow_factor = clampf(factor, 0.05, 1.0)
	_slow_remaining = maxf(_slow_remaining, duration)
	_refresh_color()


## 被弾フラッシュを時間で戻す。
func _update_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining = maxf(_flash_remaining - delta, 0.0)
	_refresh_color()


func _update_slow(delta: float) -> void:
	if _slow_remaining <= 0.0:
		return
	_slow_remaining -= delta
	if _slow_remaining <= 0.0:
		_slow_factor = 1.0
		_refresh_color()


## ゴールへの近さ (0.0〜1.0)。タワーのターゲット選択に使う。
func get_goal_progress() -> float:
	return progress_ratio


func _finish(reached_goal: bool) -> void:
	_finished = true
	remove_from_group(&"enemy")
	if data == null:
		queue_free()
		return
	if reached_goal:
		Sfx.play(&"life_lost")
		reached_end.emit(data.damage)
	else:
		# エフェクトは自分の子にしない。queue_free で巻き込まれてしまう。
		Burst.spawn(self, _visual.global_position, Burst.Kind.DEATH, data.body_color)
		Sfx.play(&"enemy_die", -4.0)
		died.emit(data.gold_value)
	queue_free()


## 遅くなるほど跳ねる間隔も伸びる。減速が効いていることが動きでも分かる。
func _update_hop(delta: float) -> void:
	_hop_time += delta * HOP_SPEED * _slow_factor
	var lift := absf(sin(_hop_time))
	var squash := 1.0 - lift * SQUASH
	var stretch := 1.0 + lift * SQUASH
	_visual.position.y = BODY_SIZE.y + lift * HOP_HEIGHT * data.body_scale
	_visual.scale = Vector3(squash, stretch, squash) * data.body_scale


func _apply_visual() -> void:
	# 球のままだと表面がのっぺりするので、面を粗く割った塊にする。
	# 色は頂点カラーではなく albedo_color 側で掛けて、メッシュは色違いで使い回す。
	_visual.mesh = LowPoly.blob(BODY_SIZE, Color.WHITE, 0.1)
	_visual.position.y = BODY_SIZE.y
	_visual.scale = Vector3.ONE * data.body_scale
	# 敵ごとに色を変えるので、マテリアルはインスタンスごとに作る。
	_material = LowPoly.vertex_color_material()
	_visual.set_surface_override_material(0, _material)
	_refresh_color()


func _refresh_color() -> void:
	if _material == null or data == null:
		return
	var color := data.body_color
	if _slow_factor < 1.0:
		color = color.lerp(SLOW_TINT, SLOW_TINT_STRENGTH)
	# フラッシュは減速の色にも上書きで乗せる。当たった事実のほうを優先して見せる。
	if _flash_remaining > 0.0:
		color = color.lerp(FLASH_COLOR, _flash_remaining / FLASH_TIME * FLASH_STRENGTH)
	_material.albedo_color = color
