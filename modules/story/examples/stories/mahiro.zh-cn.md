```gdscript
# This is a gdscript code comment, not header.
var tire = 50
var mahiro_favorability = 70
```

![transition: fadein](../assets/room.svg)

> 主角结束了一天的疲劳

真尋@happy: [audio:../assets/mahiro_voice.wav]欢迎回来！先吃饭？先洗澡？还是说………[wait:3s]**要・选・我**？

`if tire < 80:`

	- 先吃饭
		真尋: 饭已经准备好啦，今天的菜单是……[i]锵锵——画了爱心的蛋包饭！

		![popup](../assets/omelette.svg)

	- 去洗澡
		`if mahiro_favorability >= 80:`
			真尋: 那……要不要一起洗？
		`else:`
			真尋: 洗澡水已经放好了。累的话就慢慢泡一会儿吧。

	- 当然选真寻酱
		`if mahiro_favorability >= 90:`
			真尋@happy: 真拿你没办法……那就到这边来吧。
			>>[まひろちゃんにします](mahiro_h.md)
		`elif mahiro_favorability >= 60:`
			真尋: 不行啦，我只是开个玩笑。
		`else:`
			真尋: ……你是在开玩笑，对吧？
			`mahiro_favorability -= 20`

`else:`

	- 太累了，想睡觉
		真尋: 嗯。今天就早点休息吧。晚安。
