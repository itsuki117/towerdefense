class_name RouteData
extends Resource
## 敵が通る道の形。節（分岐点）と辺（区間）のグラフとして持つ。
##
## まだ分岐は使っておらず、実データはどれも「節が一列に並んだ鎖」。
## それでもグラフの形で持っているのは、分岐を足すときにデータを増やすだけで
## 済ませるため。Curve3D を 1 本だけ持つ形にすると、分岐を入れる段階で
## 保存形式ごと作り直しになる。
##
## 絵に描いた道はすべて直線と直角なので、辺の形は「節と節を結ぶ直線」で足りる。
## 曲がりの見た目は道のリボン (RoadVisual) 側で丸める。

## 節の位置。y は地面に合わせるので 0 のままでよい。
@export var nodes: PackedVector3Array = PackedVector3Array()
## 辺。つなぐ節の番号のペア。向きは持たない（どちらからでも通れる）。
@export var edges: Array[Vector2i] = []
## 敵が湧く節の番号。
@export var spawn_node: int = 0
## 守る対象（クリスタル）が置かれる節の番号。
@export var goal_node: int = 0


func spawn_position() -> Vector3:
	return nodes[spawn_node] if _has(spawn_node) else Vector3.ZERO


func goal_position() -> Vector3:
	return nodes[goal_node] if _has(goal_node) else Vector3.ZERO


## 分岐があるか（どこかの節に 3 本以上の辺が集まっているか）。
##
## 今は false になる前提だが、分岐を入れたときに「まだ対応していない経路で
## 動かしている」ことに気づけるよう、判定だけ先に持っておく。
func has_branch() -> bool:
	var degree := {}
	for edge in edges:
		degree[edge.x] = int(degree.get(edge.x, 0)) + 1
		degree[edge.y] = int(degree.get(edge.y, 0)) + 1
	for count in degree.values():
		if int(count) > 2:
			return true
	return false


## spawn から goal まで節をたどった並び。分岐が無い前提。
func chain_positions() -> PackedVector3Array:
	var result := PackedVector3Array()
	if nodes.is_empty() or edges.is_empty():
		return result

	# 節番号 -> つながっている節番号の一覧。
	var neighbours := {}
	for edge in edges:
		neighbours.get_or_add(edge.x, []).append(edge.y)
		neighbours.get_or_add(edge.y, []).append(edge.x)

	var current := spawn_node
	var previous := -1
	var visited := {}
	while _has(current) and not visited.has(current):
		visited[current] = true
		result.append(nodes[current])
		if current == goal_node:
			break
		# 来た道以外へ進む。分岐があるとここで最初の 1 本を選んでしまう。
		var next := -1
		for candidate in neighbours.get(current, []):
			if int(candidate) != previous:
				next = int(candidate)
				break
		if next < 0:
			break
		previous = current
		current = next
	return result


## 鎖を Curve3D にしたもの。Path3D に入れて敵を歩かせるのに使う。
func build_curve() -> Curve3D:
	var curve := Curve3D.new()
	for point in chain_positions():
		curve.add_point(point)
	return curve


## 道の全長。ウェーブの調整で「この道は長いか短いか」を測るのに使う。
func total_length() -> float:
	var length := 0.0
	for edge in edges:
		if _has(edge.x) and _has(edge.y):
			length += nodes[edge.x].distance_to(nodes[edge.y])
	return length


func _has(index: int) -> bool:
	return index >= 0 and index < nodes.size()
