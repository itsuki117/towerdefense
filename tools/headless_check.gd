extends SceneTree
## 画面を見ずに「ちゃんと組み上がって動くか」を確かめるスモークチェック。
##
##     godot --headless --path . --script tools/headless_check.gd
##
## タワーを数本建てたうえで一定フレーム走らせ、購入・撃破・減速までを確認する。
##
## 注意: このスクリプトの型注釈で BuildManager など「GameState を参照している
## スクリプト」の型名を使わないこと。--script は Autoload 登録より前に
## このスクリプトをコンパイルするため、巻き込まれた側がコンパイルに失敗し、
## 対象ノードから script が外れてしまう。ノードは untyped で受けて call() で叩く。

## タワーを建てるフレーム。
const BUILD_FRAME := 5
## 観測を終えるフレーム。60fps で 25 秒ぶん。
const END_FRAME := 1500

var _frames := 0
var _game_state: Node = null
var _slow_seen := false
var _max_enemies := 0


func _initialize() -> void:
	print("========== RESOURCES ==========")
	for path in [
		"res://resources/towers/tower_arrow.tres",
		"res://resources/towers/tower_frost.tres",
		"res://resources/enemies/enemy_normal.tres",
		"res://resources/enemies/enemy_fast.tres",
		"res://scenes/tower_arrow.tscn",
		"res://scenes/tower_frost.tscn",
		"res://assets/models/tower_basic_base.glb",
		"res://assets/models/tower_basic_turret.glb",
		"res://assets/models/tower_slow_base.glb",
		"res://assets/models/tower_slow_turret.glb",
	]:
		print("%-46s -> %s" % [path, "OK" if load(path) != null else "読み込み失敗"])

	print("\n========== TOWER SCENES ==========")
	for tower_path in [
		"res://resources/towers/tower_arrow.tres",
		"res://resources/towers/tower_frost.tres",
	]:
		var data := load(tower_path)
		print("--- %s (tower_scene=%s) ---" % [data.display_name, data.tower_scene])
		if data.tower_scene != null:
			_dump(data.tower_scene.instantiate(), 0)

	root.add_child(load("res://scenes/main.tscn").instantiate())


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == BUILD_FRAME:
		_game_state = root.get_node_or_null(^"GameState")
		_report_buttons()
		_build_towers()

	if _frames > BUILD_FRAME:
		_observe()

	if _frames < END_FRAME:
		return false

	_report_result()
	return true


func _dump(node: Node, depth: int) -> void:
	var extra := ""
	if node is Node3D:
		extra += " pos=%v" % (node as Node3D).position
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		extra += " surfaces=%d" % (mesh.get_surface_count() if mesh != null else -1)
	print("  ".repeat(depth), "- ", node.name, " (", node.get_class(), ")", extra)
	for child in node.get_children():
		_dump(child, depth + 1)


func _report_buttons() -> void:
	print("\n========== HUD BUTTONS ==========")
	var bar := root.get_node_or_null(^"Main/UI/HUD/TowerBar")
	for child in bar.get_children():
		print("button: text='%s' disabled=%s" % [child.text, child.disabled])


func _build_towers() -> void:
	print("\n========== BUILD ==========")
	var manager := root.get_node_or_null(^"Main/BuildManager")
	var level := root.get_node_or_null(^"Main/Level")
	# 盤面は道に近い順に並んでいるが、それだと出口側のマスが先に来て、
	# 短い観測時間の中では敵がそこまで届かない。湧き口に近い順に並べ直す。
	var spawn: Vector3 = level.graph.position_of(level.graph.spawn_node())
	var cells: Array = level.grid.free_cells()
	cells.sort_custom(func(a, b):
		return level.grid.placement_of(a).distance_to(spawn) 			< level.grid.placement_of(b).distance_to(spawn))
	print("置けるマス = %d（湧き口に近い順）" % cells.size())
	var plan := [
		"res://resources/towers/tower_arrow.tres",
		"res://resources/towers/tower_frost.tres",
	]
	for i in plan.size():
		var data := load(plan[i])
		var before: int = _game_state.gold
		manager.call(&"select_tower", data)
		var built: bool = manager.call(&"build_at", cells[i])
		print("%s: %s gold %d -> %d, 建った=%s" % [
			data.display_name, cells[i], before, _game_state.gold, built,
		])

	var towers := root.get_node_or_null(^"Main/Towers")
	print("建った本数 = ", towers.get_child_count())


func _observe() -> void:
	var enemies := get_nodes_in_group(&"enemy")
	_max_enemies = maxi(_max_enemies, enemies.size())
	for enemy in enemies:
		if float(enemy.get("_slow_factor")) < 1.0:
			_slow_seen = true


func _report_result() -> void:
	print("\n========== RESULT (%d フレーム後) ==========" % END_FRAME)
	print("wave  = ", _game_state.wave)
	print("gold  = ", _game_state.gold, "  (増えていれば敵を倒せている)")
	print("lives = ", _game_state.lives)
	print("同時に出た敵の最大数 = ", _max_enemies)
	print("減速が掛かった敵を観測 = ", _slow_seen)
	var projectiles := root.get_node_or_null(^"Main/Projectiles")
	print("Projectiles ノード = ", projectiles)
