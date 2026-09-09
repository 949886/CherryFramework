# Cherry Story

Godot 4 的 Markdown 剧情模块。入口是一个 `Story` 资源；当前实现为 `MarkdownStory`，Godot 扫描脚本类后可以直接把 `.md` 文件拖到 `StoryPlayer.story`。标准版与 .NET 版共用 GDScript 实现，不需要 Autoload。

## 开始使用

1. 在「项目 → 项目设置 → 插件」启用 Cherry。本次从导入器升级为原生资源格式，保存工作后重启一次 Godot，让原生格式加载器注册并重新扫描文件。
2. 打开 `examples/story_demo.tscn`，按 F6 体验。示例直接引用 `examples/stories/mahiro.ja.md`。
3. 自建场景时，实例化 `scenes/story_presenter.tscn`，添加挂载 `StoryPlayer` 脚本的 Node，在 Inspector 中连接 `presenter`，把入口 `.md` 拖到 `story`，然后保存场景。
4. 设置 `locale` 与 `save_path`。`autoplay` 默认开启；`locale` 留空时使用 `TranslationServer.get_locale()`。

`.md` / `.story` 通过 `MarkdownStoryFormatLoader` 原生加载为 `MarkdownStory`，使用 Godot 默认的资源选择器，不需要自定义拖放控件或先创建包装资源。场景保存外部引用：

```ini
[ext_resource type="Resource" path="res://stories/intro.story" id="1_story"]

[node name="StoryPlayer" type="Node"]
story = ExtResource("1_story")
```

文件原文保存在 `.md` / `.story` 中，`.tscn` 保存引用。加载器报告原生类型 `Resource` 和脚本类型 `MarkdownStory`；Godot 在编辑器和导出后的游戏中自动注册此全局加载器。无需 Markdown 导入步骤或 `.import` 中间资源；`.uid` 用于稳定标识文件，建议提交到版本管理。`README.md`（不区分大小写）不会被此加载器识别为故事。

升级时 Cherry 会备份并移除默认配置的旧 `cherry.story.markdown` 导入记录，将原 UID 保留到 `.uid`；备份位于项目编辑器数据目录的 `story_legacy_imports`。带有自定义命令/额外文件的旧导入设置会保留并提示先迁移到 `MarkdownStory.tres`。

## 文件命名与多语言

同时支持 `.md` 和 `.story`，两者使用相同的 Markdown 剧情语法，都会加载为 `MarkdownStory`。下文 `.md` 入口的操作也适用于 `.story`。首次添加加载器后重启 Godot，使其识别原生资源格式。

例如 `intro.ja.story`、`intro.zh-cn.story`、`intro.story` 均可直接拖到 `StoryPlayer.story`。跳转可以写 `>>[继续](chapter2.story#开场)`，也可以在 `.md` 与 `.story` 之间跳转。同目录同 ID 的翻译允许混用扩展名；同一语言若两种文件都存在，优先使用当前入口的扩展名，建议每种语言只维护一份。

文件名采用 `剧情ID.扩展名` 或 `剧情ID.语言.扩展名`，扩展名为 `md` 或 `story`：

```text
stories/
  intro.md
  intro.zh-cn.md
  intro.ja.md
  chapter2.zh-cn.md
  chapter2.ja.md
```

引用任一 `intro` 文件即可作为入口，其他语言从同目录自动发现；无需维护剧情清单。语言代码不区分大小写，`zh_CN` 与 `zh-cn` 视为同一种语言，同一种语言只保留一个文件。文件名最后一段以 Godot 支持的语言代码开头时视为语言后缀；其他点号保留在剧情 ID 中，例如 `chapter.one.zh-cn.md` 的 ID 是 `chapter.one`。

请求 `zh-cn` 时，按以下顺序查找：

1. 完整语言代码：`intro.zh-cn.md`。
2. 主语言代码：`intro.zh.md`。
3. 无语言后缀：`intro.md`。
4. 当前入口文件自身的语言版本，例如入口是 `intro.ja.md` 时回退到它。

新增或删除同目录翻译会在下次查询/播放时反映；编辑器需要完成新增文件的扫描。`player.get_available_locales()` 返回当前故事检测到的语言列表，示例据此生成语言切换按钮。

## Story 资源与播放器

| 类 / 文件 | 职责 |
| --- | --- |
| `Story` | 单个故事的 Resource 基类，定义身份、源文件、语言、跳转解析和编译接口 |
| `MarkdownStory` | 单个 Markdown 入口，依据文件名发现翻译并解析邻近故事 |
| `StoryPlayer` | 播放编排、缓存、跨文件跳转、存读档和语言切换 |
| `StoryParser` / `StoryProgram` / `StoryVM` | 编译为七条 IR 指令并执行控制流 |
| `StorySaveManager` | JSON 快照、类型校验、原子保存与位置恢复 |
| `StoryPresentation` / `StoryPresenter` | 表现层契约与默认 UI |
| `MarkdownStoryFormatLoader` | 文件类型、脚本资源类型、原生加载及运行时依赖 |
| `StoryValidator` / `editor/` | 入口检查、源行预览及导出依赖 |
| `resources/runtime_dependencies.tres` | 供选定场景导出使用的运行时脚本清单 |

