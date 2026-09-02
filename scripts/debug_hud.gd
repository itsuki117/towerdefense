extends Label
## 動作確認用の暫定表示。
## ステップ4（ゴールド・タワー設置 UI）で作る本番 UI に置き換える。


func _process(_delta: float) -> void:
	text = "WAVE %d    GOLD %d    LIVES %d    ENEMIES %d" % [
		GameState.wave,
		GameState.gold,
		GameState.lives,
		get_tree().get_nodes_in_group(&"enemy").size(),
	]
