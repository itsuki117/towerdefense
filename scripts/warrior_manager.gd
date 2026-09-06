class_name WarriorManager
extends Node
## ゴールドを払って戦士を雇う。
##
## タワーと違って置く場所を選ばない（拠点から出て道を遡る）ので、
## ボタンを押した時点で生成まで済ませる。選択の状態を持たない。
##
## 倒れた戦士は戻ってこない。雇い直しもゴールドを払う＝**消耗品**にしてある。
## タワーと同じ財布から出すので、「守りに置くか、前に出すか」の選択になる。

## 同時に出せる人数。ゴールドだけで抑えると、道を塞ぐ壁になってしまう。
@export var max_alive: int = 8
@export var warrior_scene: PackedScene
@export var warriors_parent_path: NodePath

var _parent: Node3D = null
var _level: Level = null


func _ready() -> void:
	_parent = get_node_or_null(warriors_parent_path) as Node3D
	_level = Level.find(self)
	if _parent == null or warrior_scene == null:
		push_error("WarriorManager: warrior_scene / warriors_parent_path を設定してください")


func alive_count() -> int:
	return get_tree().get_nodes_in_group(&"warrior").size()


func is_full() -> bool:
	return alive_count() >= max_alive


## 1 人雇う。払えない・人数がいっぱい・盤面が無いときは false。
func hire(data: WarriorData) -> bool:
	if data == null or _parent == null or _level == null or _level.graph == null:
		return false
	if is_full():
		return false
	if not GameState.spend_gold(data.cost):
		return false

	var warrior := warrior_scene.instantiate() as Warrior
	if warrior == null:
		return false
	warrior.setup(_level.graph, data)
	_parent.add_child(warrior)
	Sfx.play(&"build", -6.0)
	return true