正常使用只需要一个 `.md` 入口。代码中使用 `load("res://stories/intro.md") as Story` 可获得同样的外部资源。`MarkdownStory.from_file()` 是直接构造包装对象的底层工厂；也可以创建一个 `MarkdownStory.tres` 并设置 `source_file`；后者适合需要在 Resource 上独立配置命令和额外文件的情况。新增其他剧情格式时继承 `Story` 并实现其接口，播放器不依赖 Markdown 类型。

```gdscript
@onready var player: StoryPlayer = $StoryPlayer

func start_story():
    player.play()  # 播放 Inspector 中配置的入口
    # 切换到另一个入口资源：
    # player.play(load("res://stories/chapter2.ja.md") as Story)
    # 从标题开始：
    # player.play(null, "第二节")

func connect_events():
    player.story_finished.connect(func(id): print("Finished: ", id))
    player.story_failed.connect(func(message): print(message))
    player.restored.connect(func(_quality):
        print(player.save_manager.restore_quality_text()))
```

`play()` 同步返回准备结果，剧情播放异步进行；失败会保留当前播放。`story` 是配置的入口，`current_story` 是正在播放的资源，跨文件跳转后两者可以不同。`restart()` 返回配置入口。

## 剧情语法

```markdown
<!-- @sid:greeting -->
真尋@happy: 欢迎回来！[wait:500ms]今天过得怎么样？

- 打招呼
    真尋: 很高兴见到你。
- 去下一章
    >>[继续](chapter2.md#开场)
```

- 第一个位于正文前的 `gdscript` 围栏声明成员与辅助函数；后续围栏、单行反引号执行 GDScript。成员声明区不能直接写 `print()` 等执行语句。
- 支持 `姓名@状态: 台词`、`> 旁白`、缩进选项、反引号中的 `if/elif/else`。
- `# 标题` 定义跳转目标；`>>[说明](##标题)` 在当前文件内跳转。
- `>>[说明](chapter2.md)` 按命名规则查找当前目录的 chapter2。支持实际本地化文件名与相对子目录，例如 `routes/chapter2.ja.md#开场`；播放目标仍按请求的语言选择版本。
- `<!-- @sid:稳定标识 -->` 为下一条指令提供恢复锚点；对应翻译应使用相同 SID。
- `**粗体**`、`[audio:路径]`、`[wait:3s]`、`[wait:50ms]`、`[i]`、`[save]`。
- `![transition: fadein](路径)` 背景淡入；`![popup](路径)` 弹图并等待输入。

一对方括号只写一条命令，例如 `[wait:3s][save]`。素材路径以当前 Markdown 所在目录为基准，也接受 `res://` 路径。剧情内的 GDScript 是可信项目代码，执行阶段可通过 `__gal_host` 访问当前播放器。

## 播放与存档

```gdscript
player.save_path = "user://saves/slot_1.json"
player.save_game()
player.load_game()
player.switch_locale("zh-cn")
player.restart()
player.stop()
player.pause()
player.resume()
player.set_auto_play(true)
player.set_fast_forward(true)
```

默认场景支持左键、F、Space、Enter 推进；点击工具按钮不会同时推进。`StoryPlayer.autoplay` 控制场景进入后是否开始剧情，`set_auto_play()` 控制播放过程是否自动推进。暂停同时停止文字、等待、淡入和语音；自动播放和快进不会替玩家选择选项。

`save_game()` 保存深快照，包括顶部普通 `var` 成员、剧情位置、语言和表现状态。相同文字及语言下可恢复句中打字、等待、语音和画面；翻译变化时从新句开头显示。文件写入使用同目录临时文件与重命名替换。变量应为 JSON 数据，函数局部变量不参与存档。

新快照额外保存当前源文件路径，跨文件跳转后也能从配置入口读回正确故事。旧存档仍按其 `story_id` 在入口目录查找。移动/重命名故事文件需要同步处理旧存档中的源路径；文本位置迁移仍按 SID、严格签名和同类型表现指令回退。

## 命令、角色与缓存

默认表现层的 `characters` 数组配置角色资源；角色 `display_name` 匹配说话人，`states` 配置表情立绘。View Nodes 均为导出引用，调整节点层级后重新连接即可。主题中使用 CJK 系统字体，可按发行平台替换为随包字体。

`Story.commands` 指向 `StoryCommandRegistry`，默认使用 `resources/default_commands.tres`。直接加载的故事文件使用默认注册表；自定义配置时创建一个 `MarkdownStory.tres`，设置 `source_file` 和 `commands`，然后将该 `.tres` 作为入口。检查器与播放器使用相同注册表。翻译共用入口的配置，跨文件跳转使用目标入口资源的配置。

