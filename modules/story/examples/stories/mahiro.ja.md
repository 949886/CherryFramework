```gdscript
# This is a gdscript code comment, not header.
# These fields live on the generated per-story GDScript runtime object.
var tire = 50
var mahiro_favorability = 70
```

![transition: fadein](../assets/room.svg)

> 主人公は一日の疲れを抱えながら、家に帰ってきた。

真尋@happy: [audio:../assets/mahiro_voice.wav]お帰りなさい！ご飯にします？お風呂にします？それとも………[wait:3s]**わ・た・し**？

`if tire < 80:`

	- ご飯にします
		真尋: ご飯はちゃんと用意しました、今日のメニューは...[i]ジャンジャン、ハート付きのオムライスです！

		![popup](../assets/omelette.svg)

	- お風呂する
		`if mahiro_favorability >= 80:`
			真尋: じゃ、一緒にお風呂しませんか？
		`else:`
			真尋: お風呂沸いてるよ。疲れてるなら、ゆっくり温まってください。

	- もちろん、まひろちゃんにします
		`if mahiro_favorability >= 90:`
			真尋@happy: しょうがないですね……じゃあ、こっちへ。
			>>[まひろちゃんにします](mahiro_h.md)
		`elif mahiro_favorability >= 60:`
			真尋: だめ、ただの冗談よ。
		`else:`
			真尋: …冗談、だよね？
			`mahiro_favorability -= 20`

`else:`

	- 疲れた、眠りたい
		真尋: うん。今日はもう休んで。おやすみなさい。
