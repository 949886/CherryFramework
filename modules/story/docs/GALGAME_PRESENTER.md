# Galgame presenter

打开 `examples/galgame_demo.tscn`，按 F6 运行。Ronava 项目也把它设为了 F5 的启动场景。
首次打开项目需等待 Godot 完成资源扫描。基础 `story_demo.tscn` 保留用于调试核心播放器。

## 复用和编辑场景

### 编辑器显示与运行时主题

`resources/galgame_theme.tres` 是 2D 编辑器与运行时共用的主题入口，包括界面字体、
正文默认字体、按钮、分割线、滑条和菜单面板样式。运行时复制此主题并按玩家设置调整配色，
不会重新创建并覆盖其中的圆角、边距和默认界面字号。对白仍按玩家的文字设置显示。
共享主题也显式声明了游戏的默认控件样式与间距，阻止 Godot 编辑器主题的正文黑底、
标签内边距和分割线高度透传到场景预览。

主要场景带有 `EditorPreview` 节点。打开场景即可看到正文、选项、设置字段、存档卡片、
回顾和流程图的示例内容。预览复用实际组件与页面构建逻辑；独立菜单按游戏的 1280 × 720
设计画布显示，避免误用编辑器窗口尺寸。Demo 的角色和背景沿用其 Presenter 配置。

选中 `EditorPreview`，可以调整示例文字、选项、背景、角色图，以及 `settings_section`
预览的设置分类。`settings` 字典使用设置 schema 的键值，例如
`{"palette": "mint", "glass": true, "font_size": 28}`，用于预览相应的实际字体与毛玻璃效果。
默认预览使用默认设置；不会读取玩家存档或设置，因此运行中选择其他配色时应在这里指定同样的值。

预览不启动剧情、音频和导航，也不保存玩家设置。示例节点没有场景 owner；保存前自动移除
示例内容并恢复原始属性，保存后重新生成，避免把预览选项或临时主题烘焙进游戏场景。
你通过 Inspector 修改的控件属性和 StyleBox 样式会保留。动态示例控件的结构应修改其模板场景，
如 `choice_button.tscn` / `slot_card.tscn`；设置字段仍在 `galgame_settings.json` 中配置。

### 接入与场景结构

可复用入口是 **`scenes/galgame_presenter.tscn`**。`examples/galgame_demo.tscn` 直接实例化
这个场景，只提供示例剧本、角色、背景和存储配置；Presenter 本身不引用示例角色或剧本。

1. 把 `galgame_presenter.tscn` 拖入游戏的 `Control` 场景。
2. 添加 `StoryPlayer`，配置 `story`，把 `presenter` 指向该场景实例。
3. 在 Presenter Inspector 配置 `characters`、`backdrop`、`catalog_path`、标题、音频，
   并为不同游戏设置独立的 `save_directory`。`StoryPlayer` 沿用标准 `runtime_dependencies.tres`。
4. 建议从 Presenter 创建继承场景做项目定制。右键子场景实例启用「可编辑子节点」，
   就能修改对话框内部布局；无需把场景拆为独立节点，也无需修改创建控件的代码。

主场景树中的 `Stage/GameView` 包含背景、立绘、对白、旁白、选项滚动区域、图片弹层、
标题和底栏；`Stage/Menus` 包含 Cherry Navigator、转场输入遮挡和提示条，`Audio` 包含四个播放器。
这些节点在运行前已经存在。启动后 `GameView` 整体挂入 Cherry 的常驻根路由，节点及其引用保持不变。

菜单路由资源由 `menus.tscn` 的 `page_catalog` 属性配置，默认使用 `galgame_pages.tres`。
可在 Inspector 中替换该资源。菜单脚本不预加载页面场景，避免页面的编辑器预览反向引用
菜单类时形成资源加载循环；单独打开组件也不需要先打开 Presenter。

| 场景 | 可直接编辑的内容 |
| --- | --- |
| `scenes/galgame_presenter.tscn` | 设计画布、背景和立绘区域、对话框锚点、选项宽度、底栏按钮布局 |
| `scenes/galgame/dialogue_box.tscn` | 正文边距、姓名牌、语音标记、面板圆角、毛玻璃层；对白和旁白共用 |
| `scenes/galgame/choice_button.tscn` | 单个选项的最小高度、字号、内边距、圆角；可替换 Presenter 的 `choice_scene` |
| `scenes/galgame/menu_page.tscn` | 菜单页公用边距、标题、返回按钮、分割线和内容区 |
| `scenes/galgame/settings.tscn` | 分类侧栏、重置按钮、原生 TabContainer |
| `scenes/galgame/slots.tscn` / `slot_card.tscn` | 存读档网格、分页区、自动存档按钮，以及栏位内的缩略图和文字布局 |
| `scenes/galgame/confirm.tscn` / `menus.tscn` | 确认框、导航容器、转场遮挡和提示条 |
| `scenes/galgame/dialogue_preview.tscn` | 设置子页的预览裁切区域、背景和立绘容器 |

