extends Node
## 効果音の再生窓口 (Autoload)。
##
## 呼ぶ側は `Sfx.play(&"hit")` と名前で鳴らすだけで、AudioStreamPlayer を持たない。
## 音を差し替えたいときは LIBRARY の 1 行を書き換えれば全部の呼び出しに効く。
##
## プレイヤーを 1 台ではなくプールにしているのは、同じ音が重なったときに
## 後の音が前の音を打ち切ってしまうため（連射中の hit が途切れる）。
##
## カメラが固定の見下ろしなので、位置ごとの聞こえ方は付けていない
## （AudioStreamPlayer3D ではなく非空間の AudioStreamPlayer を使う）。
##
## 音源は tools/make_sfx.py で合成している。外から持ってこないので
## 再配布ライセンスの管理が要らない。

## 何台まで同時に鳴らせるか。撃破が重なる後半の波でも足りる数にしてある。
const POOL_SIZE := 12
## 鳴らすたびにピッチを少しずらす幅。同じ音が続くと機械的に聞こえるため。
const PITCH_JITTER := 0.06

const LIBRARY := {
	&"shoot_arrow": "res://assets/audio/shoot_arrow.wav",
	&"shoot_frost": "res://assets/audio/shoot_frost.wav",
	&"hit": "res://assets/audio/hit.wav",
	&"enemy_die": "res://assets/audio/enemy_die.wav",
	&"build": "res://assets/audio/build.wav",
	&"life_lost": "res://assets/audio/life_lost.wav",
	&"wave_start": "res://assets/audio/wave_start.wav",
	&"victory": "res://assets/audio/victory.wav",
	&"defeat": "res://assets/audio/defeat.wav",
}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
## 次に使うプレイヤー。順番に使い回す。
var _next: int = 0


func _ready() -> void:
	# 勝敗画面はツリーをポーズさせるので、ここが止まると勝敗の音が鳴らない。
	process_mode = Node.PROCESS_MODE_ALWAYS

	for key in LIBRARY:
		var stream := load(LIBRARY[key]) as AudioStream
		if stream == null:
			push_warning("Sfx: 読み込めなかった: %s" % LIBRARY[key])
			continue
		_streams[key] = stream

	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)


## 名前で鳴らす。登録されていない名前は黙って無視する
## （音が無いだけでゲームが止まる理由は無い）。
func play(sound: StringName, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null or _pool.is_empty():
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	player.play()
