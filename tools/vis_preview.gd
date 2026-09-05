extends Node
## 見た目の確認用ハーネス。ゲーム本編を読み込み、タワーを数本建てた絵を作る。
##
##     godot --path . --write-movie <出力>/f.png --resolution 1280x720 \
##           --quit-after 120 res://tools/vis_preview.tscn
##
## 通常の起動と同じ経路なので Autoload も効く（--script と違ってコンパイル順の
## 罠が無い）。撮影用なので本編のシーンには一切手を入れないこと。

const ARROW := "res://resources/towers/tower_arrow.tres"
const FROST := "res://resources/towers/tower_frost.tres"
## 撮影用に建てる本数と、何本に 1 本を減速砲にするか。
## 盤面は道に近い順に並んでいるので、上から順に建てれば道沿いに散らばる。
const PREVIEW_TOWERS := 6
const PREVIEW_FROST_EVERY := 3


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame

	GameState.gold = 9999
	var manager: BuildManager = main.get_node(^"BuildManager")
	# A* の確認は「何も建っていない状態」から始めたいので、既定の設置は飛ばす。
	# A* と戦士の確認はタワー抜きで見たい（敵が着く前に溶けてしまうため）。
	var bare := "astar" in OS.get_cmdline_user_args() or "warrior" in OS.get_cmdline_user_args()
	if not bare:
		_build_preview_towers(main, manager)
	manager.clear_selection()

	# `godot ... res://tools/vis_preview.tscn -- focus` で寄りの絵を撮る。
	# 直接 focus_on() を呼ばずクリックを流し込むのは、レイヤーや入力の
	# 横取りまで含めて「本当にクリックで寄れるか」を確かめたいため。
	if "focus" in OS.get_cmdline_user_args():
		await _click_tower(main)
	if "wave" in OS.get_cmdline_user_args():
		await _press_next_wave(main)
	if "fx" in OS.get_cmdline_user_args():
		_show_bursts(main)
	if "astar" in OS.get_cmdline_user_args():
		_check_astar(main)
	if "grid" in OS.get_cmdline_user_args():
		await _show_grid(main, manager)
	if "warrior" in OS.get_cmdline_user_args():
		await _check_warriors(main)

	_report_stage(main)
	# `-- stage3` のように番号を付けると、そのステージに着くまで進める。
	var target := _target_stage()
	if target > GameState.stage_number():
		await _advance_stage(main)


## 分かれ道で敵の流れがどう分かれるかを確かめる。
##
## ステージ 3 は 2 本の枝が同じ長さなので、何も建っていなければ五分五分のはず。
## 片方だけを守れば守っていないほうへ寄り、全部守れば元の五分五分へ戻る
## （どちらも同じだけ守られているので）。
func _check_astar(main: Node) -> void:
	var level: Level = main.get_node(^"Level")
	var graph := level.graph
	if graph == null or graph.route.edges.size() < 8:
		print("VisPreview: 分岐のあるステージではありません")
		return

	_report_split(graph, "なにも建てない")
	_build_branch_towers(main, 3)
	_report_split(graph, "枝Aだけ守る")
	_build_cells(main, 60)
	_report_split(graph, "置けるだけ建てる")


## 枝 A（節 3 と 4 を結ぶあたり）の近くにだけ建てる。
func _build_branch_towers(main: Node, count: int) -> void:
	var manager: BuildManager = main.get_node(^"BuildManager")
	var level: Level = main.get_node(^"Level")
	var graph := level.graph
	var edge := graph.edge_between(2, 3)
	var built := 0
	for cell in level.grid.free_cells():
		if built >= count:
			break
		var point := level.grid.placement_of(cell)
		if graph.covered_length(edge, point, 6.0) < 3.0:
			continue
		manager.select_tower(load(ARROW))
		if manager.build_at(cell):
			built += 1
	manager.clear_selection()


## 分岐点で 400 回抽選して、どちらの枝へ何割行くかを出す。
func _report_split(graph: RouteGraph, label: String) -> void:
	const FORK := 2
	const STEM := 1
	const BRANCH_A := 3
	const BRANCH_B := 5
	var cost_a: float = graph.edge_cost(graph.edge_between(FORK, BRANCH_A)) 		+ graph.cost_to_goal(BRANCH_A)
	var cost_b: float = graph.edge_cost(graph.edge_between(FORK, BRANCH_B)) 		+ graph.cost_to_goal(BRANCH_B)

	var rolls := 400
	var to_a := 0
	for i in rolls:
		if graph.next_node(FORK, STEM) == BRANCH_A:
			to_a += 1
	print("VisPreview: %-18s コスト A=%5.1f B=%5.1f → 枝A %3d%% / 枝B %3d%%" % [
		label, cost_a, cost_b,
		roundi(100.0 * to_a / rolls), roundi(100.0 * (rolls - to_a) / rolls),
	])


## 道に近いマスから順に建てる。撮影でも A* の確認でも使う。
func _build_cells(main: Node, count: int, frost_every: int = 0, skip: int = 0) -> void:
	var manager: BuildManager = main.get_node(^"BuildManager")
	var level: Level = main.get_node(^"Level")
	var cells := level.grid.free_cells()
	var built := 0
	for i in cells.size():
		if built >= count:
			break
		if i < skip:
			continue
		var use_frost := frost_every > 0 and built % frost_every == frost_every - 1
		manager.select_tower(load(FROST if use_frost else ARROW))
		if manager.build_at(cells[i]):
			built += 1
	manager.clear_selection()


## 引数から目的のステージ番号を読む。`stage` だけなら 2 面目。
func _target_stage() -> int:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("stage"):
			continue
		var number := arg.substr(5)
		return int(number) if number.is_valid_int() else 2
	return 0


