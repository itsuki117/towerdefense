class_name WaveManager
extends Node
## 波の進行と敵のスポーンを管理する。
##
## 波の中身はコードではなく resources/waves/wave_XX.tres が持つ。
## ここは「データを読んで、待って、出す」だけに徹する。
## 波の流れは await でそのまま手続きとして書けるので、状態機械を持たない。

signal wave_started(index: int)
signal all_waves_cleared

@export var enemy_scene: PackedScene
## WaveData の配列。型付き配列にしないのは WaveData の entries と同じ理由。
@export var waves: Array = []
@export var path_node: NodePath
@export var auto_start: bool = true
## ゲーム開始から第 1 波までの猶予 (秒)。
@export_range(0.0, 20.0, 0.5) var first_wave_delay: float = 3.0

var _path: Path3D = null
var _running: bool = false
## スポーン中の WaveEntry 数。0 になったらその波の湧きは終わり。
var _active_spawners: int = 0


func _ready() -> void:
	_path = get_node_or_null(path_node) as Path3D
	if _path == null:
		push_error("WaveManager: path_node に Path3D を指定してください")
		return
	if enemy_scene == null:
		push_error("WaveManager: enemy_scene が未設定です")
		return
	if auto_start:
		start()


func start() -> void:
	if _running:
		return
	_running = true
	_run_all_waves()


func _run_all_waves() -> void:
	await _wait(first_wave_delay)

	for i in waves.size():
		var wave := waves[i] as WaveData
		if wave == null:
			continue

		GameState.wave = i + 1
		wave_started.emit(i + 1)

		await _spawn_wave(wave)
		await _wait_until_field_cleared()

		if i < waves.size() - 1:
			await _wait(wave.next_wave_delay)

	_running = false
	all_waves_cleared.emit()


## 波に含まれる全 WaveEntry を並行に走らせ、湧き切るまで待つ。
func _spawn_wave(wave: WaveData) -> void:
	for entry_res in wave.entries:
		var entry := entry_res as WaveEntry
		if entry == null or entry.enemy_data == null:
			continue
		_active_spawners += 1
		_spawn_entry(entry)

	while _active_spawners > 0:
		await get_tree().process_frame


func _spawn_entry(entry: WaveEntry) -> void:
	await _wait(entry.start_delay)
	for i in entry.count:
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
		await get_tree().create_timer(0.25).timeout


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(seconds).timeout


func _on_enemy_died(gold_value: int) -> void:
	GameState.add_gold(gold_value)


func _on_enemy_reached_end(damage: int) -> void:
	GameState.damage_base(damage)
