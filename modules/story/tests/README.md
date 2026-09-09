# Story 回归测试

在宿主工程根目录运行，传入已安装的 Godot 可执行文件：

```powershell
python addons/cherry/modules/story/tests/run_tests.py --godot "C:/path/to/godot_console.exe"
```

也可设置环境变量 `GODOT`，或把 `godot` 加入 PATH，然后省略 `--godot`。需要 Python 3.9 及以上版本；没有第三方 Python 依赖。当前验证环境为 Windows、Godot 4.7.2 .NET，使用兼容渲染器和 headless 编辑器。PCK 测试不需要导出模板。

默认完整运行 **运行时 → 编辑器 → 图标与旧缓存 → 选定场景导出 → 空目录 PCK 播放 → 导出错误诊断**。旧的 `--editor-export` 参数仍然接受，但现在完整回归已是默认行为。

仅运行运行时，或指定其中一组：

```powershell
python addons/cherry/modules/story/tests/run_tests.py --godot "C:/path/to/godot_console.exe" --runtime-only
python addons/cherry/modules/story/tests/run_tests.py --godot "C:/path/to/godot_console.exe" --test parser_test.gd --runtime-only
```

`--test` 可重复指定；未加 `--runtime-only` 时仍会运行编辑器与导出阶段。`--timeout` 设置每个引擎进程的超时秒数，默认 120 秒。

## 覆盖范围

| 测试 | 主要行为 |
| --- | --- |
| `resource_test.gd` | `.md` / `.story` 原生加载、README 排除、自动发现语言、区域回退、同语言扩展名冲突、跨格式跳转、场景外部引用重载 |
| `parser_test.gd` | 缩进与嵌套条件、错误行号、重复标题、SID、局部和跨文件跳转、带点的剧情 ID |
| `story_test.gd` | 示例全部语言与分支、VM 状态、真实表现层驱动播放、失败替换保护、跨文件存档恢复 |
| `save_test.gd` | 深快照、类型校验、旧格式恢复、位置迁移、JSON 损坏、原子写入、大小限制 |
| `presentation_test.gd` | 句中文字/等待/输入/淡入恢复、暂停、快进、自动播放、语音和立绘、60/120 Hz 一致性 |
| `extension_test.gd` | 自定义命令、参数验证、注册冲突、替换表现层、扩展状态保存 |
| `cache_test.gd` | 缓存命中、独立运行时、初始化次数、源码/剧情 ID/编译器版本失效、容量淘汰、错误恢复 |
| `validator_test.gd` | 跳转闭环、混合格式及语言、SID 漂移、命令/素材/显式依赖诊断、验证时不执行作者代码 |
| `editor_suite.gd` | 主页面、菜单、资源检查器、文件筛选、CodeEdit 撤销/保存、CRLF、外部冲突和删除保护、恢复缓冲、诊断定位、原生复制、UID、资源槽赋值和场景保存 |
| `syntax_suite.gd` | 各 Story 语法角色、按字符对照原生 GDScript 高亮、代码围栏/注释缓存、增删行和撤销、不完整语法、正文亮度、颜色区分、配色刷新、独立文档、2000 行文本测量、不执行作者代码 |
| `icon_suite.gd` | 旧 TextFile 索引修复、两种格式的真实 FileSystem 图标、Script 页缓存及未保存内容保护、UID 保持、无重复扫描、缓存 TextFile 的复制 |
| `export_runtime.gd` | 仅选定场景导出、原生 `.story` 引用、两种语言的原始文件与素材、显式额外文件、排除无关错误剧本、中日双语真实播放至后续文件 |

测试使用真实引擎和编辑器组件。资源槽检查通过原生 `EditorResourcePicker` 赋值及 `PackedScene` 保存/重载完成，不模拟鼠标拖动手势。界面布局和颜色的人工观感仍需在可见编辑器中确认。

## 隔离和结果

每次运行在系统临时目录创建 `cherry-story-tests-*`。Story 复制到 `features/narrative`、核心模块复制到 `shared/cherry_core`，验证脚本不依赖默认安装目录。复制时只更新 `.tscn` / `.tres` 的序列化路径提示，保留相对引用和 UID。

测试工程、导入缓存、编辑器设置和用户存档全部使用临时目录。不会启动或修改当前打开的宿主工程。每阶段有独立日志，`report.json` 保存命令、耗时、检查数及结果；失败时退出码为 1，成功为 0。运行结束保留该目录便于排查，确认后可以手动删除。

Godot 可能在脚本或导出错误时返回 0，因此执行器还会检查错误日志、测试完成标记和 PCK 是否实际生成。负向导出用例只允许预期诊断及导出平台汇总，不会吞掉其他脚本错误。唯一忽略的环境错误是沙箱中可能出现的 Windows 根证书存储读取失败，测试不访问网络。

旧文件图标专项会在**临时工程**中构造 Godot 的 `filesystem_cache10` TextFile 条目，并恢复 Script 文本页。这项缓存格式相关测试会在引擎更改格式时明确失败，需要随 Godot 升级更新夹具。
