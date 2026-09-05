class_name WarriorData
extends Resource
## 自軍ユニット 1 種類ぶんのステータス。
##
## 役職の違いは **block_capacity と attack_range の 2 つ**で作る。
## HP とダメージの大小だけで分けると「強い戦士／弱い戦士」にしかならず、
## 揃える理由が生まれない。仕事のほうを分けておく。
##
## | 役職 | block_capacity | attack_range | 仕事 |
## | --- | --- | --- | --- |
## | 盾兵 | 2 | 近 | 2 体まとめて止める。倒す力はほぼ無い |
## | 衛兵 | 1 | 近 | 1 体を止めて倒す |
## | 弓兵 | 0 | 遠 | 止めない。前列の後ろから撃つ |
##
## EnemyData / TowerData と同じ方針で、シーンは 1 つ・差分は .tres で表現する。

## 見た目に持たせる装備。役職をひと目で見分けるためだけのもの。
enum Gear { SWORD, SHIELD, BOW }

@export var display_name: String = "戦士"
## ボタンの説明にそのまま出る 1 行。**数値ではなく役職の仕事**を書くこと。
@export var role_text: String = "道を塞いで敵を止める"
## 雇用コスト（ゴールド）。タワーと同じ経済から出す。
@export var cost: int = 40
@export var max_hp: int = 40
## 1 回の攻撃で与えるダメージ。
@export var damage: int = 5
## 攻撃レート (回/秒)。
@export_range(0.1, 5.0, 0.1) var attack_rate: float = 1.2
## 道の上を進む速さ (m/秒)。
@export_range(0.5, 10.0, 0.1) var move_speed: float = 3.0
## 敵をこの距離で捉える。捉えている間は足を止める。
@export_range(0.5, 8.0, 0.1) var attack_range: float = 1.1
## 同時に足止めできる敵の数。**0 なら足止めしない**（素通りさせて撃つだけ）。
@export_range(0, 3, 1) var block_capacity: int = 1
@export var gear: Gear = Gear.SWORD
## 体の大きさの倍率。役職の役割を体格でも見せる。
@export_range(0.6, 1.6, 0.05) var body_scale: float = 1.0
@export var body_color: Color = Color(0.82, 0.78, 0.68)
## 装備の色。体と分けて、シルエットの中で装備が読めるようにする。
@export var gear_color: Color = Color(0.62, 0.66, 0.72)