`Stage` 默认是 1280 × 720 的固定设计画布，窗口变化只改变它的整体缩放和留边。
对白与旁白使用底部锚点：左右偏移和底边距离来自场景；较大的文字设置只让上边界向上扩展，
不会覆盖你编辑的底部和水平边距。场景高度是最小高度，`visible_lines` 与 `text_height_allowance`
控制文字设置需要的额外空间。选项的水平锚点和宽度来自场景，垂直位置跟随对白顶部；
间距由 `choice_gap` 控制，可用空间不足时滚动，行高按选项子场景的实际尺寸测量。

脚本继续负责主题配色、玩家字体/毛玻璃设置、剧情状态和信号连接。底栏按钮通过
`metadata/action` 绑定语义动作，改节点名字或顺序不会改变其功能。选项、存档栏位按模板场景实例化；
设置字段按 JSON schema 生成，回顾记录与流程图按实际数据生成。设置预览复制当前对话框组件，
包括继承场景中的姓名牌位置和正文边距，同时拥有独立的材质与文本状态。

## 界面与操作

画面统一绘制在 1280 × 720 的设计画布，再等比适配窗口。其他宽高比留边；
菜单与正文共用这块画布。选项底部相对对话框顶部保持 28 个设计像素的距离。
长选项列表和长正文可滚动。正文默认黑体、23 px、1.5 倍行距，标题和装饰文字使用衬线体。

底栏提供回顾、自动、存档、读档、隐藏、流程图、快进和设置。
空格、Enter、F 或左键推进；Esc 返回；A 自动、Ctrl 切换快进、H 隐藏、
S 存档、L 读档、B 回顾、M 流程图。隐藏界面后单击恢复。
菜单、确认框和隐藏状态会隔离剧情输入；失去焦点时默认暂停。

选项使用统一的渐显、悬停/键盘聚焦和按下过渡。选中后短暂高亮确认，其他选项淡出，
然后推进一次剧情；期间重复点击不会更换或重复提交选择。选项外框和点击区域保持不动。
「减少动态效果」关闭位移与等待，直接显示最终状态。菜单暂停同时冻结选项确认，
读档或重启会取消旧选择的待完成反馈。开发者可在设置 schema 的 `choice_motion` 中
统一调节各阶段时长、文字位移与弱化透明度。

存档和读档分为两个页面，各有 4 页、每页 6 个栏位。存档带实际画面缩略图和文本摘要。
选择出现时默认写入独立自动存档，不占用手动栏位。覆盖和读取默认需要确认。
损坏文件不会替换正在播放的进度。回顾连续滚动，包含对白、旁白和选择，并可重播已有语音。

设置分为文字样式、阅读播放、声音、画面与界面、操作与存档。
文字、阅读、画面子页内显示实际对白组件的缩小预览；声音和操作子页没有预览。
六套清新配色、原始奶油色、暮夜和系统配色共用主题令牌。
毛玻璃开关位于界面动效之后；只有启用时显示模糊、底色浓度和饱和度。没有边缘光。
剧情选项也共用这些毛玻璃设置，实时跟随配色与参数变化；文字保持清晰，悬停和选中
仍通过底色与文字高亮反馈。关闭后恢复原来的纯色选项。

## 资源和配置

| 文件 / 类 | 定制内容 |
| --- | --- |
| `examples/galgame/entry.tres` | `StoryPlayer.story` 的入口；`extra_files` 声明动态读取的 JSON |
| `examples/galgame/stories/` | 八个实际剧本，三条分支在 evening 文件汇合，再通向两个结局 |
| `examples/galgame/catalog.json` | 以剧本 ID 为键的标题、章节、摘要和结局标记；不定义连线 |
| `examples/galgame/mahiro.tres` | 角色名、ID、普通和 happy 差分；脚本用 `真尋@happy:` 切换 |
| `resources/galgame_settings.json` | 默认值、范围、条件显示、分类、槽位数量与配色 |
| `StorySkin` / `StoryDialogueBox` | 字体和主题令牌、实际对话框与预览共享的组件 |
| `StoryGalgamePresenter` | 场景节点绑定、剧情表现、键盘、音频与菜单暂停；复用原有 StoryPresenter 状态机 |
| `StoryGalgameMenus` | Cherry Navigator 路由、返回、确认结果及剧情暂停 |
| `StoryMenuPage` / `StoryConfirmationPage` | 原生 NavigationPage / NavigationDialog 场景及页面内状态 |
| `StoryFlowView` | 流程图交互 |
| `StoryArchive` / `StoryLibrary` | 校验后的快照、回顾、已读进度、书签与真实文件图 |

