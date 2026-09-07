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
	# 開発者パネルは撮影の邪魔になるので、確認するとき以外は丸ごと隠す。
	var dev_panel := main.get_node_or_null(^"UI/DevPanel") as CanvasItem
	if dev_panel != null and not "dev" in OS.get_cmdline_user_args():
		dev_panel.hide()
	var manager: BuildManager = main.get_node(^"BuildManager")
	# A* の確認は「何も建っていない状態」から始めたいので、既定の設置は飛ばす。
	# A* と戦士の確認はタワー抜きで見たい（敵が着く前に溶けてしまうため）。
	var bare := "astar" in OS.get_cmdline_user_args() \
		or "warrior" in OS.get_cmdline_user_args() \
		or "archer" in OS.get_cmdline_user_args() \
		or "tiers" in OS.get_cmdline_user_args() 		or "steer" in OS.get_cmdline_user_args()
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
	if "archer" in OS.get_cmdline_user_args():
		await _check_archers_alone(main)
	if "tiers" in OS.get_cmdline_user_args():
		await _show_tiers(main, manager)
	if "interval" in OS.get_cmdline_user_args():
		await _check_interval(main)
	if "dev" in OS.get_cmdline_user_args():
		_check_dev_panel(main)

	_report_stage(main)
	# `-- stage3` のように番号を付けると、そのステージに着くまで進める。
	var target := _target_stage()
	if target > GameState.stage_number():
		await _advance_stage(main)
		return
	if "steer" in OS.get_cmdline_user_args():
		await _check_steering(main)
	if "enemies" in OS.get_cmdline_user_args():
		await _check_enemies(main)
	if "endless" in OS.get_cmdline_user_args():
		await _check_endless(main)


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
	level.get_node(^"BuildGridView").set_cursor(free[0], true, manager.get_selected().attack_range)



## 勝利画面から無限モードへ入れるかを確かめる。
##
## 無限モードは「最後まで守り切っても終わらない」だけの仕組みなので、
## 見るのは (1) 勝利画面にボタンが出るか (2) 押すと 1 面目に戻り
## 敵の硬さの倍率が上がるか、の 2 点。
func _check_endless(main: Node) -> void:
	GameState.stage = GameState.stage_count() - 1
	GameState.clear_stage()
	await get_tree().process_frame

	var screen: Control = main.get_node(^"UI/ResultScreen")
	var button: Button = screen.get_node(^"Panel/EndlessButton")
	print("VisPreview: 勝利画面 表示=%s / 無限モードのボタン=%s（%s）" % [
		screen.visible, button.visible, button.text,
	])
	print("VisPreview: 押す前  無限=%s 周回=%d 硬さ×%.2f ステージ %d" % [
		GameState.endless, GameState.endless_round, GameState.difficulty_multiplier(),
		GameState.stage_number(),
	])
	GameState.start_endless()
	print("VisPreview: 押した後 無限=%s 周回=%d 硬さ×%.2f ステージ %d" % [
		GameState.endless, GameState.endless_round, GameState.difficulty_multiplier(),
		GameState.stage_number(),
	])
	# 1 周まわしたら硬さが上がることまで見る（advance_stage が巻き戻す）。
	for i in GameState.stage_count():
		GameState.advance_stage()
	print("VisPreview: 1 周まわした後 周回=%d 硬さ×%.2f ステージ %d" % [
		GameState.endless_round, GameState.difficulty_multiplier(), GameState.stage_number(),
	])


## 敵 4 種を並べて、見た目と装甲の効き方を確かめる。
##
## 装甲は「HP を増やす」のとは効き方が違う（1 発ごとに引かれるので、
## 弱い弾を連射するほど損）。段の違うタワーで殴って、通る量の差を出す。
func _check_enemies(main: Node) -> void:
	var waves: WaveManager = main.get_node(^"WaveManager")
	var files := ["enemy_normal", "enemy_fast", "enemy_armored", "enemy_boss"]
	var tiers := ["tower_arrow", "tower_heavy", "tower_apex"]

	print("VisPreview: --- 1 発で通るダメージ（硬さ 3.0 の波） ---")
	for file_name in files:
		var data := load("res://resources/enemies/%s.tres" % file_name) as EnemyData
		var armor := maxi(roundi(float(data.armor) * sqrt(3.0)), 0) if data.armor > 0 else 0
		var line := ""
		for tier in tiers:
			var tower := load("res://resources/towers/%s.tres" % tier) as TowerData
			line += "  %s %d→%d" % [tower.display_name, tower.damage, maxi(tower.damage - armor, 1)]
		print("VisPreview: %-14s HP %4d (×3 で %4d) / 装甲 %2d%s" % [
			data.display_name, data.max_hp, roundi(data.max_hp * 3.0), armor, line,
		])

	# 見た目の確認用に道の上へ 1 体ずつ出す。
	for file_name in files:
		waves.call(&"_spawn", load("res://resources/enemies/%s.tres" % file_name), 3.0)
		await get_tree().create_timer(1.6).timeout
	print("VisPreview: 敵 %d 体を並べた" % get_tree().get_nodes_in_group(&"enemy").size())


