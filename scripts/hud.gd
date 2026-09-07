extends Control
## ゴールド / ライフ / ウェーブの表示と、タワー選択・戦士雇用・ウェーブ開始ボタン。
##
## 表示は GameState の signal を購読するだけで、こちらから状態を書き換えない。
## ボタンは .tres の配列から生成するので、種類が増えたら配列に足すだけでよい。
##
## タワーは「選んでから盤面をクリック」なのでトグル、戦士は押した時点で
## 雇い終わるので普通のボタン、と押し心地を分けてある。
##
## **tower_options に入れるのは鎖の 1 段目（基準）だけ。** 強化で段が上がっても
## ボタンは増えず、同じボタンの中身が入れ替わる。今どの段かは GameState が持つ。

## TowerData の配列。ティアの鎖の**1 段目**を入れること。
@export var tower_options: Array = []
## WarriorData の配列。
@export var warrior_options: Array = []
@export var build_manager_path: NodePath
@export var wave_manager_path: NodePath
@export var warrior_manager_path: NodePath
@export var help_screen_path: NodePath
@export var pause_screen_path: NodePath

@onready var _gold_label: Label = $Stats/GoldLabel
@onready var _lives_label: Label = $Stats/LivesLabel
@onready var _wave_label: Label = $Stats/WaveLabel
@onready var _tower_bar: HBoxContainer = $BuildBar/TowerRow
@onready var _warrior_bar: HBoxContainer = $BuildBar/WarriorRow
@onready var _next_wave_button: Button = $NextWaveButton
@onready var _fullscreen_button: Button = $FullscreenButton
@onready var _help_button: Button = $HelpButton
@onready var _pause_button: Button = $PauseButton

var _build_manager: BuildManager = null
var _wave_manager: WaveManager = null
var _warrior_manager: WarriorManager = null
## Button -> TowerData（鎖の 1 段目。今の段は GameState から引く）
var _buttons: Dictionary = {}
## Button -> WarriorData
var _warrior_buttons: Dictionary = {}


