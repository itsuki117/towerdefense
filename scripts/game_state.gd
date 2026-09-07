extends Node
## ゲーム全体の状態を 1 か所に集約する Autoload。
##
## 状態を持つのはここだけにして、変化は signal で外に流す。
## UI やマネージャは「購読するだけ」になり、参照方向が一方向に保たれる。

signal gold_changed(new_value: int)
signal lives_changed(new_value: int)
signal wave_changed(index: int)
signal stage_changed(index: int)
## ステージを 1 つ守り切った。次がある場合だけ流れる（最後なら game_won）。
signal stage_cleared(stage_number: int, reward: int)
signal game_over
signal game_won
## 強化を買った。UI はここを購読して表示を作り直す。
signal upgrades_changed

enum Result { PLAYING, WON, LOST }

const START_GOLD := 1100
## ステージのデータが読めなかったときに使う保険の値。
const START_LIVES := 20
const CAMPAIGN_PATH := "res://resources/campaign.tres"

## 武器強化の段数の上限と、1 段ごとの費用。
const WEAPON_MAX_LEVEL := 3
const WEAPON_COSTS := [480, 800, 1280]
## 無限モードで 1 周ごとに敵の硬さへ掛かる増分。
##
## ステージの中身（波・道・報酬）は作り直さず、**硬さの倍率だけを乗せて周回する**。
## 波を無限に用意することはできないし、用意しても後半は数の暴力にしかならない。
## 硬さなら 1 つの数値で伸ばせて、獲得ゴールドは増えないので稼ぎも自然に締まる。
const ENDLESS_STEP := 0.35

## 1 段ごとにダメージが何割増えるか。
##
## 一律 +N ではなく割合にしてある。素のダメージが小さい盾兵（2）だけが
## 不釣り合いに強くなってしまい、役職の切り分けが崩れるため。
const WEAPON_STEP := 0.3

## 開発者パネル専用。ライフを減らさない。製品版ではパネルごと消えるので
## （scripts/dev_panel.gd）、ここが true になることは無い。
var invincible: bool = false

var result: Result = Result.PLAYING
## 周回するステージの並び。
var campaign: CampaignData = null

## 種類ごとの今のティア。鍵は**基準の TowerData**（UI が配列で持っているもの）で、
## 値がその種類の現在の段。周回に属する状態なので、ステージをまたいでも残る。
var tower_tiers: Dictionary = {}
## 戦士の武器強化の段。全役職に同じ割合で掛かる。
var weapon_level: int = 0

## 無限モードに入っているか。最後のステージを守り切っても終わらなくなる。
var endless: bool = false
## 無限モードで何周目か（1 始まり）。敵の硬さに効く。
var endless_round: int = 0

## 今いるステージ（0 始まり）。**周回に属する状態**なので、
## ステージを作り直しても（シーンを読み直しても）ここは残る。
var stage: int = 0:
	set(value):
		if value == stage:
			return
		stage = value
		stage_changed.emit(stage)

var gold: int = START_GOLD:
	set(value):
		value = maxi(value, 0)
		if value == gold:
			return
		gold = value
		gold_changed.emit(gold)

var lives: int = START_LIVES:
	set(value):
		value = maxi(value, 0)
		if value == lives:
			return
		lives = value
		lives_changed.emit(lives)
		if lives == 0:
			_finish(Result.LOST)

var wave: int = 0:
	set(value):
		if value == wave:
			return
		wave = value
		wave_changed.emit(wave)


func _ready() -> void:
	lives = _stage_lives()


## ステージ並びを読む。_ready を待たずに読み込むのは、Autoload の _ready と
## メインシーンの _enter_tree のどちらが先かに依存させないため。
## 呼ばれた時点で必ず用意されているほうが、初期化順の事故が起きない。
func _ensure_campaign() -> void:
	if campaign != null:
		return
	campaign = load(CAMPAIGN_PATH) as CampaignData
	if campaign == null or campaign.stages.is_empty():
		push_error("GameState: %s が読めません" % CAMPAIGN_PATH)


func stage_count() -> int:
	_ensure_campaign()
	return campaign.stages.size() if campaign != null else 0


## 画面に出す 1 始まりのステージ番号。
func stage_number() -> int:
	return stage + 1


func current_stage() -> StageData:
	_ensure_campaign()
	if campaign == null or stage < 0 or stage >= campaign.stages.size():
		return null
	return campaign.stages[stage] as StageData


func is_last_stage() -> bool:
	return stage_number() >= stage_count()


## 波の硬さに掛かる倍率。通常の周回では 1.0。
func difficulty_multiplier() -> float:
	return 1.0 + ENDLESS_STEP * float(maxi(endless_round - 1, 0))


