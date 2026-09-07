extends Control
## ステージ間のインターバル画面。ここで強化を買う。
##
## 勝敗画面と同じく SceneTree.paused で全部止めてから出す。
## この画面だけ process_mode = ALWAYS にしてあるので、ポーズ中でもボタンが効く。
##
## **強化は置いたタワー 1 本ではなく、タワーの種類そのものに掛かる。**
## ステージが変わると設置はリセットされるので、1 本に掛けても次で消えてしまう。
## 種類の段を上げておけば、以降そのティアで建つ。
##
## 買った内容は GameState が持つ（周回に属する状態）。負けたら消える＝セーブは無い。
##
## 「次のステージへ」でシーンを読み直す。GameState は Autoload なので
## ゴールド・ステージ番号・強化は生き残り、タワーの配置と地形だけが作り直される。

## 強化の行の横幅と、名前とボタンの間隔。
## 名前は長いので、間隔を詰めると文字がボタンにくっついて読みにくくなる。
const ROW_WIDTH := 600
const ROW_SEPARATION := 24
## 行のボタンの大きさ。
const BUTTON_SIZE := Vector2(180, 44)

## HUD と同じ TowerData の配列（鎖の 1 段目）。強化できる種類だけ行になる。
@export var tower_options: Array = []

@onready var _title: Label = $Panel/TitleLabel
@onready var _message: Label = $Panel/MessageLabel
@onready var _warning: Label = $Panel/WarningLabel
@onready var _upgrades: VBoxContainer = $Panel/Upgrades
@onready var _next_button: Button = $Panel/NextButton

## 1 行ぶんの部品。{"base": TowerData, "label": Label, "button": Button}
## base が null の行は戦士の武器強化。
var _rows: Array = []
## 直前のステージ報酬。ゴールドが動くたびに文面を作り直すので覚えておく。
var _reward: int = 0


func _ready() -> void:
	hide()
	GameState.stage_cleared.connect(_on_stage_cleared)
	GameState.upgrades_changed.connect(_refresh)
	GameState.gold_changed.connect(_on_gold_changed)
	_next_button.pressed.connect(_on_next_pressed)
	_build_rows()
	_refresh()


## 強化できるものだけを行にする。
##
## 鎖を持たない種類（フロストタワー）は「最大」と出しても意味が無いので出さない。
## 買えないものが並んでいると、買えるものを探す手間が増えるだけになる。
func _build_rows() -> void:
	for option in tower_options:
		var base := option as TowerData
		if base != null and base.next_tier != null:
			_rows.append(_add_row(base))
	_rows.append(_add_row(null))


func _add_row(base: TowerData) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	row.add_theme_constant_override(&"separation", ROW_SEPARATION)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 17)
	row.add_child(label)

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = BUTTON_SIZE
	button.pressed.connect(_on_upgrade_pressed.bind(base))
	row.add_child(button)

	_upgrades.add_child(row)
	return {"base": base, "label": label, "button": button}


func _on_upgrade_pressed(base: TowerData) -> void:
	var bought := GameState.upgrade_weapon() if base == null else GameState.upgrade_tower(base)
	if bought:
		Sfx.play(&"build", -3.0)


func _on_gold_changed(_value: int) -> void:
	_refresh()


func _refresh() -> void:
	for row in _rows:
		var base := row["base"] as TowerData
		if base == null:
			_refresh_weapon_row(row["label"] as Label, row["button"] as Button)
		else:
			_refresh_tower_row(base, row["label"] as Label, row["button"] as Button)
	_refresh_message()


func _refresh_tower_row(base: TowerData, label: Label, button: Button) -> void:
	var current := GameState.current_tower(base)
	label.text = "%s   段 %d/%d   ダメージ %d ／ 射程 %.1f" % [
		current.display_name, current.tier, _last_tier(base), current.damage,
		current.attack_range,
	]
	if not GameState.can_upgrade_tower(base):
		button.text = "最大"
		button.disabled = true
		return
	button.text = "%s へ  %d G" % [current.next_tier.display_name, current.upgrade_cost]
	button.disabled = not GameState.can_afford(current.upgrade_cost)


func _refresh_weapon_row(label: Label, button: Button) -> void:
	label.text = "戦士の武器   Lv %d/%d   ダメージ ×%.1f" % [
		GameState.weapon_level, GameState.WEAPON_MAX_LEVEL, GameState.weapon_multiplier(),
	]
	var cost := GameState.weapon_upgrade_cost()
	if cost <= 0:
		button.text = "最大"
		button.disabled = true
		return
	button.text = "Lv %d へ  %d G" % [GameState.weapon_level + 1, cost]
	button.disabled = not GameState.can_afford(cost)


## 鎖の最終段の番号。「段 2/5」の分母に使う。
func _last_tier(base: TowerData) -> int:
	var last := base
	while last.next_tier != null:
		last = last.next_tier
	return last.tier


func _refresh_message() -> void:
	_message.text = "報酬 +%d G   所持 %d G" % [_reward, GameState.gold]
	_refresh_warning()


## タワーは次のステージで全部消える（§16.4-2 の仕様）。それを知らずに強化へ
## 全額を使うと、次のステージをタワー 0 本で迎えて詰む——という報告があったため、
## 「今のゴールドで一番安いタワーすら建たない」ときだけ警告を出す。
func _refresh_warning() -> void:
	var cheapest := _cheapest_tower_cost()
	if cheapest < 0 or GameState.gold >= cheapest:
		_warning.hide()
		return
	_warning.text = "⚠ タワーは次のステージで一新されます。このままだと 1 本も建てられません（最安 %d G）" % cheapest
	_warning.show()


func _cheapest_tower_cost() -> int:
	var cheapest := -1
	for option in tower_options:
		var base := option as TowerData
		if base == null:
			continue
		var cost := GameState.current_tower(base).cost
		if cheapest < 0 or cost < cheapest:
			cheapest = cost
	return cheapest


func _on_stage_cleared(stage_number: int, reward: int) -> void:
	_reward = reward
	_title.text = "STAGE %d CLEAR" % stage_number
	if GameState.endless:
		_title.text += "  （%d 周目）" % GameState.endless_round
	# 無限モードで最後のステージを守り切ったときは 1 面目へ戻る。
	var next_index := 0 if GameState.is_last_stage() else GameState.stage + 1
	var next_stage := GameState.campaign.stages[next_index] as StageData
	if next_stage != null:
		_next_button.text = "次へ: %s" % next_stage.display_name
	_refresh()
	show()
	_next_button.grab_focus()
	get_tree().paused = true
	Sfx.play(&"victory", -4.0)


func _on_next_pressed() -> void:
	get_tree().paused = false
	GameState.advance_stage()
	# 自分自身を含むシーンを作り直すので、フレーム境界まで遅らせる。
	get_tree().call_deferred(&"reload_current_scene")