## 戦士で敵の流れを寄せられるかを確かめる（分かれ道のあるステージ専用）。
##
## 戦士は道の上に立つので、立っている辺のコストが上がる。片方の枝に置けば
## 敵はもう一方へ回るはず——タワーにはできない仕事なので、ここだけ別に測る。
func _check_steering(main: Node) -> void:
	var level: Level = main.get_node(^"Level")
	var graph := level.graph
	if graph == null or graph.route.edges.size() < 8:
		print("VisPreview: 分岐のあるステージではありません（-- stage3 と一緒に使う）")
		return
	var manager: WarriorManager = main.get_node(^"WarriorManager")

	_report_split(graph, "戦士なし")
	var data := load("res://resources/warriors/warrior_shield.tres")
	for i in 3:
		manager.hire(data)
	# 拠点から歩いて枝に着くまで待つ。着いた辺のコストが上がる。
	await get_tree().create_timer(8.0).timeout
	_report_split(graph, "盾兵 3 人を配置")

	for node in get_tree().get_nodes_in_group(&"warrior"):
		(node as Warrior).take_damage(99999)
	await get_tree().process_frame
	_report_split(graph, "戦士が倒れたあと")


## 開発者パネルを確かめる。押した結果が GameState に出るかまで見る。
##
## パネルは製品版（リリース書き出し）では丸ごと消えるので、
## ここで確かめられるのは開発用の実行だけ。
func _check_dev_panel(main: Node) -> void:
	var dev := main.get_node_or_null(^"UI/DevPanel")
	if dev == null:
		print("VisPreview: 開発者パネルが無い（製品版のはず）")
		return
	var panel: Control = dev.get_node(^"Panel")
	print("VisPreview: 開発者パネル ボタン=%s / 目印=%s / デバッグ実行=%s" % [
		panel.visible, (dev.get_node(^"Hint") as Control).visible, OS.is_debug_build(),
	])

	# 閉じている状態を撮ってから開く。
	await get_tree().create_timer(1.5).timeout
	# **F3 を実際に流し込む。** 直接 visible を触ると「キーで開くか」を確かめられない。
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	print("VisPreview: F3 を押したあとの表示=%s" % panel.visible)

	var before := GameState.gold
	panel.get_node(^"GoldButton").pressed.emit()
	print("VisPreview: ゴールド %d -> %d" % [before, GameState.gold])

	panel.get_node(^"InvincibleButton").pressed.emit()
	var lives := GameState.lives
	GameState.damage_base(5)
	print("VisPreview: 無敵=%s のときライフ %d -> %d" % [
		GameState.invincible, lives, GameState.lives,
	])
	panel.get_node(^"InvincibleButton").pressed.emit()

	panel.get_node(^"SpeedButton").pressed.emit()
	print("VisPreview: 早送り time_scale=%.1f" % Engine.time_scale)
	Engine.time_scale = 1.0


## インターバルの強化を確かめる。行の中身と、押したときに段が上がるかまで見る。
func _check_interval(main: Node) -> void:
	await get_tree().create_timer(0.3).timeout
	GameState.clear_stage()
	await get_tree().process_frame

	var screen: Control = main.get_node(^"UI/IntervalScreen")
	var rows := screen.get_node(^"Panel/Upgrades").get_children()
	print("VisPreview: インターバル 表示=%s ポーズ=%s 強化の行=%d 所持=%d" % [
		screen.visible, get_tree().paused, rows.size(), GameState.gold,
	])
	_print_rows(rows, "買う前")

	# 全部の行を 1 回ずつ押す。ポーズ中でもボタンが効くか（process_mode）の確認も兼ねる。
	for row in rows:
		var button: Button = row.get_child(1)
		if not button.disabled:
			button.pressed.emit()
	await get_tree().process_frame
	_print_rows(rows, "1 回ずつ買った後")

	# 買った結果が盤面のボタンにも出ているか（段が上がると名前と費用が変わる）。
	var bar := main.get_node(^"UI/HUD/BuildBar/TowerRow")
	var labels := ""
	for button in bar.get_children():
		labels += " [%s]" % (button as Button).text
	print("VisPreview: 盤面のタワーボタン%s" % labels)


func _print_rows(rows: Array, title: String) -> void:
	print("VisPreview: --- %s ---" % title)
	for row in rows:
		var button: Button = row.get_child(1)
		print("VisPreview:   %-46s %s%s" % [
			(row.get_child(0) as Label).text, button.text,
			"（押せない）" if button.disabled else "",
		])


