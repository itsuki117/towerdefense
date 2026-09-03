extends SceneTree
## バランス確認用のシミュレータ。8 波を通しで走らせて結果を出す。
##
##     godot --headless --path . --script tools/balance_sim.gd -- --towers 3
##     godot --headless --path . --script tools/balance_sim.gd -- --towers 99 --frost-every 0
##
## --towers      建てる上限。3 なら「3本しか建てない下手なプレイヤー」、
##               99 なら「置けるだけ置く上手なプレイヤー」の想定。
## --frost-every 何本に1本を減速砲にするか。0 なら通常砲だけ。
##               通常砲だけの結果と比べると、減速砲を混ぜる価値が測れる。
##
## 速度は physics_ticks_per_second と time_scale を同じ倍率で上げて稼ぐ。
## こうすると 1 ステップあたりの delta が通常プレイと同じままなので、
## 弾の飛び方や減速の掛かり方を歪めずに早送りできる。
##
## 注意: 型注釈で BuildManager など GameState を参照するスクリプトの型名を
## 使わないこと（--script は Autoload 登録前にコンパイルされる）。

const SPEEDUP := 8
const BASE_TICKS := 60
## 建て直しを検討する間隔（ゲーム内秒）。
const BUILD_INTERVAL := 1.0
## 何波ぶんか走らせても終わらなければ打ち切る（ゲーム内秒）。
const TIMEOUT_SECONDS := 900.0

const ARROW := "res://resources/towers/tower_arrow.tres"
const FROST := "res://resources/towers/tower_frost.tres"

var _max_towers := 99
var _frost_every := 3
var _game_state: Node = null
var _manager: Node = null
var _spots: Array = []
var _built := 0
var _elapsed := 0.0
var _next_build_check := 0.0
var _peak_enemies := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--towers")
	if index >= 0 and index + 1 < args.size():
		_max_towers = int(args[index + 1])
	index = args.find("--frost-every")
	if index >= 0 and index + 1 < args.size():
		_frost_every = int(args[index + 1])

	Engine.physics_ticks_per_second = BASE_TICKS * SPEEDUP
	Engine.time_scale = float(SPEEDUP)

	root.add_child(load("res://scenes/main.tscn").instantiate())

	_game_state = root.get_node_or_null(^"GameState")
	_manager = root.get_node_or_null(^"Main/BuildManager")
	var holder := root.get_node_or_null(^"Main/Level/BuildSpots")
	_spots = holder.get_children()

	print("=== SIM START (towers<=%d, spots=%d) ===" % [_max_towers, _spots.size()])


func _process(delta: float) -> bool:
	# time_scale が掛かった値が来るので、そのままゲーム内時間として使える。
	_elapsed += delta
	_peak_enemies = maxi(_peak_enemies, get_nodes_in_group(&"enemy").size())

	if _elapsed >= _next_build_check:
		_next_build_check = _elapsed + BUILD_INTERVAL
		_try_build_one()

	var result: int = _game_state.result
	if result != 0:
		_report("WON" if result == 1 else "LOST")
		return true
	if _elapsed > TIMEOUT_SECONDS:
		_report("TIMEOUT")
		return true
	return false


## 空きマスがあり、買えるなら 1 本建てる。
func _try_build_one() -> void:
	if _built >= _max_towers:
		return
	var use_frost := _frost_every > 0 and _built % _frost_every == _frost_every - 1
	var data := load(FROST if use_frost else ARROW)
	if _game_state.gold < data.cost:
		return
	for spot in _spots:
		if spot.call(&"is_occupied"):
			continue
		_manager.call(&"select_tower", data)
		_manager.call(&"_try_build", spot)
		_built += 1
		print("[%6.1fs] wave %d: %s を建てた (%d 本目, 残り %d G)" % [
			_elapsed, _game_state.wave, data.display_name, _built, _game_state.gold,
		])
		return


func _report(outcome: String) -> void:
	print("=== SIM RESULT: %s ===" % outcome)
	print("到達ウェーブ = %d / 8" % _game_state.wave)
	print("残りライフ   = %d / 20" % _game_state.lives)
	print("建てた本数   = %d" % _built)
	print("所持ゴールド = %d" % _game_state.gold)
	print("同時に出た敵の最大数 = %d" % _peak_enemies)
	print("経過ゲーム内時間 = %.1f 秒" % _elapsed)
