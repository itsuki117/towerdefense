class_name CampaignData
extends Resource
## 周回 1 本ぶんのステージ並び。resources/campaign.tres が実データ。
##
## ステージ数を有限にすると決めたので、順番も終端もここに素直に並べておける。
## 無限モードを足すときは「並びを生成する側」を差し替えれば済む。

## StageData の配列。型付き配列にしないのは WaveData.entries と同じ理由。
@export var stages: Array = []
