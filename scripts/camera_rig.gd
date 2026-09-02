@tool
extends Camera3D
## マップを見下ろす固定カメラ。
##
## 向きを Transform3D の 9 個の数値で持つと、エディタで少し触っただけで
## 空を向いてしまい、その値がそのまま保存されてしまう。
## そこで「どこを見るか」だけを持ち、向きは位置から毎回計算する。
## @tool なので、誤って回してしまってもシーンを開き直せば元に戻る。
## 画角を変えたいときは position か look_at_target を動かす。

## このワールド座標を見る。マップのだいたい中央。
@export var look_at_target := Vector3(-2.0, 0.0, 0.0):
	set(value):
		look_at_target = value
		_aim()


func _ready() -> void:
	_aim()


func _aim() -> void:
	# シーン読み込み中は setter が先に走るので、ツリーに入るまでは何もしない。
	if not is_inside_tree():
		return
	var to_target := look_at_target - global_position
	# 真上や真下からだと up ベクトルと平行になり look_at が失敗する。
	if Vector2(to_target.x, to_target.z).length() < 0.001:
		return
	look_at(look_at_target, Vector3.UP)
