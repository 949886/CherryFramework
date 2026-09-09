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
| `story_module.gd` | Cherry 模块注册、编辑器检查面板、Inspector 按钮与导出插件 |
| `gdscript/story_library.gd` / `StoryLibrary` | 剧情 ID → 语言 → Markdown 路径，显式语言回退链与语言显示名称 |
| `gdscript/story_player.gd` / `StoryPlayer` | 播放编排、跨文件跳转、存读档与语言切换 |
| `StoryParser` / `StoryProgram` / `StoryVM` | Markdown 编译、IR、独立 GDScript 实例与控制流 |
| `StorySaveManager` | v2 JSON 存档、变量恢复及位置迁移诊断 |
| `StoryInlineParser` / `StoryPresenter` | 行内指令与默认异步 UI |
| `StoryCharacter` / `StoryCharacterState` | 可编辑角色及状态资源 |
| `scenes/story_presenter.tscn` | 可复用、可继承编辑的默认表现层场景 |
| `examples/` | 原 demo 的场景、角色、美术、声音及四份中日剧情；调试 UI 单独放在这里 |
| `StoryLibraryValidator` / `editor/` | 库检查、源行定位与动态导出依赖 |
| `resources/runtime_dependencies.tres` | 供选定场景导出使用的运行时依赖清单 |
| `tests/` | 行为回归、编辑器生命周期及独立 PCK 播放验证 |

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

## 自定义表现层与命令

`StoryPlayer.presenter` 接受 `StoryPresentation`。可以用普通 Node、世界场景或无 UI 节点实现 `present_dialogue/present_narration/present_choice`；这些方法可以异步等待完成。实现应支持取消、暂停和状态捕获/恢复。`get_presenter_id()` 标识状态所属实现，自定义数据放在 `StoryPresentationState.extensions`；不同表现层的状态会被拒绝。

默认 `StoryPresenter` 的 View Nodes 全部通过导出引用连接，节点改名或改变层级无需修改脚本。`is_configured()` 在播放前检查引用和注册表。

`StoryLibrary.commands` 指向 `StoryCommandRegistry`，播放时传给表现层，编辑器检查也使用同一注册表。默认资源为 `resources/default_commands.tres`；独立使用 `StoryPresenter` 时可以直接配置其 `commands`。添加一个继承 `StoryCommandHandler` 的 `@tool` 资源，配置 `command_name` 并实现 `execute(presentation, command) -> Error` 即可扩展指令；参数位于 `argument` 与 `attributes`。可用 `validate_argument` 返回诊断，`asset_type` 声明动态资源类型。处理器应无运行时可变状态；执行数据存放在当前表现层或游戏宿主。

`StoryBuiltinCommand` 将可配置名称映射到表现层能力，例如新的 `hold` 指令可映射到 `command_wait`，继续使用统一时钟和存档游标。注册同名命令默认失败，只有显式 `register(handler, true)` 才替换。修改共享默认注册表前先 `duplicate(true)`；未知命令及无效参数会停止当前表现并发出诊断。

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

仅自动保存顶部普通 `var` 成员，值应为 JSON 可表示数据；函数局部变量不参与存档。`presentation_scene` 与 `metadata` 是角色扩展点，默认表现层只显示 `portrait`。不包含可视化剧情编写器、rollback 或跨文件调用栈。

## 编译缓存

`StoryLibrary` 默认开启内存缓存，`cache_capacity` 默认 64 个编译结果，按最近使用顺序淘汰。缓存键包含源码 SHA-256、源路径、剧情 ID、路径映射和 `StoryParser.COMPILER_VERSION`，不依赖文件时间戳。`cache_enabled=false` 可关闭，`clear_cache()` 可显式清空。

缓存只保留无运行时实例的模板；每次播放深拷贝 IR 并创建新的剧情实例。作者 `_init()` 每次播放执行一次，模板编译不执行它。编译后的 `runtime_script` 会共享，应视为只读；实例变量与数组、字典不会共享。`program_cache.hits/misses/compilations` 可用于观察命中情况，失败结果不会缓存。

## 编辑器检查与导出

启用 Cherry 插件后，使用「项目 → 工具 → Cherry: Check Story Libraries」或底部 **Story** 面板检查所有已保存的库。选中 `StoryLibrary` 资源时，Inspector 的 **Check Story Library** 按钮只检查当前库。结果包含路径、行号、错误码与消息，选择诊断即可在旁边预览源文件并定位到对应行。

检查覆盖库配置、语法、命令及参数、素材存在性与类型、跨文件标题跳转、语言回退、翻译显式 SID 顺序/指令类型。翻译差异是警告。编译检查不创建剧情运行时实例，因此不调用作者 `_init()`；它仍会调用可信自定义命令的参数验证方法。

导出插件自动加入被使用的库的所有语言 Markdown、行内资源以及导入后的素材数据，无需 `*.md` 过滤器。全资源导出检查所有库；选定场景/资源模式按资源依赖图筛选库，并包含 Autoload 的依赖。库应保存为独立 `.tres` / `.res` 文件。预设显式排除的文件不会被偷偷加回；与必需依赖冲突时报告错误。

`StoryPlayer.runtime_dependencies` 是自动保存的内部资源引用，保证全局脚本类进入 Godot 正常导出流程；`resources/runtime_dependencies.tres` 集中声明运行时脚本与默认命令资源。新增运行时类时同步更新清单。现有场景重新保存一次即可获得引用；示例已配置。编辑器中的 StoryPlayer 不会播放剧情。

作者代码计算出的路径无法从 Markdown 推断：把这些文件加入 `StoryLibrary.extra_files`，相对路径以库资源目录为基准。额外资源的依赖也会收集；自定义全局脚本类应通过场景、资源或运行时清单建立常规引用，使 Godot 的全局类缓存也包含它们。

导出诊断会显示在 Godot 导出日志中；错误日志不保证 Godot 不生成 PCK，发布前应使检查结果为零错误。当前已验证 Windows Desktop PCK、兼容渲染器、全运行时脚本和选定场景导出；其他平台的素材导入格式仍应在目标平台验证。未启用插件时，需自行配置 Markdown 与动态依赖的导出过滤器。

## 验证

解析器会拒绝孤立 `else/elif`、重复标题、异常缩进和被覆盖的 SID。`parser.diagnostics` 返回路径、行、列、严重程度、错误码和消息；`report_errors=false` 可由宿主统一展示这些诊断。

首次使用先让 Godot 完成资源扫描，再从项目根目录执行：

```shell
godot --headless --editor --import --path .
godot --headless --path . --script res://addons/cherry/modules/story/tests/story_test.gd
```

测试覆盖四份剧情编译、相对素材路径、中日分支及条件执行、跨文件跳转、独立变量、Tab/空格缩进、本地标题、存档 JSON 与恢复策略、场景资源装配、语言切换、失败加载保留现场、取消旧选项，以及实际表现层播放到跨文件 END。验证也可在独立项目中仅复制 Cherry addon 后执行，或修改命令路径验证搬移后的模块。

完整隔离验证（会把模块搬移到临时项目的另一目录，不修改宿主项目设置）：

```shell
python addons/cherry/modules/story/tests/run_tests.py --godot /path/to/godot --editor-export
```

包含 281 项运行时检查、真实编辑器插件注册/卸载与新场景依赖保存、仅选定场景导出、从空目录运行 PCK 到跨文件 END，以及无效剧情的导出诊断。单组测试可用 `--test validator_test.gd` 等参数。
