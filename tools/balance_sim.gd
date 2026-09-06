extends SceneTree
## バランス確認用のシミュレータ。1 ステージ、または周回を通しで走らせて結果を出す。
##
##     godot --headless --path . --script tools/balance_sim.gd -- --towers 3
##     godot --headless --path . --script tools/balance_sim.gd -- --towers 99 --frost-every 0
##     godot --headless --path . --script tools/balance_sim.gd -- --towers 3 --tier 3
##     godot --headless --path . --script tools/balance_sim.gd -- --campaign --warriors 3
##
## --towers      建てる上限。3 なら「3本しか建てない下手なプレイヤー」、
##               99 なら「置けるだけ置く上手なプレイヤー」の想定。
## --frost-every 何本に1本を減速砲にするか。0 なら通常砲だけ。
##               通常砲だけの結果と比べると、減速砲を混ぜる価値が測れる。
## --tier        アロータワーの段（1〜5）を最初から上げておく。**費用は払わない**ので、
##               「その段の火力だけ」を測れる。--campaign と混ぜると意味が薄れる。
## --warriors    同時に保つ戦士の人数（上限 8）。倒れたら雇い直す。
##               盾兵→衛兵→弓兵の順に回す。0 なら雇わない。
## --stage       いきなりそのステージから始める（1 始まり）。1 面ずつ詰めるとき用。
## --gold         開始ゴールド。--stage と組み合わせて「そこまで貯めて来た」を作る。
## --campaign    ステージ 1 から最後まで通しで走らせる。インターバルでは
##               --upgrade の方針で強化を買い、ステージを作り直して続ける。
## --endless     無限モードで走らせる（--campaign と一緒に使う）。周回を続け、
##               1 周ごとに敵が硬くなる。どこで力尽きるかが結果になる。
## --upgrade     周回中の強化方針: none / tower / weapon / balanced（既定）。
##               balanced は「安いほうから買う」＝自然に交互になる。
##
## **1 ステージだけ走らせたときの結果は、これまでの基準とそのまま比べられる。**
## 周回対応で増えたのは分岐だけで、既定の挙動は変えていない。
##
## 速度は physics_ticks_per_second と time_scale を同じ倍率で上げて稼ぐ。
## こうすると 1 ステップあたりの delta が通常プレイと同じままなので、
## 弾の飛び方や減速の掛かり方を歪めずに早送りできる。
##
## 注意: 型注釈で BuildManager など GameState を参照するスクリプトの型名を
## 使わないこと（--script は Autoload 登録前にコンパイルされる）。

const SPEEDUP := 8
const BASE_TICKS := 60
## 建て直し・雇い直しを検討する間隔（ゲーム内秒）。
const BUILD_INTERVAL := 1.0
## 1 ステージが終わらなければ打ち切る（ゲーム内秒）。
const STAGE_TIMEOUT := 900.0
## 強化に使わずに残しておくゴールド。今の段のタワー何本ぶんか。
## 全部を強化に注ぐと次のステージで 1 本も建てられなくなる。
const BUILD_RESERVE_TOWERS := 5

const ARROW := "res://resources/towers/tower_arrow.tres"
const FROST := "res://resources/towers/tower_frost.tres"
## 雇う順。盾兵で止め、衛兵で倒し、弓兵で後ろから撃つ、の 1 組。
const WARRIOR_FILES := [
	"res://resources/warriors/warrior_shield.tres",
	"res://resources/warriors/warrior_guard.tres",
	"res://resources/warriors/warrior_archer.tres",
]

var _max_towers := 99
var _frost_every := 3
var _tier := 1
var _max_warriors := 0
var _campaign := false
var _upgrade_policy := "balanced"

var _game_state: Node = null
var _manager: Node = null
var _level: Node = null
var _warrior_manager: Node = null

var _spots: Array = []
var _built := 0
var _hired := 0
## ステージを守り切ったか。次のステージがある場合は勝敗が付かないので、
## signal を拾わないとインターバルの前で回り続けてしまう。
var _stage_cleared := false
## 全体の経過と、今のステージだけの経過。打ち切りはステージごとに見る。
var _elapsed := 0.0
var _stage_elapsed := 0.0
var _next_build_check := 0.0
var _peak_enemies := 0
## 次のフレームでステージを作り直す。
var _rebuild_pending := false
## ステージごとの結果。最後にまとめて出す。
var _stage_log: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_max_towers = _int_arg(args, "--towers", _max_towers)
	_frost_every = _int_arg(args, "--frost-every", _frost_every)
	_tier = maxi(_int_arg(args, "--tier", _tier), 1)
	_max_warriors = clampi(_int_arg(args, "--warriors", 0), 0, 8)
	_campaign = args.has("--campaign")
	var endless := args.has("--endless")
	var start_stage := _int_arg(args, "--stage", 0)
	var start_gold := _int_arg(args, "--gold", 0)
	var index := args.find("--upgrade")
	if index >= 0 and index + 1 < args.size():
		_upgrade_policy = args[index + 1]

	Engine.physics_ticks_per_second = BASE_TICKS * SPEEDUP
	Engine.time_scale = float(SPEEDUP)

	_game_state = root.get_node_or_null(^"GameState")
	if _campaign:
		# 周回は必ず 1 面目から。前の実行の状態が残っていると比べられない。
		_game_state.reset_run()
	if start_stage > 0:
		_game_state.stage = clampi(start_stage - 1, 0, _game_state.stage_count() - 1)
		_game_state.lives = _game_state.current_stage().lives
	if start_gold > 0:
		_game_state.gold = start_gold
	if endless:
		_game_state.endless = true
		_game_state.endless_round = 1
	_game_state.stage_cleared.connect(_on_stage_cleared)
	_build_stage()
	_apply_tier()

	print("=== SIM START (towers<=%d, tier=%d, warriors=%d, %s) ===" % [
		_max_towers, _tier, _max_warriors,
		"campaign upgrade=%s" % _upgrade_policy if _campaign else "stage %d" % (_game_state.stage + 1),
	])


