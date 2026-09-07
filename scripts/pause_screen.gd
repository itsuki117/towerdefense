extends Control
## 一時停止。HUD の ⏸ ボタンから開き、SceneTree を止める。
##
## 勝敗画面・インターバル画面と同じ「ツリーを止めて Control を出す」型
## （process_mode = ALWAYS でポーズ中もボタンが効く）。
## HelpScreen と違ってこちらは常にプレイヤーの明示操作でしか開かないので、
## 自動表示は無く、ポーズを挟んでも headless_check / vis_preview を壊さない。

@onready var _resume_button: Button = $Panel/ResumeButton


func _ready() -> void:
	hide()
	_resume_button.pressed.connect(close)


func open() -> void:
	show()
	_resume_button.grab_focus()
	get_tree().paused = true


func close() -> void:
	get_tree().paused = false
	hide()
