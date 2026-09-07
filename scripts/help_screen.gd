extends Control
## 遊び方の説明。「?」ボタンでいつでも開ける。ステージ 1 の開始時だけ自動で開く。
##
## **自動表示はツリーを止めない。** WaveManager は「押さなくても待ち時間で
## 勝手に進む」設計（auto_start / first_wave_delay）なので、ここで一括ポーズを
## 挟むと初回の待ち時間がまるごと消費されてしまい、かつ headless_check や
## vis_preview のような「main.tscn をそのまま読み込んで動かす」検証ツールが
## 誰も閉じないまま止まったツリーごと固まって壊れる（実測で踏んだ）。
## 「?」ボタンからの手動オープンだけ勝敗画面と同じくポーズする
## ——そちらはプレイヤーが自分の意思で読みに来ているので、止めても不都合が無い。
##
## **自動表示は起動につき 1 回だけ。** static var はシーンの読み直し
## （ステージ移行のたびに main.tscn ごと作り直す）をまたいで残るので、
## 「もう一度あそぶ」で周回をやり直しても再度は出さない
## （reset_run() で stage は 0 に戻るが、遊び方はもう知っている）。
static var _shown_once: bool = false

@onready var _close_button: Button = $Panel/CloseButton


func _ready() -> void:
	hide()
	_close_button.pressed.connect(_on_close_pressed)
	# ステージ 1 の最初のフレームだけ自動で開く。
	# call_deferred にしているのは、HUD 側の接続が終わってから出したいため。
	# tools/vis_preview.tscn は `-- モード名` を付けて main.tscn ごと読み込むので、
	# ユーザー引数が付いているときは検証用と見なして自動表示をしない
	# （出しっぱなしだと撮りたい画面がずっと隠れてしまう）。
	if not _shown_once and OS.get_cmdline_user_args().is_empty() \
			and GameState.stage == 0 and GameState.wave == 0:
		_shown_once = true
		_show_without_pausing.call_deferred()


## 「?」ボタンから開く。プレイヤーが自分から読みに来ているので、
## 勝敗画面・インターバル画面と同じくここは止めてよい。
func open() -> void:
	show()
	_close_button.grab_focus()
	get_tree().paused = true


func _show_without_pausing() -> void:
	show()
	_close_button.grab_focus()


func _on_close_pressed() -> void:
	get_tree().paused = false
	hide()
