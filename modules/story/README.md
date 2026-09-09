# Cherry Story

从 `godot_galgame_demo` 整理出的 Godot 4 剧情模块，模块 ID 为 `story`。标准版与 .NET 版共用 GDScript 实现，不需要 Autoload。保留 Markdown 剧情、真实 GDScript 条件与执行代码、七条 VM 指令、打字机、选项、背景、立绘、音频、弹图、存读档和语言切换。

## 运行示例

打开 `examples/story_demo.tscn`，按 F6 运行。推荐视口 1280×720。

- 左键、F、Space、Enter：显示当前文字片段或推进；点击工具按钮不会同时推进。
- Save / Load / Restart：存档、恢复、重开。示例存档为 `user://cherry_story_demo.json`。
- 中文 / 日本語：切换语言并恢复当前剧情位置。
- 在首次选择前点击「Debug 好感=95」，再选择第三项，会跳转到 `mahiro_h`；「Debug 疲劳=90」演示单选项分支。

启用项目设置中的 Cherry 插件后，宿主注册 `StoryModule`，可通过 `get_module(&"story")` 获取模块。未启用编辑器插件也可直接运行示例与运行时类。

## 目录与职责

| 路径 / 类 | 用途 |
| --- | --- |
| `story_module.gd` | Cherry 模块注册；根据自身路径返回运行时及示例位置 |
| `gdscript/story_library.gd` / `StoryLibrary` | 剧情 ID → 语言 → Markdown 路径，显式语言回退链与语言显示名称 |
| `gdscript/story_player.gd` / `StoryPlayer` | 播放编排、跨文件跳转、存读档与语言切换 |
| `StoryParser` / `StoryProgram` / `StoryVM` | Markdown 编译、IR、独立 GDScript 实例与控制流 |
| `StorySaveManager` | v2 JSON 存档、变量恢复及位置迁移诊断 |
| `StoryInlineParser` / `StoryPresenter` | 行内指令与默认异步 UI |
| `StoryCharacter` / `StoryCharacterState` | 可编辑角色及状态资源 |
| `scenes/story_presenter.tscn` | 可复用、可继承编辑的默认表现层场景 |
| `examples/` | 原 demo 的场景、角色、美术、声音及四份中日剧情；调试 UI 单独放在这里 |
| `tests/story_test.gd` | Godot 行为回归与实际场景播放检查 |

运行时没有示例角色、剧情目录或语言判断。每个 `StoryPlayer` 持有独立 VM；跨文件跳转创建目标剧情自己的变量实例。资源库与角色资源可以共享。

## 接入项目

1. 创建 `StoryLibrary` 资源并保存为 `.tres`。在 `stories` 中配置 `{剧情ID: {语言: 文件路径}}`；相对路径以该 `.tres` 所在目录为基准。
2. 实例化 `scenes/story_presenter.tscn`，在 `characters` 数组中添加角色资源。角色的 `display_name` 对应剧情中的说话人，`states` 配置不同表情贴图。
3. 添加 `StoryPlayer` 节点，在 Inspector 中连接 `library`、`presenter`，设置 `initial_story`、`locale` 和 `save_path`。`autoplay` 默认开启。
4. 通过信号连接自己的 UI。默认表现层的文字速度、淡入时长、推进键、鼠标按钮和选项尺寸均可配置；也可调用 `presenter.advance()` 接入项目自己的输入。

默认 `scenes/story_theme.tres` 为普通与粗体文字分别配置 CJK 系统字体，避免默认字体回退造成中文粗体重叠。可替换为项目自己的 Theme；跨平台发行时建议在 Theme 中指定随项目打包的字体。

库资源中的配置例子：

```gdscript
stories = {
    "intro": {"zh-cn": "stories/intro.zh-cn.md", "en": "stories/intro.en.md"},
    "chapter2": {"zh-cn": "stories/chapter2.zh-cn.md"},
}
fallback_locales = PackedStringArray("zh-cn")
locale_labels = {"zh-cn": "中文", "en": "English"}
```

常用接口：

```gdscript
player.play("intro")             # 同步返回准备结果；播放异步进行
player.play("intro", "第二节")   # 从 Markdown 标题开始
player.save_game()
player.load_game()
player.switch_locale("en")
player.restart()                 # 回到 initial_story
player.stop()
player.pause()
player.resume()
player.set_auto_play(true)
player.set_fast_forward(true)

player.story_finished.connect(func(story_id): print(story_id))
player.story_failed.connect(func(message): print(message))
player.restored.connect(func(_quality): print(player.save_manager.restore_quality_text()))
```

`play()` / `load_game()` / `switch_locale()` 返回 `Error`，完成准备后才替换当前播放；准备失败会发出 `story_failed` 并保留当前剧情。播放结束通过 `story_finished` 通知。其他信号为 `story_started`、`instruction_changed`、`saved`、`restored`。内部跳转每帧有执行预算，跨文件跳转会让出一帧。

只需要解析和控制流时，可直接调用 `StoryParser.new().compile_file(path, story_id)` 或 `compile_source(text, story_id, source_path)`，再交给 `StoryVM`，无需创建 UI 节点。