自定义实例可在 presenter Inspector 配置 `characters`、`backdrop`、`catalog_path`、
`game_title`、`footer_caption` 和独立的 `save_directory`。字体使用系统字体回退；
需要跨设备固定字形时，在 `StorySkin` 中改用项目内的 FontFile 资源。
Godot 的字距为整数像素，因此界面中的半像素字距会在渲染时取整。

语音使用脚本的 `[audio:相对路径]`，背景音乐和点击音效分别通过
`music_stream` / `effect_stream` 配置。示例提供语音演示资源，未提供背景音乐和点击音效素材。
音量分别控制 Master、Voice、Music、Effects 总线；对白播放时可自动压低音乐。
自动推进可等待语音结束；默认快进只经过已读内容。

## 流程图与存储

流程图遍历入口能到达的跨文件 JMP。一个文件身份只产生一个节点，本地标题和翻译文件不重复。
图支持分支、汇合、循环、拖动、缩放、全图适配、小地图、搜索、章节筛选和书签。
当前文件、已访问文件、相邻未读文件和未解锁文件分别显示；未解锁节点隐藏标题与文件名。
重读从该文件首次出现可见剧情时保存的快照开始，恢复当时变量和画面，先征求确认。

默认存储目录为 `user://cherry_galgame`：`settings.cfg` 保存设置，`profile.cfg` 保存
终身已读进度、文件入口快照和书签，`slot_01.json` 到 `slot_24.json` 保存手动存档，
`automatic.json` 保存自动存档。读档不回滚设置或终身已读记录。
文本改动后，其精确签名变化，改动的片段重新视为未读。回顾最多保存最近 500 条。

## 导出与验证

Galgame UI 依赖 Cherry Navigation 的 GDScript 运行时。`scenes/galgame/` 中的场景
使用 `ui://cherry/story/...` 导航路径；`resources/galgame_pages.tres` 显式引用页面定义，
可通过 `Navigator.push_definition_configured()` 在未运行编辑器注册表生成器的导出环境中使用。
场景仍可被 Cherry 的页面注册表扫描，转场由 `galgame_page_transition.tres` 配置。

剧情是常驻根路由。菜单进栈后，Cherry 负责遮罩、覆盖期间的输入隔离和返回时的焦点恢复；
确认框是同一个导航栈中的 `NavigationDialog`，仅返回 `true` 执行确认操作。
Esc / 返回调用 `maybe_pop()`，读档和重新开始使用 `pop_until()` 关闭整个菜单流程。
剧情在退出动画结束后恢复，转场期间屏蔽连续输入。减少动效使用零时长的原生转场。

设置使用隐藏原生标签栏的 `TabContainer` 与侧边按钮组，子页首次访问时创建并保留。
切换分类保留控件、滚动位置及预览；重置只同步控件值。存读档页复用栏位卡片，
翻页及保存只绑定新数据，不重建菜单场景。流程图和回顾在被确认框覆盖后也保持原有状态。

StoryPlayer 引用 `runtime_dependencies.tres`，可复用 Presenter 场景自带 `galgame_dependencies.tres`，
确保选定场景导出包含运行时脚本、组件场景及毛玻璃着色器。自己的剧本入口也需在 `extra_files`
中声明 `resources/galgame_settings.json` 和使用的剧本说明 JSON（路径相对入口的源剧本文件），
示例 `entry.tres` 展示了配置；它们是动态读取的文件，不属于普通纹理场景依赖。
导出时启用 Cherry 插件，使 Markdown 跳转、命令中的图像和音频依赖自动进入 PCK。

在模块目录外运行：

```text
python addons/cherry/modules/story/tests/run_tests.py --godot <Godot可执行文件>
```

测试使用独立的临时项目和用户目录，覆盖模型、真实原生菜单、多分辨率、分支结局及
从独立 PCK 启动。窗口渲染检查使用 `galgame_ui_test.gd -- --render`，截图由 Godot
Viewport 直接输出到测试用户目录，包含实际设置预览、毛玻璃和 7 种窗口尺寸。
`galgame_scene_test.gd` 单独实例化可复用场景，序列化自定义布局和选项模板，验证
独立播放器接入、继承修改保留、多分辨率锚点、预览一致性与材质隔离。
`galgame_editor_suite.gd` 在真实编辑器进程中检查各场景的预览、设置分类切换、保存前后的
清理与重建、样式修改保留，以及音频和玩家配置隔离。
