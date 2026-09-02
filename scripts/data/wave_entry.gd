class_name WaveEntry
extends Resource
## 1 波の中の「敵種 × 数 × 出現間隔」1 組ぶん。
##
## WaveData がこれを複数持つことで、1 つの波に複数の敵種を混ぜられる。

@export var enemy_data: EnemyData
## 出す数。
@export var count: int = 3
## 1 体ごとの出現間隔 (秒)。
@export_range(0.05, 5.0, 0.05) var spawn_interval: float = 1.0
## 波の開始からこの組がスポーンを始めるまでの遅延 (秒)。
## 組どうしは並行して走るので、これをずらすと敵種が混ざって出てくる。
@export_range(0.0, 10.0, 0.1) var start_delay: float = 0.0
