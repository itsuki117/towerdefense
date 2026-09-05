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

enum Result { PLAYING, WON, LOST }

const START_GOLD := 120
## ステージのデータが読めなかったときに使う保険の値。
const START_LIVES := 20
const CAMPAIGN_PATH := "res://resources/campaign.tres"

var result: Result = Result.PLAYING
## 周回するステージの並び。
var campaign: CampaignData = null

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


## 周回をはじめからやり直す。負けたら強化もゴールドも失う（セーブは持たない）。
func reset_run() -> void:
	stage = 0
	gold = START_GOLD
	_reset_stage_state()


## 次のステージへ進む。ゴールドは持ち越し、ライフとウェーブは仕切り直す。
func advance_stage() -> void:
	if is_last_stage():
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
	add_gold(reward)
	if is_last_stage():
		_finish(Result.WON)
	else:
		stage_cleared.emit(stage_number(), reward)


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
	lives -= amount
