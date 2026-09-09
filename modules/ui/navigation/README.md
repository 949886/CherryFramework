# Navigation 转场

Cherry 同时提供 GDScript 与 C# 实现。编辑器模块根据项目根目录是否有 `.csproj` 自动选择运行时。

## 内置效果

| Resource | Push / Pop 行为 | 默认参数 |
| --- | --- | --- |
| `FadeNavigationTransition` | 淡入 / 淡出 | 0.18 秒，线性 |
| `SlideNavigationTransition` | 从指定边缘滑入 / 向同一边缘滑出 | 右侧，1 倍页面宽度，0.28 秒 |
| `SlideFadeNavigationTransition` | 短距离滑动，同时淡入 / 淡出 | 底部，0.08 倍页面高度，0.22 秒 |
| `ScaleNavigationTransition` | 从指定相对缩放淡入 / 缩回并淡出 | 0.9 倍缩放，页面中心，0.24 秒 |

新增效果默认使用 Cubic / Ease Out。它们只动画当前进入或离开的页面，底层页面保持原位；底层页面的可见性和覆盖期间的处理策略仍由 Navigator 管理。Modal 的遮罩仍由 Navigator 独立管理。

## Inspector 设置

1. 在 Navigator 的 `Default Transition` 上新建上述 Resource，作为全局默认效果。
2. 或在某个 NavigationPage 的 `Transition` 上新建 Resource，覆盖该页面的默认效果。该引用在页面初始化配置前写入 Route；配置回调中才修改页面的 `Transition` 不会改变当前 Route。
3. 展开 Resource 调整参数，或保存成 `.tres` 供多处共用。

所有内置效果通过 `TweenNavigationTransition` 提供 `Duration`、`Ease Type` 和 `Transition Type`。GDScript 属性采用 snake_case，C# 属性采用 PascalCase。`Duration <= 0` 会立即完成，不改变页面属性。

- Slide / Slide Fade：`From Edge` 选择 Left / Right / Top / Bottom；`Distance Ratio` 是页面宽度或高度的倍数，不依赖固定像素尺寸。页面某个尺寸为零时使用父 Control 对应尺寸，没有父 Control 时使用 Viewport 尺寸。
- Scale：`Hidden Scale` 是相对页面原有缩放的倍率，小于 1 为放大进入，大于 1 为缩小进入；`Pivot Ratio` 是页面内的归一化中心，例如 `(0.5, 0.5)`；`Fade` 可关闭透明度动画。
- 嵌套 Navigator 可开启 `Clip Contents`，将滑动内容限制在导航区域内。

动画结束后恢复原有位置、缩放、旋转中心和颜色，包括原本小于 1 的透明度。每次运行单独保存状态，共用 Resource 的多个 Navigator 不会覆盖彼此的数据。动画使用 Process 暂停模式，SceneTree 暂停期间也可完成导航。

页面应由 Navigator 直接挂载。转场期间避免让其他 Tween、布局脚本同时修改它正在动画的根节点属性；动态内容动画可以放在子 Control 上。位移尺寸和缩放中心在每次转场开始时计算。

## 代码示例

GDScript：

```gdscript
var slide := SlideNavigationTransition.new()
slide.from_edge = SlideNavigationTransition.Edge.RIGHT
slide.distance_ratio = 1.0
slide.duration = 0.3
$Navigator.default_transition = slide

# 给某类页面设置缩放效果，在该页面的 _init() 中执行。
var zoom := ScaleNavigationTransition.new()
zoom.hidden_scale = 0.85
zoom.pivot_ratio = Vector2(0.5, 0.5)
transition = zoom
```

C#：

```csharp
GetNode<Navigator>("Navigator").DefaultTransition = new SlideNavigationTransition
{
    FromEdge = SlideNavigationTransition.Edge.Right,
    DistanceRatio = 1.0f,
    Duration = 0.3,
};

// 在 NavigationPage 的构造函数中设置默认效果，或通过 Inspector 设置。
Transition = new ScaleNavigationTransition
{
    HiddenScale = 0.85f,
    PivotRatio = new Vector2(0.5f, 0.5f),
};
```

自定义动画仍可直接继承 `NavigationTransition`，实现 `push/pop` 或 `PushAsync/PopAsync`。只需要组合位移、缩放和透明度时，也可继承 `TweenNavigationTransition` 并调用 `_animate` / `AnimateAsync`。

## 回归测试

```text
python addons/cherry/modules/ui/navigation/tests/run_tests.py --godot <Godot.NET可执行文件> --dotnet <dotnet可执行文件>
```

测试会在临时目录分别创建 GDScript 和 C# 项目，执行导入、C# 编译与运行时测试，不改动主项目配置。输出目录保留日志和 `report.json`。`.gd.txt` / `.cs.txt` 是测试源码模板，运行器将其复制为脚本，避免未选择的语言和测试类被宿主项目扫描。

可用 `--language gdscript` 仅测试 GDScript（不需要 .NET），或 `--language csharp` 仅测试 C#。C# 项目默认选择与传入引擎相同版本的 Godot.NET.Sdk；自定义引擎可传 `--sdk-version`。

测试覆盖正反向动画中点、四个滑动方向、原有透明度与变换恢复、非正时长、资源共享与序列化，以及真实 Navigator 的队列、覆盖与返回行为。