添加 `StoryBuiltinCommand` 可把新名字映射到现有表现能力，例如 `hold` → `command_wait`；新能力继承 `StoryCommandHandler`，用 `@tool` 实现 `validate_argument()` 和 `execute()`。完全替换表现层时继承 `StoryPresentation`，实现显示、取消、暂停和状态捕获/恢复接口。

编译缓存属于播放器，默认开启，容量 64。修改源码或编译器版本会使缓存失效，运行时实例和变量仍然隔离。

```gdscript
player.cache_capacity = 128
player.cache_enabled = true
player.program_cache.clear()
print(player.program_cache.hits)
print(player.program_cache.compilations)
```

## 编辑器与导出

启用 Cherry 后，顶部 **Asset Store** 右侧出现 **Story** 主页面入口，旧底部 Story 面板已移除。升级后如果仍显示旧界面，先保存已有工作，再重新打开工程。

- 左侧列出工程全部 `.md` / `.story`，包括尚未被场景引用的文件。排除 `README.md`、隐藏目录及 `.gdignore` 目录；输入文件名或路径可筛选，同名文件的完整路径显示在悬停提示与顶部标题中。
- 右侧复用 Godot 原生 `CodeEdit`，支持行号、缩略图、原生剪贴板及独立撤销历史。Story 高亮区分标题、说话人、状态、命令、参数、跳转路径、粗体和注释；`gdscript` 围栏及独立反引号代码行复用 Godot 原生 `GDScriptSyntaxHighlighter`，支持关键字、类型、函数、字符串与代码注释。字体、字号和颜色跟随编辑器设置即时更新；高亮不会执行剧情代码，也不提供 GDScript 调试器或完整语义补全。
- **File** 菜单提供保存、全部保存、从磁盘重新加载、在文件系统定位和刷新列表。`Ctrl+S` 保存当前文件，`Ctrl+Shift+S` 保存全部。切换文件保留编辑内容与撤销历史，`(*)` 标记未保存修改。
- **Edit** 菜单提供撤销、重做、剪切、复制、粘贴和全选。**Search** 菜单或 `Ctrl+F` 打开查找，`F3` / `Shift+F3` 查找下一处 / 上一处。
- **Story** 菜单提供 **Save All and Check Current / Project**：先保存全部编辑，再检查当前入口或工程剧本。检查涵盖语法、命令参数、素材、跳转、翻译 SID；结果显示在下方，点击诊断会在编辑器中打开对应文件与行。
- 选中 Story 资源时可通过 Inspector 的 **Open in Story** 打开；**Check Story** 检查入口及翻译、跳转。项目工具菜单 **Cherry: Check Stories** 同样打开主页面并执行检查。

保存保留原文件的 LF / CRLF 换行格式，并采用同目录临时文件替换。如果源文件被外部编辑或删除，会阻止覆盖，并保留本地缓冲；可先复制需要保留的修改，再使用 **Reload from Disk**。放弃未保存内容前会显示确认框。运行项目会先尝试保存，保存失败则阻止运行。

未保存内容另存于 Godot 工程编辑器缓存的 `story_editor_recovery.cfg`，停用插件或重开工程后可恢复；这不是剧情源文件，不参与导出，也不应提交到版本库。退出编辑器时未保存文件纳入 Godot 的保存提示。

启用 Cherry 后正常导出即可。导出插件沿入口跟随跨文件跳转，收集同目录翻译、Markdown 原文及素材导入数据。选定场景/资源模式只处理被选中的入口；不会验证无关 README 或未选中的故事。原始 Markdown 也保留在包中，使运行时可继续按文件名发现语言版本。

作者代码计算出的资源路径需要在手动创建的 `MarkdownStory.tres` 入口上配置 `extra_files`。相对路径以入口源文件目录为基准。导出会报告缺失文件及与排除过滤器冲突的依赖；Godot 报错时仍可能写出 PCK，发布前应确保零错误。

`StoryPlayer.runtime_dependencies` 自动保存运行时清单引用，保留选定场景导出需要的全局脚本类。新建或迁移后的场景保存一次即可；新增模块运行时类时同步更新清单。

## 从旧入口迁移

原剧情库资源已移除。将播放器的 `library` 和 `initial_story` 配置改为单个 `story` 资源引用；示例已迁移。`play("剧情ID")` 改为 `play()` 或 `play(Story资源)`。语言列表改用 `player.get_available_locales()`，缓存配置改到播放器；路径和语言字典不再需要。

本次迁移在隔离项目中验证了 38 项新入口行为、32 项存档检查及 31 项表现层回归，以及真实 Markdown 导入、编辑器检查和独立 PCK 播放。PCK 在空目录运行中文入口，并自动跳转到中文后续剧情。验证使用 Godot 4.7.2 .NET、Windows Desktop 与兼容渲染器；临时验证文件留在宿主 `.godot` 下。

原生格式迁移验证包含 Godot 默认资源槽的拖放与撤销/重做、外部引用序列化、场景重载、无编辑器的运行及独立 PCK 播放。
