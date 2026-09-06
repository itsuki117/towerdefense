class_name StageData
extends Resource
## ステージ 1 つぶんのデータ。resources/stages/stage_XX.tres が実データ。
##
## 道も設置マスもシーンに直置きせずここに持つ。ステージごとに違うのは
## 「道の形・設置マスの位置・ウェーブ構成」だけなので、シーンは 1 つで足りる。
##
## 地形・道のリボン・小物は起動時に道と設置マスを読んで自分を組み立て直すため、
## ステージごとに見た目を作り込む必要は無い。

@export var display_name: String = "ステージ"
## 敵が通る道。
## 置けるマスはこの道と地形から機械的に割り出すので、座標は持たない (BuildGrid)。
@export var route: RouteData
## WaveData の配列。型付き配列にしないのは WaveData.entries と同じ理由。
@export var waves: Array = []
## このステージの開始ライフ。ステージごとに仕切り直す。
@export var lives: int = 20
## クリアで入るゴールド。インターバルで強化を買う原資になる。
@export var clear_reward: int = 80