func _int_arg(args: PackedStringArray, name: String, fallback: int) -> int:
	var index := args.find(name)
	if index >= 0 and index + 1 < args.size():
		return int(args[index + 1])
	return fallback


## アロータワーの段を _tier まで進める。費用は払わない。
##
## 強化の費用まで含めると「その段に届くゴールドが貯まるか」の測定になってしまう。
## ここで見たいのは段そのものの火力なので、費用は分けて考える。
func _apply_tier() -> void:
	var base := load(ARROW)
	var current = base
	for _step in _tier - 1:
		if current.next_tier == null:
			break
		current = current.next_tier
	_game_state.tower_tiers[base] = current
	if current != base:
		print("アロータワー -> %s（段 %d / 設置 %d G / ダメージ %d）" % [
			current.display_name, current.tier, current.cost, current.damage,
		])


## ステージを 1 つ組み立てる。周回では前のステージを捨ててから呼ぶ。
func _build_stage() -> void:
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_manager = root.get_node_or_null(^"Main/BuildManager")
	_level = root.get_node_or_null(^"Main/Level")
	_warrior_manager = root.get_node_or_null(^"Main/WarriorManager")
	_spots = []
	_built = 0
	_stage_cleared = false
	_stage_elapsed = 0.0


func _process(delta: float) -> bool:
	if _rebuild_pending:
		_rebuild_pending = false
		_build_stage()
		return false

	# time_scale が掛かった値が来るので、そのままゲーム内時間として使える。
	_elapsed += delta
	_stage_elapsed += delta
	_peak_enemies = maxi(_peak_enemies, get_nodes_in_group(&"enemy").size())

	if _elapsed >= _next_build_check:
		_next_build_check = _elapsed + BUILD_INTERVAL
		_try_build_one()
		_try_hire_warriors()

	if _stage_cleared:
		_record_stage("CLEAR")
		if _campaign:
			_advance_to_next_stage()
			return false
		_report("STAGE CLEAR")
		return true
	var result: int = _game_state.result
	if result != 0:
		if result != 1:
			_record_stage("LOST")
		_report("WON" if result == 1 else "LOST")
		return true
	if _stage_elapsed > STAGE_TIMEOUT:
		_record_stage("TIMEOUT")
		_report("TIMEOUT")
		return true
	return false


func _on_stage_cleared(_stage_number: int, _reward: int) -> void:
	_stage_cleared = true


## インターバルの処理。強化を買ってから、次のステージを作り直す。
##
## IntervalScreen がツリーをポーズするので、ここで戻しておく
## （プレイヤーが「次へ」を押したときと同じ状態にする）。
func _advance_to_next_stage() -> void:
	paused = false
	_buy_upgrades()
	_game_state.advance_stage()

	var main := root.get_node_or_null(^"Main")
	if main != null:
		root.remove_child(main)
		main.queue_free()
	# 解放が済むフレーム境界まで待ってから組み立てる。
	_rebuild_pending = true


## 方針にしたがって強化を買う。
##
## balanced は**タワーの段を先に、余ったら武器**。安いほうから買う版も試したが、
## 武器 Lv1 を先に買ってタワーが 2 本減り、次のステージで押し切られた。
## 武器は戦士を抱えているぶんにしか効かないので、盤面より後になるのが妥当。
func _buy_upgrades() -> void:
	if _upgrade_policy == "none":
		return
	var base := load(ARROW)
	var bought: Array = []
	while true:
		var reserve: int = _game_state.current_tower(base).cost * BUILD_RESERVE_TOWERS
		var choice := ""
		var cost := 0
		if _upgrade_policy != "weapon" and _game_state.can_upgrade_tower(base):
			choice = "tower"
			cost = _game_state.current_tower(base).upgrade_cost
		# 戦士を雇わない走らせ方で武器を買っても、ゴールドを捨てるだけになる。
		var buys_weapon := _upgrade_policy != "tower" and _max_warriors > 0
		var weapon_cost: int = _game_state.weapon_upgrade_cost() if buys_weapon else 0
		if weapon_cost > 0 and choice == "":
			choice = "weapon"
			cost = weapon_cost
		if choice == "" or _game_state.gold - cost < reserve:
			break
		if choice == "weapon":
			if not _game_state.upgrade_weapon():
				break
			bought.append("武器 Lv%d" % _game_state.weapon_level)
		else:
			if not _game_state.upgrade_tower(base):
				break
			bought.append(_game_state.current_tower(base).display_name)
	print("[interval] 強化: %s（残り %d G）" % [
		" / ".join(PackedStringArray(bought)) if not bought.is_empty() else "なし",
		_game_state.gold,
	])


