class_name WaveManager
extends Node
## 波の進行と敵のスポーンを管理する。
##
## 波の中身はコードではなく resources/waves/wave_XX.tres が持つ。
## ここは「データを読んで、待って、出す」だけに徹する。
## 波の流れは await でそのまま手続きとして書けるので、状態機械を持たない。

## 次の波を待っている間の残り秒数が変わった。待っていないときは -1 を流す。
signal countdown_changed(seconds_left: float)

## 「湧き切ったか」「全滅したか」を見に行く間隔 (秒)。
const POLL_INTERVAL := 0.1

@export var enemy_scene: PackedScene
## WaveData の配列。**空ならステージのデータ (StageData.waves) を使う。**
## シーンに直接並べるのはツールから差し替えたいときだけ。
## 型付き配列にしないのは WaveData の entries と同じ理由。
@export var waves: Array = []
@export var path_node: NodePath
@export var auto_start: bool = true
## ゲーム開始から第 1 波までの猶予 (秒)。
@export_range(0.0, 20.0, 0.5) var first_wave_delay: float = 3.0

var _path: Path3D = null
var _running: bool = false
## スポーン中の WaveEntry 数。0 になったらその波の湧きは終わり。
var _active_spawners: int = 0
## 次の波までの待ち時間の最中かどうか。
var _waiting_for_next: bool = false
## プレイヤーが「次の波へ」を押した。
var _next_requested: bool = false
## 次の波までの残り秒数。待っていないときは -1。
var _countdown: float = -1.0


func _ready() -> void:
	_path = get_node_or_null(path_node) as Path3D
	if _path == null:
		push_error("WaveManager: path_node に Path3D を指定してください")
		return
	if enemy_scene == null:
		push_error("WaveManager: enemy_scene が未設定です")
		return
	if waves.is_empty():
		var stage := GameState.current_stage()
		if stage != null:
			waves = stage.waves
	if waves.is_empty():
		push_error("WaveManager: 走らせるウェーブがありません")
		return
	if auto_start:
		start()


## プレイヤーが次の波を呼ぶ。待ち時間の最中でなければ何も起きない。
##
## 押さなくても待ち時間で勝手に進むので、放置してもゲームは止まらない。
## 「早く呼べる」だけの機能にしてあるので、押さない前提のバランス検証
## (tools/balance_sim.gd) は今までと同じ経路を通る。
func request_next_wave() -> void:
	if _waiting_for_next:
		_next_requested = true


func is_waiting_for_next_wave() -> bool:
	return _waiting_for_next


## 次の波までの残り秒数。待っていないときは -1。
##
## UI は signal を購読するだけで足りるが、購読を始めた時点の値も要る。
## WaveManager の _ready は UI より先に走るので、最初の 1 回を取り逃がすため。
func get_countdown() -> float:
	return _countdown


func start() -> void:
	if _running:
		return
	_running = true
	_run_all_waves()


## 敗北したら（GameState.is_over()）どの待ちからも抜けて、以降は何も湧かせない。
func _run_all_waves() -> void:
	await _wait_for_next_wave(first_wave_delay)

	for i in waves.size():
		if GameState.is_over():
			return
		var wave := waves[i] as WaveData
		if wave == null:
			continue

		GameState.wave = i + 1
		Sfx.play(&"wave_start", -5.0)

		await _spawn_wave(wave)
		await _wait_until_field_cleared()
		if GameState.is_over():
			return

		if i < waves.size() - 1:
			await _wait_for_next_wave(wave.next_wave_delay)

	_running = false
	# 最終波まで残らず片付いた = このステージはクリア。
	# 最後のステージなら勝利、まだ先があるならインターバルへ進む。
	GameState.clear_stage()


## 次の波まで待つ。プレイヤーが呼んだら残り時間を待たずに抜ける。
func _wait_for_next_wave(seconds: float) -> void:
	_next_requested = false
	_waiting_for_next = true
	_countdown = seconds
	countdown_changed.emit(_countdown)
	while _countdown > 0.0 and not _next_requested:
		if GameState.is_over():
			break
		await _wait(POLL_INTERVAL)
		_countdown = maxf(_countdown - POLL_INTERVAL, 0.0)
		countdown_changed.emit(_countdown)
	_waiting_for_next = false
	_countdown = -1.0
	countdown_changed.emit(_countdown)


## 波に含まれる全 WaveEntry を並行に走らせ、湧き切るまで待つ。
func _spawn_wave(wave: WaveData) -> void:
	for entry_res in wave.entries:
		var entry := entry_res as WaveEntry
		if entry == null or entry.enemy_data == null:
			continue
		_active_spawners += 1
		_spawn_entry(entry)

	while _active_spawners > 0:
		if GameState.is_over():
			return
		await _wait(POLL_INTERVAL)


func _spawn_entry(entry: WaveEntry) -> void:
	await _wait(entry.start_delay)
	for i in entry.count:
		if GameState.is_over():
			break
		_spawn(entry.enemy_data)
		if i < entry.count - 1:
			await _wait(entry.spawn_interval)
	_active_spawners -= 1


func _spawn(data: EnemyData) -> void:
	var enemy := enemy_scene.instantiate() as Enemy
	if enemy == null:
		return
	# add_child より前に渡しておくと、敵の _ready で HP と見た目が確定する。
	enemy.data = data
	enemy.died.connect(_on_enemy_died)
	enemy.reached_end.connect(_on_enemy_reached_end)
	_path.add_child(enemy)


func _wait_until_field_cleared() -> void:
	while not get_tree().get_nodes_in_group(&"enemy").is_empty():
		if GameState.is_over():
			return
		await _wait(POLL_INTERVAL)


## 待ち時間は SceneTree のタイマーではなく子ノードの Timer で計る。
##
## 理由は 2 つ:
##   - process_mode を親から継承するので、ポーズ中は待ち時間も自然に止まる
##     (SceneTree.create_timer は既定でポーズを無視して進んでしまう)
##   - WaveManager が解放されるとタイマーも一緒に消えるので、リスタート後に
##     「解放済みインスタンスを再開しようとした」エラーが出ない
func _wait(seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	# Timer.start は 0 以下を受け付けないので下限を入れる。
	timer.start(maxf(seconds, 0.001))
	await timer.timeout
	timer.queue_free()


func _on_enemy_died(gold_value: int) -> void:
	GameState.add_gold(gold_value)


func _on_enemy_reached_end(damage: int) -> void:
	GameState.damage_base(damage)