## 剧情语法

完整脚本见 `examples/stories/mahiro.ja.md`。支持：

- 文件开头的 `gdscript` 围栏：剧情局部成员与辅助函数；后续围栏和单行反引号：执行 GDScript。
- `姓名@状态: 台词`、`> 旁白`、缩进选项 `- 选项`。
- 反引号包围的 `if 条件:`、`elif 条件:`、`else:`，支持空格或 Tab 缩进。
- `# 标题`；`>>[说明](##标题)` 本地跳转，`>>[说明](chapter2.md)` 跳转到库中的 `chapter2`。
- 支持 `chapter.one.md#第二节`；点号属于剧情 ID。引用实际的本地化文件名时，通过 `StoryLibrary` 的路径映射解析，不猜测语言后缀。
- `<!-- @sid:稳定标识 -->`：可选的恢复锚点，建议对应翻译使用同一 SID。
- `**粗体**`；`[audio:路径]`、`[wait:3s]`、`[wait:50ms]`、`[i]`、`[save]`。
- `![transition: fadein](路径)` 背景淡入；`![popup](路径)` 弹图并等待输入。

一个 `[...]` 中只写一条指令，例如 `[wait:3s][save]`。图片、音频相对路径以**当前 Markdown 文件**所在目录为基准，也支持绝对 `res://` 路径。模块示例统一使用相对路径，因此整个 Cherry addon 或 `story` 目录可以移动。

剧情中的代码由 Godot 动态编译执行，可以通过 `__gal_host` 访问当前 `StoryPlayer`；它是可信项目代码，不是隔离的脚本语言。

## 存档与保留的限制

存档仍使用原 v2 格式：`story_id`、`locale`、`sid`、`instruction_index`、`op`、`exact_signature`、`variables`。恢复顺序为 SID → 原位置严格匹配 → 附近 ±32 指令严格匹配 → 最近同类型表现指令 → 最近对话。相同距离优先向后，行号只用于诊断。

快照递归复制数组和字典，恢复时先校验所有字段及变量类型，再提交变量与位置变更。v1 SID 存档继续支持；未知版本、错误类型、对象、循环引用、非有限数字及超出 JSON 精确范围的整数会返回错误。迁移搜索按实际剧情长度限制。保存通过同目录临时文件、flush 与重命名替换旧档；失败保留旧档。`max_file_bytes` 默认 16 MiB，可配置。`write_snapshot(path, snapshot)` 可保存宿主扩展的快照。

语言切换使用相同流程；没有共享 SID 时可能采用位置或类型回退，并通过 `restored` 报告实际等级。对示例资源路径的改写会改变涉及这些路径的自动 SID / 严格签名，原 demo 存档可能进入回退；示例使用独立的新存档文件。

`StoryPlayer.create_snapshot()` 与 `save_game()` 额外保存 `StoryPresentationState`：背景及淡入进度、立绘、语音播放位置、弹图、对话/旁白画面、行内游标、剩余等待时间和打字机的小数时间。原文及语言相同则从句中继续，不重复执行已经经过的音频或 `[save]`；翻译或文本变化时保留画面上下文，从新句开头显示。旧存档没有表现状态时仍从句首开始。缺失素材或损坏状态会在替换当前剧情前被拒绝。

表现层使用单一帧时钟。`pause/resume` 同时控制文字、等待、淡入和语音，暂停期间不接受推进或选项输入。`auto_play` 配合 `auto_advance_delay` 自动推进；`fast_forward` 按 `fast_forward_multiplier` 加速。两者均不会自动替玩家选择选项。`advance_time(delta)` 可用于可重复测试；手动驱动时应禁用该节点的自动 `_process`。

仅自动保存顶部普通 `var` 成员，值应为 JSON 可表示数据；函数局部变量不参与存档。`presentation_scene` 与 `metadata` 是角色扩展点，默认表现层只显示 `portrait`。不包含剧情编辑器、编译缓存、rollback 或跨文件调用栈。

导出时选择 **Export all resources in the project**，并在非资源文件导出过滤器添加 `*.md`，确保库引用的 Markdown 和剧情动态引用的图片、声音一起打包。使用选定场景/资源导出模式时，还需显式包含这些动态依赖。

## 验证

解析器会拒绝孤立 `else/elif`、重复标题、异常缩进和被覆盖的 SID。`parser.diagnostics` 返回路径、行、列、严重程度、错误码和消息；`report_errors=false` 可由宿主统一展示这些诊断。

首次使用先让 Godot 完成资源扫描，再从项目根目录执行：

```shell
godot --headless --editor --import --path .
godot --headless --path . --script res://addons/cherry/modules/story/tests/story_test.gd
```

测试覆盖四份剧情编译、相对素材路径、中日分支及条件执行、跨文件跳转、独立变量、Tab/空格缩进、本地标题、存档 JSON 与恢复策略、场景资源装配、语言切换、失败加载保留现场、取消旧选项，以及实际表现层播放到跨文件 END。验证也可在独立项目中仅复制 Cherry addon 后执行，或修改命令路径验证搬移后的模块。