## 空いているマスを集める。盤面は道に近い順に並んでいるので、
## 上から順に建てるだけで「射程が道に届く置き方」になる。
func _collect_spots() -> void:
	_spots = _level.grid.free_cells() if _level != null and _level.grid != null else []


## 空きマスがあり、買えるなら 1 本建てる。
func _try_build_one() -> void:
	if _built >= _max_towers or _manager == null:
		return
	if _spots.is_empty():
		_collect_spots()
	var use_frost := _frost_every > 0 and _built % _frost_every == _frost_every - 1
	var data = load(FROST) if use_frost else _game_state.current_tower(load(ARROW))
	if _game_state.gold < data.cost:
		return
	_manager.call(&"select_tower", data)
	for cell in _spots:
		if not _manager.call(&"build_at", cell):
			continue
		_built += 1
		print("[%6.1fs] stage %d wave %d: %s を建てた (%d 本目, 残り %d G)" % [
			_elapsed, _game_state.stage + 1, _game_state.wave,
			data.display_name, _built, _game_state.gold,
		])
		_collect_spots()
		return


## 人数を保つ。倒れたら雇い直すので、戦士は「ゴールドを食い続ける守り」になる。
##
## **序盤は雇わない。** 開始直後に雇うと初手のタワーが 1 本減り、
## そのタワーが稼ぐはずだったゴールドまで失って雪だるま式に負ける
## （実測: ステージ 1 がライフ 17 残しの勝利 → 敗北に変わった）。
## 戦士は盤面がひととおり建ってからの増援、という扱いにしてある。
const WARRIOR_MIN_TOWERS := 6
## 戦士を雇うのはタワーを何本ぶん残せるときか。
## 序盤のゴールドはタワーに回したほうが強いので、余っているときだけ雇う。
const WARRIOR_GOLD_RESERVE := 1


func _try_hire_warriors() -> void:
	if _max_warriors <= 0 or _warrior_manager == null or _built < WARRIOR_MIN_TOWERS:
		return
	var tower_cost: int = _game_state.current_tower(load(ARROW)).cost
	while _warrior_manager.call(&"alive_count") < _max_warriors:
		if _warrior_manager.call(&"is_full"):
			return
		var data = load(WARRIOR_FILES[_hired % WARRIOR_FILES.size()])
		if _game_state.gold - data.cost < tower_cost * WARRIOR_GOLD_RESERVE:
			return
		if not _warrior_manager.call(&"hire", data):
			return
		_hired += 1


func _record_stage(outcome: String) -> void:
	var stage = _game_state.current_stage()
	var round_label := ""
	if _game_state.endless:
		round_label = "%d 周目 " % _game_state.endless_round
	_stage_log.append("%sステージ %d %-7s 波 %d/%d ／ ライフ %2d ／ タワー %2d 本 ／ %6.1f 秒 ／ 残り %d G" % [
		round_label, _game_state.stage + 1, outcome, _game_state.wave,
		stage.waves.size() if stage != null else 0,
		_game_state.lives, _built, _stage_elapsed, _game_state.gold,
	])


func _report(outcome: String) -> void:
	var stage = _game_state.current_stage()
	print("=== SIM RESULT: %s ===" % outcome)
	for line in _stage_log:
		print("  " + line)
	print("ステージ     = %d / %d (%s)" % [
		_game_state.stage + 1, _game_state.stage_count(),
		stage.display_name if stage != null else "?",
	])
	print("到達ウェーブ = %d / %d" % [
		_game_state.wave, stage.waves.size() if stage != null else 0,
	])
	print("残りライフ   = %d / %d" % [
		_game_state.lives, stage.lives if stage != null else 0,
	])
	print("空きマス数   = %d" % _spots.size())
	print("建てた本数   = %d" % _built)
	print("雇った戦士   = %d" % _hired)
	print("タワーの段   = %s" % _game_state.current_tower(load(ARROW)).display_name)
	print("武器 Lv      = %d" % _game_state.weapon_level)
	if _game_state.endless:
		print("無限モード   = %d 周目（敵の硬さ ×%.2f）" % [
			_game_state.endless_round, _game_state.difficulty_multiplier(),
		])
	print("所持ゴールド = %d" % _game_state.gold)
	print("同時に出た敵の最大数 = %d" % _peak_enemies)
	print("経過ゲーム内時間 = %.1f 秒" % _elapsed)