## 勝利画面から無限モードへ入る。**ゴールドと強化は持ったまま**、
## ステージ 1 から周り直す。負けたら終わり（セーブは持たない）。
##
## **所持ゴールドは最低でも START_GOLD まで補う。** 最終ステージは
## インターバル画面（強化を買う場所）を経由せず直接勝利するので、
## 1 つ前のインターバルで強化に全額を使っていると、最終ステージの収入だけを
## 持ってタワー 0 本の盤面から無限モードを始めることになり、そのまま詰む
## （実際に報告があった）。ここは通常の周回開始と同じ前提に揃えておく。
func start_endless() -> void:
	endless = true
	endless_round = 1
	stage = 0
	gold = maxi(gold, START_GOLD)
	_reset_stage_state()


## 周回をはじめからやり直す。負けたら強化もゴールドも失う（セーブは持たない）。
func reset_run() -> void:
	stage = 0
	gold = START_GOLD
	tower_tiers.clear()
	weapon_level = 0
	endless = false
	endless_round = 0
	upgrades_changed.emit()
	_reset_stage_state()


## その種類を今どの段で建てるか。強化していなければ基準をそのまま返す。
##
## 強化は**置いた 1 本ではなく種類そのもの**に掛かる。ステージが変わると設置は
## リセットされるので、1 本に掛けても次のステージで消えてしまう。
func current_tower(base: TowerData) -> TowerData:
	if base == null:
		return null
	var current := tower_tiers.get(base) as TowerData
	return current if current != null else base


func can_upgrade_tower(base: TowerData) -> bool:
	var current := current_tower(base)
	return current != null and current.next_tier != null and current.upgrade_cost > 0


## 1 段上げる。払えない・これ以上上がらないときは false。
func upgrade_tower(base: TowerData) -> bool:
	if not can_upgrade_tower(base):
		return false
	var current := current_tower(base)
	if not spend_gold(current.upgrade_cost):
		return false
	tower_tiers[base] = current.next_tier
	upgrades_changed.emit()
	return true


## 戦士のダメージに掛かる倍率。
func weapon_multiplier() -> float:
	return 1.0 + WEAPON_STEP * float(weapon_level)


## 武器を 1 段上げる費用。これ以上上がらないなら 0。
func weapon_upgrade_cost() -> int:
	if weapon_level >= WEAPON_MAX_LEVEL:
		return 0
	return WEAPON_COSTS[weapon_level]


func upgrade_weapon() -> bool:
	var cost := weapon_upgrade_cost()
	if cost <= 0 or not spend_gold(cost):
		return false
	weapon_level += 1
	upgrades_changed.emit()
	return true


## 次のステージへ進む。ゴールドは持ち越し、ライフとウェーブは仕切り直す。
##
## 無限モードでは最後まで行ったら 1 面目へ戻り、周回数を 1 つ進める
## （＝敵が硬くなる）。
func advance_stage() -> void:
	if is_last_stage():
		if not endless:
			return
		endless_round += 1
		stage = 0
		_reset_stage_state()
		return
	stage += 1
	_reset_stage_state()


## ステージのウェーブを守り切ったときに WaveManager から呼ばれる。
## 最後のステージなら勝利、まだ先があるならインターバルへ。
func clear_stage() -> void:
	if is_over():
		return
	var data := current_stage()
	var reward: int = data.clear_reward if data != null else 0
	# 最後のステージには報酬を置いていない（そこで終わるので）。
	# 無限モードでは終わらないので、1 つ前のステージと同じだけ渡す。
	if reward <= 0 and endless and is_last_stage():
		reward = _previous_stage_reward()
	add_gold(reward)
	if is_last_stage() and not endless:
		_finish(Result.WON)
	else:
		stage_cleared.emit(stage_number(), reward)


func _previous_stage_reward() -> int:
	_ensure_campaign()
	if campaign == null or stage <= 0:
		return 0
	var previous := campaign.stages[stage - 1] as StageData
	return previous.clear_reward if previous != null else 0


## ステージごとに作り直す状態だけを戻す。ゴールドとステージ番号は触らない。
func _reset_stage_state() -> void:
	result = Result.PLAYING
	wave = 0
	lives = _stage_lives()


func _stage_lives() -> int:
	var data := current_stage()
	return data.lives if data != null else START_LIVES


func is_over() -> bool:
	return result != Result.PLAYING


## 勝敗はどちらか一度だけ。先に決まったほうが確定する
## （最終波の途中でライフが尽きたら、その後の殲滅では勝利にしない）。
func _finish(new_result: Result) -> void:
	if result != Result.PLAYING:
		return
	result = new_result
	if new_result == Result.WON:
		game_won.emit()
	else:
		game_over.emit()


func add_gold(amount: int) -> void:
	gold += amount


func can_afford(cost: int) -> bool:
	return gold >= cost


## 支払えたら true。足りなければ何も減らさず false。
func spend_gold(cost: int) -> bool:
	if not can_afford(cost):
		return false
	gold -= cost
	return true


func damage_base(amount: int) -> void:
	if invincible:
		return
	lives -= amount
