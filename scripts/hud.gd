extends Control
## ゴールド / ライフ / ウェーブの表示と、タワー選択・ウェーブ開始ボタン。
##
## 表示は GameState の signal を購読するだけで、こちらから状態を書き換えない。
## ボタンは tower_options の TowerData から生成するので、タワーが増えたら
## 配列に .tres を足すだけでよい（ステップ6の 2 種類目もこれで済む）。

## TowerData の配列。
@export var tower_options: Array = []
@export var build_manager_path: NodePath
@export var wave_manager_path: NodePath

@onready var _gold_label: Label = $Stats/GoldLabel
@onready var _lives_label: Label = $Stats/LivesLabel
@onready var _wave_label: Label = $Stats/WaveLabel
@onready var _tower_bar: HBoxContainer = $TowerBar
@onready var _next_wave_button: Button = $NextWaveButton

var _build_manager: BuildManager = null
var _wave_manager: WaveManager = null
## Button -> TowerData
var _buttons: Dictionary = {}


func _ready() -> void:
	_build_manager = get_node_or_null(build_manager_path) as BuildManager
	if _build_manager == null:
		push_error("HUD: build_manager_path に BuildManager を指定してください")

	_wave_manager = get_node_or_null(wave_manager_path) as WaveManager
	if _wave_manager == null:
		push_error("HUD: wave_manager_path に WaveManager を指定してください")

	_create_tower_buttons()

	GameState.gold_changed.connect(_on_gold_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.game_over.connect(_on_game_finished)
	GameState.game_won.connect(_on_game_finished)
	if _build_manager != null:
		_build_manager.selection_changed.connect(_on_selection_changed)
	if _wave_manager != null:
		_wave_manager.countdown_changed.connect(_on_countdown_changed)
		_next_wave_button.pressed.connect(_wave_manager.request_next_wave)

	_on_gold_changed(GameState.gold)
	_on_lives_changed(GameState.lives)
	_on_wave_changed(GameState.wave)
	_on_countdown_changed(_wave_manager.get_countdown() if _wave_manager != null else -1.0)


func _create_tower_buttons() -> void:
	for option in tower_options:
		var data := option as TowerData
		if data == null:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(190, 56)
		button.text = "%s   %d G" % [data.display_name, data.cost]
		button.tooltip_text = "ダメージ %d ／ 射程 %.0f ／ %.1f 発/秒" % [
			data.damage, data.attack_range, data.fire_rate,
		]
		button.toggled.connect(_on_tower_button_toggled.bind(button))
		_tower_bar.add_child(button)
		_buttons[button] = data


func _on_tower_button_toggled(pressed: bool, button: Button) -> void:
	if _build_manager == null:
		return
	if pressed:
		# 選択は 1 つだけ。
		for other in _buttons:
			if other != button:
				(other as Button).set_pressed_no_signal(false)
		_build_manager.select_tower(_buttons[button])
	elif _build_manager.get_selected() == _buttons[button]:
		_build_manager.clear_selection()


## 右クリックや Esc で BuildManager 側から選択が解除されたときにボタンを戻す。
func _on_selection_changed(data: TowerData) -> void:
	for button in _buttons:
		(button as Button).set_pressed_no_signal(_buttons[button] == data)


## 次の波までの残り時間。負の値は「今は待っていない」の意味。
func _on_countdown_changed(seconds_left: float) -> void:
	var waiting := seconds_left >= 0.0
	_next_wave_button.disabled = not waiting
	if waiting:
		# 切り上げにして、表示が 0 のまま待たされないようにする。
		_next_wave_button.text = "次の波へ  %d" % ceili(seconds_left)
	else:
		_next_wave_button.text = "ウェーブ進行中"


func _on_game_finished() -> void:
	_next_wave_button.hide()


func _on_gold_changed(value: int) -> void:
	_gold_label.text = "GOLD  %d" % value
	_refresh_buttons(value)


func _on_lives_changed(value: int) -> void:
	_lives_label.text = "LIVES  %d" % value


func _on_wave_changed(value: int) -> void:
	_wave_label.text = "WAVE  %d" % value


## 買えないタワーのボタンは押せなくする。選択中に買えなくなったら選択も解除する。
func _refresh_buttons(current_gold: int) -> void:
	for key in _buttons:
		var button := key as Button
		var data := _buttons[key] as TowerData
		var affordable := current_gold >= data.cost
		button.disabled = not affordable
		if not affordable and button.button_pressed:
			button.set_pressed_no_signal(false)
			if _build_manager != null and _build_manager.get_selected() == data:
				_build_manager.clear_selection()