## タワーのティアを確かめる。
##
## 前半は強化を順に買って、種類の段が入れ替わるか（＝インターバルで押す操作）。
## 後半は 5 段ぶんを一列に建てて、モデルが段ごとに変わっているかを絵で見る。
func _show_tiers(main: Node, manager: BuildManager) -> void:
	var base := load("res://resources/towers/tower_arrow.tres") as TowerData
	print("VisPreview: --- 強化の階段 ---")
	while GameState.can_upgrade_tower(base):
		var before := GameState.current_tower(base)
		var cost := before.upgrade_cost
		if not GameState.upgrade_tower(base):
			print("VisPreview: %s の強化に失敗（%d G 足りない）" % [before.display_name, cost])
			break
		var after := GameState.current_tower(base)
		print("VisPreview: %s -> %s (%d G) 段 %d / 設置 %d G / ダメージ %d / 射程 %.1f" % [
			before.display_name, after.display_name, cost,
			after.tier, after.cost, after.damage, after.attack_range,
		])
	print("VisPreview: 打ち止め = %s（残り %d G）" % [
		GameState.current_tower(base).display_name, GameState.gold,
	])

	var level := Level.find(main)
	var files := ["tower_arrow", "tower_cannon", "tower_heavy", "tower_siege", "tower_apex"]
	var line := _tier_line(level)
	for i in files.size():
		var data := load("res://resources/towers/%s.tres" % files[i]) as TowerData
		manager.select_tower(data)
		if not manager.build_at(line[i % line.size()]):
			print("VisPreview: %s を建てられなかった" % data.display_name)
	manager.clear_selection()

	# `-- tiers focus` で最上位のタワーに寄る。段が上がると図体も大きくなるので、
	# 固定の距離だと画面からはみ出す（focus_radius に合わせて伸ばしてある）。
	if "focus" in OS.get_cmdline_user_args():
		var towers := main.get_node(^"Towers")
		var camera: Camera3D = main.get_node(^"Camera3D")
		camera.call(&"focus_on", towers.get_child(towers.get_child_count() - 1))
		await get_tree().create_timer(1.0).timeout


## 5 段を並べて撮るためのマスの列。道沿いの帯の中で、同じ z が一番多い列を使う。
func _tier_line(level: Level) -> Array[Vector2i]:
	var counts: Dictionary = {}
	for cell in level.grid.cells:
		counts[cell.y] = (counts.get(cell.y, 0) as int) + 1
	var best_row := 0
	var best_count := -1
	for row in counts:
		if counts[row] > best_count:
			best_count = counts[row]
			best_row = row
	var line: Array[Vector2i] = []
	for cell in level.grid.cells:
		if cell.y == best_row:
			line.append(cell)
	line.sort_custom(func(a, b): return a.x < b.x)
	return line


## 弓兵だけを並べたときに、前列が無いせいで崩れるかを確かめる。
##
## 弓兵は足止めしないので敵に触られない——という状態を放っておくと、
## 「弓兵だけ並べるのが最適」になってしまう。すれ違いざまの反撃
## (Enemy._strike_passing) がそれを潰しているかを見る。
func _check_archers_alone(main: Node) -> void:
	var manager: WarriorManager = main.get_node(^"WarriorManager")
	var waves: WaveManager = main.get_node(^"WaveManager")
	var data := load("res://resources/warriors/warrior_archer.tres")
	for i in 3:
		manager.hire(data)
	print("VisPreview: 弓兵だけ %d 人（前列なし）" % manager.alive_count())
	waves.request_next_wave()
	await get_tree().create_timer(4.0).timeout
	waves.request_next_wave()

	for step in 4:
		await get_tree().create_timer(5.0).timeout
		print("VisPreview: %2d 秒 弓兵 %d 人 / 敵 %d 体 / ライフ %d" % [
			(step + 1) * 5, manager.alive_count(),
			get_tree().get_nodes_in_group(&"enemy").size(), GameState.lives,
		])


## 役職 3 種を 1 人ずつ雇い、それぞれが役職どおりに振る舞うかを確かめる。
##
## 見たいのは「何人生き残ったか」ではなく **役職の切り分けが効いているか**。
## 盾兵が 2 体抱えているか、弓兵が誰も掴んでいないか、を数えて出す。
func _check_warriors(main: Node) -> void:
	var manager: WarriorManager = main.get_node(^"WarriorManager")
	var waves: WaveManager = main.get_node(^"WaveManager")
	for name in ["warrior_shield", "warrior_guard", "warrior_archer"]:
		var data := load("res://resources/warriors/%s.tres" % name)
		print("VisPreview: %s を雇用 %s（残り %d G）" % [
			data.display_name, manager.hire(data), GameState.gold,
		])
	# 波を 2 つ重ねる。1 波目だけだと敵が 1 体ずつ来るので、
	# 盾兵が 2 体まとめて抱えている場面が出ない。
	waves.request_next_wave()
	await get_tree().create_timer(4.0).timeout
	waves.request_next_wave()

	for step in 4:
		await get_tree().create_timer(5.0).timeout
		var enemies := get_tree().get_nodes_in_group(&"enemy")
		var blocked := 0
		for node in enemies:
			if not (node as Enemy).can_be_engaged():
				blocked += 1
		var held := ""
		for node in get_tree().get_nodes_in_group(&"warrior"):
			var warrior := node as Warrior
			held += " %s %d体" % [warrior.data.display_name, warrior.held_count()]
		print("VisPreview: %2d 秒 敵 %d 体（足止め %d）/ ライフ %d /%s" % [
			(step + 1) * 5, enemies.size(), blocked, GameState.lives, held,
		])
