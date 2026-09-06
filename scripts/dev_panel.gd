extends Control
## 開発中だけ出る操作パネル。**リリース書き出しでは丸ごと消える。**
##
## `OS.is_debug_build()` が false のとき（＝書き出した製品版）は _ready で
## 自分を捨てる。「非表示にする」ではなく**ツリーから消す**のは、
## 隠しただけだと入力やショートカットが生きたままになり、
## 何かの拍子に製品版で効いてしまうため。
##
## 既定では隠してあり、F3 で出し入れする。出しっぱなしにすると
## 見た目の確認（撮影ハーネス）に毎回写り込んでしまう。
##
## ここのボタンは**ゲームの規則を曲げる**もの。GameState を直接いじるので、
## 通常の経路（支払い・ライフ減少）を通らない。検証を速くするための道具で、
## バランスの測定に使うものではない（測定は tools/balance_sim.gd）。

## 1 回押すごとに増えるゴールド。
const GOLD_STEP := 1000
## 早送りの倍率。押すたびに次へ回る。
const TIME_SCALES := [1.0, 2.0, 4.0]

@onready var _panel: VBoxContainer = $Panel
@onready var _speed_button: Button = $Panel/SpeedButton
@onready var _invincible_button: Button = $Panel/InvincibleButton

var _speed_index: int = 0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	# ポーズ中（インターバル・勝敗画面）でも触れるようにする。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false

	$Panel/GoldButton.pressed.connect(_on_gold_pressed)
	$Panel/KillButton.pressed.connect(_on_kill_pressed)
	$Panel/ClearButton.pressed.connect(_on_clear_pressed)
	_invincible_button.pressed.connect(_on_invincible_pressed)
	_speed_button.pressed.connect(_on_speed_pressed)
	_refresh()
	print("[DEV] F3 で開発者パネル（製品版では出ない）")


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


func _on_gold_pressed() -> void:
	GameState.add_gold(GOLD_STEP)


## 今出ている敵を全部倒す。倒した扱いなのでゴールドも入る。
func _on_kill_pressed() -> void:
	for node in get_tree().get_nodes_in_group(&"enemy"):
		(node as Enemy).take_damage(999999)


## ステージを守り切ったことにしてインターバルへ飛ぶ。
##
## 残りの波は止めない（ツリーがポーズされ、「次へ」でシーンごと作り直されるため）。
func _on_clear_pressed() -> void:
	_on_kill_pressed()
	GameState.clear_stage()


func _on_invincible_pressed() -> void:
	GameState.invincible = not GameState.invincible
	_refresh()


func _on_speed_pressed() -> void:
	_speed_index = (_speed_index + 1) % TIME_SCALES.size()
	Engine.time_scale = TIME_SCALES[_speed_index]
	_refresh()


func _refresh() -> void:
	_invincible_button.text = "無敵  %s" % ("ON" if GameState.invincible else "OFF")
	_speed_button.text = "早送り  ×%d" % int(TIME_SCALES[_speed_index])
