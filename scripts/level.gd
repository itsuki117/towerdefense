class_name Level
extends Node3D
## StageData を読んで、道・設置マス・拠点の位置を組み立てる。
## そのステージの道グラフ (RouteGraph) を持ち、地形・道・敵・タワーへ配る。
##
## ステージごとに違うのは「道の形・設置マスの位置・ウェーブ構成」だけなので、
## シーンは 1 つで足りる。地形・道のリボン・小物は道と設置マスを読んで
## 自分を組み立て直すため、ステージごとに見た目を作り込む必要も無い。
##
## 組み立ては _ready ではなく **_enter_tree** で行う。
## _ready は子が先に走るので、Terrain と RoadVisual（どちらも _ready で
## Path3D と BuildSpots を読む）には間に合わない。_enter_tree は親が先に走る。

@export var build_spot_scene: PackedScene
@export var build_spots_path: NodePath = ^"BuildSpots"
@export var base_path: NodePath = ^"Base"

## このステージの道グラフ。子ノードは level_path 経由でここを見る。
var graph: RouteGraph = null


func _enter_tree() -> void:
	var stage := GameState.current_stage()
	if stage == null:
		push_error("Level: ステージ %d のデータが取れません（resources/campaign.tres を確認）"
			% GameState.stage_number())
		return
	if stage.route == null:
		push_error("Level: %s に道 (RouteData) が設定されていません" % stage.display_name)
		return
	graph = RouteGraph.new(stage.route)
	# どこからでも掴めるようにしておく（弾やエフェクトの置き場と同じ探し方）。
	add_to_group(&"level")

	# 拠点は道の終点に置く。ステージが変わっても守る対象の位置は道が決める。
	var base := get_node_or_null(base_path) as Node3D
	if base != null:
		base.position = stage.route.goal_position()

	_place_build_spots(stage)


## 設置マスを並べる。名前を BuildSpot1.. にしておくと、
## 検証ツール (tools/headless_check.gd) からステージ跨ぎで同じように掴める。
func _place_build_spots(stage: StageData) -> void:
	var parent := get_node_or_null(build_spots_path)
	if parent == null or build_spot_scene == null:
		push_error("Level: build_spots_path / build_spot_scene を設定してください")
		return
	for i in stage.build_spots.size():
		var spot := build_spot_scene.instantiate() as Node3D
		if spot == null:
			continue
		spot.name = "BuildSpot%d" % (i + 1)
		parent.add_child(spot)
		spot.position = stage.build_spots[i]


## 道の中心線を一定間隔で点にしたもの。
## 地形を平らに均す判定と、小物を道から避ける判定に使う。
func road_points(step: float = 0.6) -> PackedVector3Array:
	return graph.sample_points(step) if graph != null else PackedVector3Array()


## どこからでも Level を掴むための入口。
static func find(node: Node) -> Level:
	return node.get_tree().get_first_node_in_group(&"level") as Level
