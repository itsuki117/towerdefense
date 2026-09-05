extends Node
## 見た目の確認用ハーネス。ゲーム本編を読み込み、タワーを数本建てた絵を作る。
##
##     godot --path . --write-movie <出力>/f.png --resolution 1280x720 \
##           --quit-after 120 res://tools/vis_preview.tscn
##
## 通常の起動と同じ経路なので Autoload も効く（--script と違ってコンパイル順の
## 罠が無い）。撮影用なので本編のシーンには一切手を入れないこと。

## 「マス名 : TowerData」の組。撮影したい構図に合わせて足し引きする。
const PLAN := {
	"BuildSpot2": "res://resources/towers/tower_arrow.tres",
	"BuildSpot4": "res://resources/towers/tower_frost.tres",
	"BuildSpot7": "res://resources/towers/tower_arrow.tres",
	"BuildSpot9": "res://resources/towers/tower_frost.tres",
}


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame

	GameState.gold = 9999
	var manager: BuildManager = main.get_node(^"BuildManager")
	# A* の確認は「何も建っていない状態」から始めたいので、既定の設置は飛ばす。
	var plan: Dictionary = {} if "astar" in OS.get_cmdline_user_args() else PLAN
	for spot_name in plan:
		var spot := main.get_node_or_null(NodePath("Level/BuildSpots/%s" % spot_name)) as BuildSpot
		if spot == null:
			push_warning("VisPreview: マスが見つからない: %s" % spot_name)
			continue
		manager.select_tower(load(plan[spot_name]))
		manager._try_build(spot)
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

	_report_stage(main)
	# `-- stage3` のように番号を付けると、そのステージに着くまで進める。
	var target := _target_stage()
	if target > GameState.stage_number():
		await _advance_stage(main)


## 分かれ道で A* が枝を選び直すかを確かめる。
##
## ステージ 3 は 2 本の枝が同じ長さなので、何も建っていなければどちらでもよい。
## 片方だけをタワーで守ると、そちらのコストが上がってもう片方が選ばれるはず。
func _check_astar(main: Node) -> void:
	var level: Level = main.get_node(^"Level")
	var graph := level.graph
	if graph == null or graph.route.edges.size() < 8:
		print("VisPreview: 分岐のあるステージではありません")
		return
	const FORK := 2
	print("VisPreview: 分岐点 %d から次 = %d（枝A=3 / 枝B=5）コスト A=%.1f B=%.1f" % [
		FORK, graph.next_node(FORK),
		graph.edge_cost(graph.edge_between(2, 3)) + graph.edge_cost(graph.edge_between(3, 4)),
		graph.edge_cost(graph.edge_between(2, 5)) + graph.edge_cost(graph.edge_between(5, 4)),
	])

	var manager: BuildManager = main.get_node(^"BuildManager")
	var data := load("res://resources/towers/tower_arrow.tres")
	for spot_name in ["BuildSpot5", "BuildSpot6"]:
		var spot := main.get_node_or_null(NodePath("Level/BuildSpots/%s" % spot_name)) as BuildSpot
		if spot == null:
			continue
		manager.select_tower(data)
		manager._try_build(spot)
	manager.clear_selection()

	print("VisPreview: 枝Aを守った後の次 = %d、コスト A=%.1f B=%.1f" % [
		graph.next_node(FORK),
		graph.edge_cost(graph.edge_between(2, 3)) + graph.edge_cost(graph.edge_between(3, 4)),
		graph.edge_cost(graph.edge_between(2, 5)) + graph.edge_cost(graph.edge_between(5, 4)),
	])


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
	var spots := main.get_node(^"Level/BuildSpots")
	print("VisPreview: ステージ %d「%s」節=%d 辺=%d マス=%d 所持=%d ライフ=%d" % [
		GameState.stage_number(), GameState.current_stage().display_name,
		level.graph.node_count(), level.graph.route.edges.size(),
		spots.get_child_count(), GameState.gold, GameState.lives,
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
