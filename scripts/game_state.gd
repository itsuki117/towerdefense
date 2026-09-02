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

const START_GOLD := 120
const START_LIVES := 20

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
			game_over.emit()

var wave: int = 0:
	set(value):
		if value == wave:
			return
		wave = value
		wave_changed.emit(wave)


func reset() -> void:
	gold = START_GOLD
	lives = START_LIVES
	wave = 0


func add_gold(amount: int) -> void:
	gold += amount


func damage_base(amount: int) -> void:
	lives -= amount