## 今のステージで何が組み上がったかを出す。道と設置マスがステージごとに
## 作り直されているかは、節とマスの数を見れば分かる。
func _report_stage(main: Node) -> void:
	var level: Level = main.get_node(^"Level")
	print("VisPreview: ステージ %d「%s」節=%d 辺=%d 置けるマス=%d 所持=%d ライフ=%d" % [
		GameState.stage_number(), GameState.current_stage().display_name,
		level.graph.node_count(), level.graph.route.edges.size(),
		level.grid.cells.size(), GameState.gold, GameState.lives,
	])


## ステージをクリアした扱いにして、インターバルから次のステージへ進める。
func _advance_stage(main: Node) -> void:
	await get_tree().create_timer(0.5).timeout
	GameState.clear_stage()
	await get_tree().process_frame
	var screen: Control = main.get_node(^"UI/IntervalScreen")
	print("VisPreview: インターバル 表示=%s ポーズ=%s 所持=%d" % [
		screen.visible, get_tree().paused, GameState.gold,
	])
	screen.get_node(^"Panel/NextButton").pressed.emit()


## エフェクトの見た目を確かめる。4 種類をタワーの手前に並べて撒き続ける。
func _show_bursts(main: Node) -> void:
	var towers := main.get_node(^"Towers")
	if towers.get_child_count() == 0:
		return
	var tower: Node3D = towers.get_child(towers.get_child_count() - 1)
	var camera: Camera3D = main.get_node(^"Camera3D")
	camera.call(&"focus_on", tower)
	var colors := [
		Color(1.0, 0.85, 0.4), Color(0.35, 0.75, 0.4),
		Color(0.85, 0.72, 0.35), Color(0.58, 0.53, 0.44),
	]
	while is_inside_tree():
		await get_tree().create_timer(0.7).timeout
		for i in 4:
			var at := tower.global_position + Vector3(-2.7 + float(i) * 1.8, 0.5, 2.2)
			Burst.spawn(main, at, i as Burst.Kind, colors[i])


## 「次の波へ」を押して、待ち時間を飛ばして波が始まるかを確かめる。
func _press_next_wave(main: Node) -> void:
	var manager: WaveManager = main.get_node(^"WaveManager")
	var button: Button = main.get_node(^"UI/HUD/NextWaveButton")
	print("VisPreview: 待ち中=%s disabled=%s 文言=%s" % [
		manager.is_waiting_for_next_wave(), button.disabled, button.text,
	])
	var before := GameState.wave
	button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	print("VisPreview: 押した後 wave %d -> %d（待ち中=%s 文言=%s）" % [
		before, GameState.wave, manager.is_waiting_for_next_wave(), button.text,
	])


func _click_tower(main: Node) -> void:
	var towers := main.get_node(^"Towers")
	if towers.get_child_count() == 0:
		return
	var camera: Camera3D = main.get_node(^"Camera3D")
	var tower: Node3D = towers.get_child(towers.get_child_count() - 1)
	var screen := camera.unproject_position(tower.global_position + Vector3.UP * 0.6)

	Input.warp_mouse(screen)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen
	Input.parse_input_event(press)
	await get_tree().process_frame
	# 入力はフレームの頭で処理されるので、1 フレーム待たないと結果が読めない。
	await get_tree().process_frame
	print("VisPreview: クリック位置=%v 寄っているか=%s" % [screen, camera.call(&"is_focused")])


func _build_preview_towers(main: Node, _manager: BuildManager) -> void:
	_build_cells(main, PREVIEW_TOWERS, PREVIEW_FROST_EVERY)


## タワーを選んだ状態にして、マウスを 1 マスに乗せる。
## 盤面の見え方（置けるマスとカーソル）を撮るためのモード。
func _show_grid(main: Node, manager: BuildManager) -> void:
	var level: Level = main.get_node(^"Level")
	var camera: Camera3D = main.get_node(^"Camera3D")
	manager.select_tower(load(ARROW))
	var free := level.grid.free_cells()
	if free.is_empty():
		return
	# 道沿いの空きマスにカーソルを合わせる（先頭は道にいちばん近いマス）。
	var target := camera.unproject_position(level.grid.placement_of(free[0]))
	Input.warp_mouse(target)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("VisPreview: 盤面 置ける=%d 空き=%d / カーソル狙い=%v 実際=%v 乗っている=%s" % [
		level.grid.cells.size(), free.size(), target,
		manager.get_viewport().get_mouse_position(), manager._has_hover,
	])
	# 撮影中は OS 側のカーソルが戻ってきて hover が外れることがあるので、
	# 当たり判定の更新を止めてカーソルを固定する。
	manager.set_physics_process(false)
	level.get_node(^"BuildGridView").set_cursor(free[0], true)



## 戦士が拠点から出て、敵を足止めするかを確かめる。
func _check_warriors(main: Node) -> void:
	var manager: WarriorManager = main.get_node(^"WarriorManager")
	var waves: WaveManager = main.get_node(^"WaveManager")
	var data := load("res://resources/warriors/warrior_guard.tres")
	for i in 3:
		manager.hire(data)
	print("VisPreview: 雇用 %d 人 / 上限 %d / 所持 %d" % [
		manager.alive_count(), manager.max_alive, GameState.gold,
	])
	waves.request_next_wave()

	for step in 3:
		await get_tree().create_timer(5.0).timeout
		var enemies := get_tree().get_nodes_in_group(&"enemy")
		var blocked := 0
		for node in enemies:
			if not (node as Enemy).can_be_engaged():
				blocked += 1
		print("VisPreview: %2d 秒 戦士 %d 人 / 敵 %d 体（足止め %d）/ ライフ %d" % [
			(step + 1) * 5, manager.alive_count(), enemies.size(), blocked, GameState.lives,
		])