func _ready() -> void:
	_build_manager = get_node_or_null(build_manager_path) as BuildManager
	if _build_manager == null:
		push_error("HUD: build_manager_path に BuildManager を指定してください")

	_wave_manager = get_node_or_null(wave_manager_path) as WaveManager
	if _wave_manager == null:
		push_error("HUD: wave_manager_path に WaveManager を指定してください")

	_warrior_manager = get_node_or_null(warrior_manager_path) as WarriorManager

	_create_tower_buttons()
	_create_warrior_buttons()

	_fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	var help_screen := get_node_or_null(help_screen_path)
	if help_screen != null:
		_help_button.pressed.connect(help_screen.open)
	var pause_screen := get_node_or_null(pause_screen_path)
	if pause_screen != null:
		_pause_button.pressed.connect(pause_screen.open)

	GameState.gold_changed.connect(_on_gold_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.stage_changed.connect(_on_stage_changed)
	GameState.game_over.connect(_on_game_finished)
	GameState.game_won.connect(_on_game_finished)
	GameState.upgrades_changed.connect(_on_upgrades_changed)
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
		var base := option as TowerData
		if base == null:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(190, 56)
		button.toggled.connect(_on_tower_button_toggled.bind(button))
		_tower_bar.add_child(button)
		_buttons[button] = base
	_refresh_tower_labels()


## ボタンの文字を今の段のものに書き直す。強化で段が入れ替わるので、
## 名前も費用も作った時点では決められない。
func _refresh_tower_labels() -> void:
	for key in _buttons:
		var data := GameState.current_tower(_buttons[key] as TowerData)
		(key as Button).text = "%s   %d G" % [data.display_name, data.cost]
		(key as Button).tooltip_text = "段 %d ／ ダメージ %d ／ 射程 %.1f ／ %.1f 発/秒" % [
			data.tier, data.damage, data.attack_range, data.fire_rate,
		]


## 強化を買った。ボタンの中身と、買える／買えないを作り直す。
func _on_upgrades_changed() -> void:
	_refresh_tower_labels()
	_refresh_warrior_labels()
	_refresh_buttons(GameState.gold)


## 戦士は置く場所を選ばないので、押した時点で雇い終わる（トグルにしない）。
func _create_warrior_buttons() -> void:
	for option in warrior_options:
		var data := option as WarriorData
		if data == null:
			continue
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(150, 48)
		button.text = "%s  %d G" % [data.display_name, data.cost]
		button.pressed.connect(_on_warrior_button_pressed.bind(data))
		_warrior_bar.add_child(button)
		_warrior_buttons[button] = data
	_refresh_warrior_labels()


## 説明は数値より先に**仕事**を出す。役職の違いは HP やダメージではなく
## 「何体止められるか」「どこから殴るか」で作ってあるため。
## ダメージだけは武器強化で動くので、ここで作り直せるようにしてある。
func _refresh_warrior_labels() -> void:
	for key in _warrior_buttons:
		var data := _warrior_buttons[key] as WarriorData
		var damage := maxi(1, roundi(float(data.damage) * GameState.weapon_multiplier()))
		(key as Button).tooltip_text = "%s\nHP %d ／ ダメージ %d ／ %.1f 回/秒 ／ 射程 %.1f" % [
			data.role_text, data.max_hp, damage, data.attack_rate, data.attack_range,
		]


func _on_warrior_button_pressed(data: WarriorData) -> void:
	if _warrior_manager != null:
		_warrior_manager.hire(data)
	# 人数がいっぱいになった／ゴールドが減った結果を押し心地へ返す。
	_refresh_buttons(GameState.gold)


func _on_tower_button_toggled(pressed: bool, button: Button) -> void:
	if _build_manager == null:
		return
	if pressed:
		# 選択は 1 つだけ。
		for other in _buttons:
			if other != button:
				(other as Button).set_pressed_no_signal(false)
		_build_manager.select_tower(GameState.current_tower(_buttons[button]))
	elif _build_manager.get_selected() == GameState.current_tower(_buttons[button]):
		_build_manager.clear_selection()


## 右クリックや Esc で BuildManager 側から選択が解除されたときにボタンを戻す。
func _on_selection_changed(data: TowerData) -> void:
	for button in _buttons:
		var current := GameState.current_tower(_buttons[button] as TowerData)
		(button as Button).set_pressed_no_signal(current == data)


## 次の波までの残り時間。負の値は「今は待っていない」の意味。
func _on_countdown_changed(seconds_left: float) -> void:
	var waiting := seconds_left >= 0.0
	_next_wave_button.disabled = not waiting
	if waiting:
		# 切り上げにして、表示が 0 のまま待たされないようにする。
		_next_wave_button.text = "次の波へ  %d" % ceili(seconds_left)
	else:
		_next_wave_button.text = "ウェーブ進行中"


## Web 書き出しでも DisplayServer.window_set_mode がブラウザの Fullscreen API を
## 叩いてくれる（ユーザー操作＝ボタン押下から直接呼ぶ必要がある）ので、
## デスクトップと同じコードで済む。
func _on_fullscreen_pressed() -> void:
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN
	)


func _on_game_finished() -> void:
	_next_wave_button.hide()


func _on_gold_changed(value: int) -> void:
	_gold_label.text = "GOLD  %d" % value
	_refresh_buttons(value)


func _on_lives_changed(value: int) -> void:
	_lives_label.text = "LIVES  %d" % value


## ステージ番号が出ていないという指摘があったため、WAVE の表示にステージも足す。
## stage_changed でも呼ぶ必要があるので、値は引数で受けず GameState から読み直す。
func _on_wave_changed(_value: int) -> void:
	var stage_part := "STAGE %d/%d" % [GameState.stage_number(), GameState.stage_count()]
	if GameState.endless:
		# 無限モードでは何周目かが実質のスコアなので、そちらを前に出す。
		_wave_label.text = "ROUND %d   %s   WAVE %d" % [GameState.endless_round, stage_part, GameState.wave]
	else:
		_wave_label.text = "%s   WAVE %d" % [stage_part, GameState.wave]


func _on_stage_changed(_index: int) -> void:
	_on_wave_changed(GameState.wave)


## 買えないタワーのボタンは押せなくする。選択中に買えなくなったら選択も解除する。
func _refresh_buttons(current_gold: int) -> void:
	for key in _buttons:
		var button := key as Button
		var data := GameState.current_tower(_buttons[key] as TowerData)
		var affordable := current_gold >= data.cost
		button.disabled = not affordable
		if not affordable and button.button_pressed:
			button.set_pressed_no_signal(false)
			if _build_manager != null and _build_manager.get_selected() == data:
				_build_manager.clear_selection()

	# 戦士は買えないときに加えて、人数がいっぱいのときも押せなくする。
	var full := _warrior_manager != null and _warrior_manager.is_full()
	for key in _warrior_buttons:
		var button := key as Button
		var data := _warrior_buttons[key] as WarriorData
		button.disabled = full or current_gold < data.cost
