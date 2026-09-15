class_name TowerData
extends Resource
## タワー 1 種類ぶんのステータス。
##
## EnemyData と同じ方針で、タワーシーンは 1 つ・差分は .tres で表現する。
##
## **ティアは .tres の鎖で持つ**（next_tier）。強化は置いた 1 本ではなく
## タワーの種類そのものに掛かるので、「今どの .tres で建てるか」を
## GameState が差し替えるだけで済む。段ごとの数値・モデル・名前は
## すべてこのファイルの中に閉じていて、コード側に段の知識が要らない。
## 鎖は tools/make_tower_tiers.py が検算してから書き出す。

## 追加効果。命中時に Projectile が適用する。
enum Effect { NONE, SLOW }

## 弾の見た目と飛び方。**当たるかどうかは変わらない**（どれも必中）ので、
## ここで選ぶのは「どう見えるか」だけ。外れが出ないからこそ、弾速も弾道も
## 演出として自由に決められる（Projectile の設計メモと同じ理由）。
enum Shot {
	BOLT,  ## 細い矢弾。水平に速く飛ぶ。
	SHELL,  ## 砲弾。山なりに飛ぶ。段が上がるほど太い。
	ORB,  ## 氷の玉。ゆっくり漂うように飛ぶ。
	BEAM,  ## レールガン。飛ばずに即着弾し、線だけが残る。
}

@export var display_name: String = "Tower"
## 鎖の何段目か（1 始まり）。表示にしか使わない。
@export var tier: int = 1
## このタワー専用のシーン。Blender で作ったモデルを持つタワーはここで指定する。
## null なら BuildManager の default_tower_scene（プリミティブ表示）が使われ、
## 見た目は body_color だけで差を付ける。
@export var tower_scene: PackedScene
## 設置コスト（ゴールド）。
@export var cost: int = 50
## 1 発あたりのダメージ。
@export var damage: int = 4
## 射程 (m)。Area3D の SphereShape3D 半径に反映される。
@export_range(1.0, 20.0, 0.5) var attack_range: float = 6.0
## 発射レート (発/秒)。
@export_range(0.1, 10.0, 0.1) var fire_rate: float = 1.5
## 弾速 (m/秒)。
@export var projectile_speed: float = 18.0
@export var effect: Effect = Effect.NONE
## effect が SLOW のときの速度倍率。0.5 なら敵の移動速度が半分になる。
@export_range(0.05, 1.0, 0.05) var slow_factor: float = 0.5
## 減速が続く秒数。effect が SLOW のときだけ意味を持つ。
@export_range(0.1, 10.0, 0.1) var slow_duration: float = 1.5
@export var body_color: Color = Color(0.85, 0.72, 0.35)
## 発射音の名前。Sfx.LIBRARY のキーを指す。
@export var shoot_sfx: StringName = &"shoot_arrow"

@export_group("弾")
## 弾の見た目と飛び方。
@export var shot: Shot = Shot.BOLT
## 弾の色。**段ごとに少しずつ変える**ための欄で、body_color とは別に持つ
## （同じ系統のタワーでも、段が上がったことが弾を見ただけで分かるようにする）。
@export var shot_color: Color = Color(1.0, 0.85, 0.4)
## 弾の大きさの倍率。段が上がるほど太くする。
@export_range(0.4, 3.0, 0.05) var shot_scale: float = 1.0
## 着弾したとき、この半径 (m) の中にいる敵も巻き込む。**0 なら単体攻撃**。
##
## 最終段（レールガン）のためだけに足した欄。effect と別に持つのは、
## 巻き込みと減速が直交するため（凍らせながら巻き込む、もありうる）。
@export_range(0.0, 6.0, 0.1) var splash_radius: float = 0.0
## 巻き込まれた敵に通るダメージの割合。狙われた 1 体は常に全部入る。
@export_range(0.0, 1.0, 0.05) var splash_falloff: float = 0.5

@export_group("ティア")
## 次の段へ上げる費用。0 なら「これ以上は無い」。
@export var upgrade_cost: int = 0
## 次の段の TowerData。null なら最終段。
@export var next_tier: TowerData
