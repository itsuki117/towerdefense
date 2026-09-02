class_name WaveData
extends Resource
## 1 波ぶんの構成。resources/waves/wave_XX.tres が実データ。

## WaveEntry の配列。
## 型付き配列 (Array[WaveEntry]) にすると .tres のシリアライズ形式が複雑になるため、
## ここでは素の Array で持ち、読み出し側で WaveEntry にキャストする。
@export var entries: Array = []
## この波を殲滅してから次の波が始まるまでの待ち時間 (秒)。
@export_range(0.0, 30.0, 0.5) var next_wave_delay: float = 5.0
