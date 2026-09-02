extends Node
## ゲーム全体の状態を 1 か所に集約する Autoload。
##
## 状態を持つのはここだけにして、変化は signal で外に流す。
## UI やマネージャは「購読するだけ」になり、参照方向が一方向に保たれる。

signal gold_changed(new_value: int)
signal lives_changed(new_value: int)
signal wave_changed(index: int)
signal game_over
signal game_won

enum Result { PLAYING, WON, LOST }

const START_GOLD := 120
const START_LIVES := 20

var result: Result = Result.PLAYING

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


func reset() -> void:
	result = Result.PLAYING
	gold = START_GOLD
	lives = START_LIVES
	wave = 0


## 全ウェーブを凌ぎ切ったときに WaveManager から呼ばれる。
func win() -> void:
	_finish(Result.WON)


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
