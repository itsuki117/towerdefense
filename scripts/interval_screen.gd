extends Control
## ステージ間のインターバル画面。
##
## 勝敗画面と同じく SceneTree.paused で全部止めてから出す。
## この画面だけ process_mode = ALWAYS にしてあるので、ポーズ中でもボタンが効く。
##
## 「次のステージへ」でシーンを読み直す。GameState は Autoload なので
## ゴールドとステージ番号は生き残り、タワーの配置と地形だけが作り直される。
##
## 強化 UI はここに入る予定（§16.4-5）。今は器だけ。

@onready var _title: Label = $Panel/TitleLabel
@onready var _message: Label = $Panel/MessageLabel
@onready var _next_button: Button = $Panel/NextButton


func _ready() -> void:
	hide()
	GameState.stage_cleared.connect(_on_stage_cleared)
	_next_button.pressed.connect(_on_next_pressed)


func _on_stage_cleared(stage_number: int, reward: int) -> void:
	_title.text = "STAGE %d CLEAR" % stage_number
	_message.text = "報酬 +%d G   所持 %d G" % [reward, GameState.gold]
	var next_stage := GameState.campaign.stages[GameState.stage + 1] as StageData
	if next_stage != null:
		_next_button.text = "次へ: %s" % next_stage.display_name
	show()
	_next_button.grab_focus()
	get_tree().paused = true
	Sfx.play(&"victory", -4.0)


func _on_next_pressed() -> void:
	get_tree().paused = false
	GameState.advance_stage()
	# 自分自身を含むシーンを作り直すので、フレーム境界まで遅らせる。
	get_tree().call_deferred(&"reload_current_scene")
