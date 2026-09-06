extends Control
## 勝敗画面。ゲームが終わったらツリーごと止め、リスタートを受け付ける。
##
## 停止は SceneTree.paused で一括して行う。敵・タワー・弾・WaveManager を
## 個別に止めて回らずに済み、止め忘れも起きない。
## この画面だけ process_mode = ALWAYS にしてあるので、ポーズ中でもボタンが効く。

const COLOR_WIN := Color(0.55, 0.92, 0.62)
const COLOR_LOSE := Color(0.96, 0.5, 0.5)

@onready var _title: Label = $Panel/TitleLabel
@onready var _message: Label = $Panel/MessageLabel
@onready var _restart_button: Button = $Panel/RestartButton
@onready var _endless_button: Button = $Panel/EndlessButton


func _ready() -> void:
	hide()
	GameState.game_won.connect(_on_game_won)
	GameState.game_over.connect(_on_game_over)
	_restart_button.pressed.connect(_on_restart_pressed)
	_endless_button.pressed.connect(_on_endless_pressed)
	_endless_button.hide()


func _on_game_won() -> void:
	Sfx.play(&"victory")
	# 勝ってからが無限モードの入り口。ゴールドと強化を持ったまま続けられる。
	_endless_button.show()
	_show_result("VICTORY", "全 %d ステージを守りきった" % GameState.stage_count(), COLOR_WIN)


func _on_game_over() -> void:
	Sfx.play(&"defeat")
	_show_result("DEFEAT", _defeat_message(), COLOR_LOSE)


## 無限モードで倒れたときは、どこまで行けたかがそのまま記録になる。
func _defeat_message() -> String:
	if not GameState.endless:
		return "クリスタルが破壊された"
	return "無限モード %d 周目 ／ ステージ %d ／ ウェーブ %d で力尽きた" % [
		GameState.endless_round, GameState.stage_number(), GameState.wave,
	]


func _show_result(title: String, message: String, color: Color) -> void:
	_title.text = title
	_title.add_theme_color_override(&"font_color", color)
	_message.text = message
	show()
	_restart_button.grab_focus()
	get_tree().paused = true


func _on_endless_pressed() -> void:
	get_tree().paused = false
	GameState.start_endless()
	get_tree().call_deferred(&"reload_current_scene")


func _on_restart_pressed() -> void:
	get_tree().paused = false
	# GameState は Autoload でシーンをまたいで生き残るので、明示的に戻す。
	# 強化もゴールドもステージ番号も失う（1 周回のみ＝セーブは持たない）。
	GameState.reset_run()
	# 自分自身を含むシーンを作り直すので、フレーム境界まで遅らせる。
	get_tree().call_deferred(&"reload_current_scene")
