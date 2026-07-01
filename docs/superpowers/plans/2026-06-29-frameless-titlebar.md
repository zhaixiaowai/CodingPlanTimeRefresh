# 无边框标题栏 + 设置独立窗口 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 隐藏系统标题栏、整个 mini 界面可拖动、自绘右侧 4 按钮（置顶图标互切/设置/最小化/关闭），设置走 `desktop_multi_window` 真独立第二窗口（模态、IPC 回传 saved 布尔、主窗口自行 reload）。

**Architecture:** 主窗口继续用 `window_manager`（隐藏标题栏 + 自绘控制行 + 全界面拖动）；设置窗口由 `desktop_multi_window` 接管（独立 engine、`config.dat` 文件级解耦、`WindowMethodChannel` 单布尔 IPC）。通过 `SettingsWindowOpener` 接口隔离多窗口实现，主窗口逻辑可用 fake 完整测试。放大态全组删除（被设置窗口取代）。

**Tech Stack:** Flutter (sdk ^3.12.2)、`window_manager` ^0.5.1、新增 `desktop_multi_window`、`flutter_test`。

## Global Constraints

- 所有代码注释、文案用中文（CLAUDE.md 全局规则）。
- 不自动 push 远端；每个任务末尾提交本地。
- 文件读写限制在项目根目录 `D:\My\Project\Common\Other\CodingPlanTimeRefresh\` 内。
- Windows-first：macOS 多窗口行为留 TODO 手动验证（延续既有约定）。
- 配置持久化：AES 加密 `config.dat`，`ConfigService.load/save` 已有兜底链与旧路径迁移，本计划不改其逻辑。
- 运行测试：`cd codingplan_refresh && flutter test`。
- 失焦半透（窗口 `setOpacity 0.9`）保留；顶部栏跟随窗口透明度（既有方案 B）。
- 设计依据：`docs/superpowers/specs/2026-06-29-frameless-titlebar-design.md`。

---

## File Structure

| 文件 | 职责 | 本计划 |
|---|---|---|
| `codingplan_refresh/pubspec.yaml` | 依赖 | 改：+ `desktop_multi_window` |
| `codingplan_refresh/lib/platform/settings_window_opener.dart` | **新**：`SettingsWindowOpener` 抽象 + 生产实现 `DesktopMultiWindowSettingsOpener` | 新建 |
| `codingplan_refresh/lib/ui/settings_window.dart` | **新**：`SettingsApp`（设置窗口 widget：X 关闭栏 + ConfigPanel） | 新建 |
| `codingplan_refresh/lib/platform/window_controller.dart` | 主窗口窗口控制 | 改：`TitleBarStyle.hidden`、+ `minimize()`/`close()`、删放大态方法、`opacityFor` 简化 |
| `codingplan_refresh/lib/ui/main_page.dart` | 主窗口 UI | 改：顶部栏 4 按钮、全界面拖动、模态遮罩、`_applyConfig`、删放大态全组、依赖 `SettingsWindowOpener` |
| `codingplan_refresh/lib/main.dart` | 入口 | 改：多窗口 engine 分发 |
| `codingplan_refresh/test/...` | 测试 | 新增/改 |

**测试 fake 复用既有模式**：`main_page_test.dart` 已有 `FakeWindowController extends WindowController` override 全部平台调用。本计划新增 `FakeSettingsWindowOpener` 同理注入。

---

### Task 1: 引入依赖 + `SettingsWindowOpener` 接口 + Fake + 验证 pin_off

**Files:**
- Modify: `codingplan_refresh/pubspec.yaml`
- Create: `codingplan_refresh/lib/platform/settings_window_opener.dart`
- Create: `codingplan_refresh/test/platform/settings_window_opener_test.dart`

**Interfaces:**
- Produces: `abstract class SettingsWindowOpener { Future<void> open(); void onClosed(void Function(bool saved) cb); }` —— 后续 Task 2/4/5 依赖；生产实现 `DesktopMultiWindowSettingsOpener`（Task 3 填充）、测试 fake 同文件外置。
- Consumes: 无。

- [ ] **Step 1: 加依赖**

修改 `codingplan_refresh/pubspec.yaml`，在 `dependencies:` 下 `window_manager` 之后加：

```yaml
  desktop_multi_window: ^0.3.0
```

- [ ] **Step 2: 拉取依赖**

Run: `cd codingplan_refresh && flutter pub get`
Expected: 解析成功，下载 `desktop_multi_window`。

- [ ] **Step 3: 写接口文件**

创建 `codingplan_refresh/lib/platform/settings_window_opener.dart`：

```dart
/// 设置窗口打开器抽象：隔离多窗口实现（生产用 desktop_multi_window，测试用 fake）。
///
/// 主窗口点「设置」调 [open] 创建独立设置窗口并进入模态；设置窗口关闭时经 [onClosed]
/// 回传「是否有保存」布尔，主窗口据此决定是否 reload 配置。设置窗口本身不持有
/// AppConfig 引用，唯一数据媒介是 config.dat 文件（见设计 spec §3/§5）。
abstract class SettingsWindowOpener {
  /// 创建并显示设置窗口（独立 OS 窗口）。主窗口在调用后自行进入模态遮罩态。
  Future<void> open();

  /// 注册关闭回调。[saved]=true 表示用户在设置窗口点了保存（已写盘）；
  /// false 表示取消/异常关闭。回调在主窗口 engine 触发。
  void onClosed(void Function(bool saved) cb);
}
```

- [ ] **Step 4: 写 fake 行为测试（验证 onClosed 回调可注册并触发，为后续主窗口测试铺路）**

创建 `codingplan_refresh/test/platform/settings_window_opener_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/platform/settings_window_opener.dart';

/// 测试用 fake：记录 open 调用次数，暴露 simulateClosed 触发已注册回调。
class FakeSettingsWindowOpener implements SettingsWindowOpener {
  int openCalls = 0;
  void Function(bool saved)? _cb;

  @override
  Future<void> open() async {
    openCalls++;
  }

  @override
  void onClosed(void Function(bool saved) cb) {
    _cb = cb;
  }

  /// 模拟设置窗口关闭（测试驱动主窗口 reload/移遮罩逻辑）。
  void simulateClosed(bool saved) => _cb?.call(saved);
}

void main() {
  test('FakeSettingsWindowOpener: open 计数 + onClosed 回调可触发', () async {
    final op = FakeSettingsWindowOpener();
    bool? received;
    op.onClosed((saved) => received = saved);
    await op.open();
    expect(op.openCalls, 1);
    op.simulateClosed(true);
    expect(received, isTrue);
    op.simulateClosed(false);
    expect(received, isFalse);
  });
}
```

- [ ] **Step 5: 跑测试**

Run: `cd codingplan_refresh && flutter test test/platform/settings_window_opener_test.dart`
Expected: PASS。

- [ ] **Step 6: 验证 Icons.pin_off 可用（决定置顶图标是否需 material_symbols_icons）**

Run: `cd codingplan_refresh && flutter test test/platform/settings_window_opener_test.dart 2>&1 | head -1`（确认基线编译通过）
然后在任意测试临时加一行 `const _ = Icons.pin_off;`（仅探测编译），跑 `flutter analyze` 或编译。若 `Icons.pin_off` 未定义 → 在 `pubspec.yaml` 加 `material_symbols_icons: ^0.0.190` 并改用 `MaterialSymbols.pin_off`（Task 4 会引用）。若已定义 → 直接用 `Icons.pin_off`，**不加** `material_symbols_icons`。
预期：Flutter sdk ^3.12.2 的 `Icons` 类已含 `pin_off`（Flutter 3.16+ 引入），无需额外包。探测后移除临时行。

- [ ] **Step 7: 提交**

```bash
git add codingplan_refresh/pubspec.yaml codingplan_refresh/pubspec.lock \
        codingplan_refresh/lib/platform/settings_window_opener.dart \
        codingplan_refresh/test/platform/settings_window_opener_test.dart
git commit -m "feat(platform): SettingsWindowOpener 接口 + fake + desktop_multi_window 依赖"
```

---

### Task 2: `SettingsApp` 设置窗口内容（ConfigPanel 容器 + X 关闭栏）

**Files:**
- Create: `codingplan_refresh/lib/ui/settings_window.dart`
- Create: `codingplan_refresh/test/ui/settings_window_test.dart`

**Interfaces:**
- Consumes: `ConfigService`（load/save）、`LocalizationService`、`ConfigPanel`（既有）、`AppConfig`。
- Produces: `class SettingsApp extends StatelessWidget`，构造 `SettingsApp({required ConfigService configService, required LocalizationService l10n, required void Function(AppConfig next) onSave, required VoidCallback onCancel})`。
  - `onSave`：用户点保存 → 内部 `configService.save(next)` 写盘后回调（上层 Task 3 的生产 opener 在此发 IPC）。
  - `onCancel`：用户点取消或 X → 回调（上层发 IPC `{saved:false}`）。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/ui/settings_window_test.dart`：

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/settings_window.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('settings_'));
  tearDown(() => dir.deleteSync(recursive: true));

  ConfigService _cs() => ConfigService(dir);
  AppConfig _seeded(String name) =>
      AppConfig(providers: [ProviderConfig(id: 'p1', name: name, apiUrl: 'https://x', apiKey: 'k')]);

  testWidgets('加载 config.dat 作为 ConfigPanel initial，显示已存 provider 名', (tester) async {
    _cs().save(_seeded('智谱'));
    final l10n = LocalizationService()..initialize('zh');
    await tester.pumpWidget(MaterialApp(
      home: SettingsApp(
        configService: _cs(),
        l10n: l10n,
        onSave: (_) {},
        onCancel: () {},
      ),
    ));
    await tester.pump();
    expect(find.textContaining('智谱'), findsWidgets);
  });

  testWidgets('点保存 → 写盘 + 触发 onSave(next)', (tester) async {
    final cs = _cs();
    cs.save(_seeded('旧名'));
    final l10n = LocalizationService()..initialize('zh');
    AppConfig? saved;
    await tester.pumpWidget(MaterialApp(
      home: SettingsApp(
        configService: cs,
        l10n: l10n,
        onSave: (next) => saved = next,
        onCancel: () {},
      ),
    ));
    await tester.pumpAndSettle();
    // 点 ConfigPanel 的「保存」按钮（本地化 key 'save' = '保存'）。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    // 写盘成功：重新 load 拿到的是保存后的内容（providers 结构一致）。
    expect(cs.load().providers.length, saved!.providers.length);
  });

  testWidgets('点 X 关闭 → 触发 onCancel（不保存）', (tester) async {
    _cs().save(_seeded('x'));
    final l10n = LocalizationService()..initialize('zh');
    bool cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: SettingsApp(
        configService: _cs(),
        l10n: l10n,
        onSave: (_) {},
        onCancel: () => cancelled = true,
      ),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd codingplan_refresh && flutter test test/ui/settings_window_test.dart`
Expected: FAIL（`settings_window.dart` 不存在 / `SettingsApp` 未定义）。

- [ ] **Step 3: 实现 SettingsApp**

创建 `codingplan_refresh/lib/ui/settings_window.dart`：

```dart
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../services/config_service.dart';
import '../services/localization_service.dart';
import '../platform/window_controller.dart' show WindowController;
import 'widgets/config_panel.dart';

/// 设置窗口（独立 OS 窗口内的 widget tree）。
///
/// 自绘极简标题栏（仅 X 关闭=取消）+ 复用 [ConfigPanel]。数据自包含：
/// [configService] 读 config.dat 作为初始编辑态，保存时写盘。不接收主窗口的
/// AppConfig 引用——唯一与主窗口的交互是 [onSave]/[onCancel] 回调（由上层 opener
/// 经 IPC 通知主窗口）。
///
/// [windowController] 用于设置窗口自身隐藏标题栏后的拖动（onPanStart → startDragging）。
class SettingsApp extends StatelessWidget {
  final ConfigService configService;
  final LocalizationService l10n;
  final WindowController windowController;
  final void Function(AppConfig next) onSave;
  final VoidCallback onCancel;

  const SettingsApp({
    super.key,
    required this.configService,
    required this.l10n,
    required this.windowController,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    // load 在 build 期同步读（ConfigService.load 是同步的）；config.dat 已由主窗口
    // 启动时迁移/创建，设置窗口打开时必然存在。
    final initial = configService.load();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF2D2D30),
      ),
      home: Scaffold(
        body: GestureDetector(
          // 设置窗口自身也可拖动（隐藏系统标题栏后）。
          onPanStart: (_) => windowController.startDragging(),
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              _buildTitleBar(),
              Expanded(
                child: ConfigPanel(
                  initial: initial,
                  l10n: l10n,
                  onSave: (next, _) {
                    configService.save(next);
                    onSave(next);
                  },
                  onCancel: onCancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 极简标题栏：仅一个 X 关闭按钮（=取消不保存）。
  Widget _buildTitleBar() {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
            icon: const Icon(Icons.close, color: Color(0xFFAAAAAA), size: 14),
            onPressed: onCancel,
            tooltip: l10n.t('cancel'),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
```

> 说明：`ConfigPanel` 既有签名 `ConfigPanel({required initial, required l10n, required onSave(void Function(AppConfig, bool)), required onCancel, onHeightChanged})`。`onHeightChanged` 设置窗口不传（设置窗口固定尺寸，不靠主窗口收缩）。

- [ ] **Step 4: 给 WindowController 加 `startDragging()`（设置窗口拖动需要）**

修改 `codingplan_refresh/lib/platform/window_controller.dart`，在 `setAlwaysOnTop` 附近加：

```dart
  /// 开始拖动窗口（无系统标题栏时，由自定义手势区触发）。
  Future<void> startDragging() => windowManager.startDragging();
```

（`window_manager` 提供 `startDragging()`。）

- [ ] **Step 5: 跑测试确认通过**

Run: `cd codingplan_refresh && flutter test test/ui/settings_window_test.dart`
Expected: 3 个测试 PASS。
> 若 ConfigPanel 保存按钮文本非「保存」（本地化 key 不同），按实际本地化调整 `find.text('保存')`。

- [ ] **Step 6: 提交**

```bash
git add codingplan_refresh/lib/ui/settings_window.dart \
        codingplan_refresh/lib/platform/window_controller.dart \
        codingplan_refresh/test/ui/settings_window_test.dart
git commit -m "feat(ui): SettingsApp 设置窗口内容（X 关闭栏 + ConfigPanel 复用）"
```

---

### Task 3: 生产 opener 实现 + `main.dart` 多窗口分发（手动验证）

> **本任务涉及 `desktop_multi_window` 0.3.0 真实多窗口 API，无法自动化测试（依赖平台通道）。** 代码基于包公开文档（`WindowController.create(WindowConfiguration)` / `WindowController.fromCurrentEngine()` / `WindowMethodChannel`）；实现期以包安装后的 `example/` 与 README 为准核对 API 名称，本步骤提供完整结构代码 + 手动验证清单。

**Files:**
- Modify: `codingplan_refresh/lib/platform/settings_window_opener.dart`
- Modify: `codingplan_refresh/lib/main.dart`

**Interfaces:**
- Consumes: Task 1 的 `SettingsWindowOpener`、Task 2 的 `SettingsApp`、既有 `_App`/`MainPage`/`ConfigService`/`WindowController`。
- Produces: `DesktopMultiWindowSettingsOpener implements SettingsWindowOpener`（生产）；`main.dart` 多窗口分发。

- [ ] **Step 1: 实现生产 opener**

在 `codingplan_refresh/lib/platform/settings_window_opener.dart` 末尾追加（保留 Task 1 的抽象类）：

```dart
import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 生产实现：用 desktop_multi_window 创建独立设置窗口，关闭经 WindowMethodChannel
/// 回传主窗口。主窗口 windowId 视为 0（首个 engine）。
///
/// 实现期对照 desktop_multi_window 0.3.0 的 example 核对：
/// - WindowController.create(WindowConfiguration(arguments:...)) 的确切字段名
/// - WindowMethodChannel.invokeMethod / setMethodHandler 的签名
class DesktopMultiWindowSettingsOpener implements SettingsWindowOpener {
  static const _mainWindowId = 0;
  static const _methodOnSettingsClosed = 'onSettingsClosed';
  static const _settingsArgs = 'settings';

  void Function(bool saved)? _cb;

  @override
  Future<void> open() async {
    // 注册主窗口侧的方法处理器（收设置窗口回传）。
    await WindowMethodChannel.setMethodHandler(_mainWindowId, (call) async {
      if (call.method == _methodOnSettingsClosed) {
        final saved = (call.arguments as Map?)?['saved'] == true;
        _cb?.call(saved);
      }
      return null;
    });
    // 创建设置窗口（hiddenAtLaunch 先隐藏，show 前设好尺寸/标题栏）。
    final controller = await WindowController.create(WindowConfiguration(
      arguments: _settingsArgs,
      hiddenAtLaunch: true,
    ));
    await controller.setSize(const Size(420, 560));
    await controller.center();
    await controller.show();
  }

  @override
  void onClosed(void Function(bool saved) cb) {
    _cb = cb;
  }

  /// 设置窗口侧调用：通知主窗口关闭结果并关闭自己。
  static Future<void> notifyClosed(WindowController self, bool saved) async {
    await WindowMethodChannel.invokeMethod(
      _mainWindowId,
      _methodOnSettingsClosed,
      {'saved': saved},
    );
    await self.close();
  }
}
```

> 实现期核对点：`WindowConfiguration` 字段（`arguments`/`hiddenAtLaunch`）、`WindowMethodChannel.setMethodHandler`/`invokeMethod` 的参数与 `MethodCall` 形态、`controller.center()` 是否存在（若无则用 `setPosition` 配合屏幕尺寸）。以包 `example/lib/main.dart` 为准。

- [ ] **Step 2: 改 main.dart 多窗口分发**

修改 `codingplan_refresh/lib/main.dart`，把 `main()` 改为按当前 engine 的 arguments 分发主/设置窗口。完整新 `main.dart`：

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'models/app_config.dart';
import 'services/config_service.dart';
import 'services/llm_service.dart';
import 'services/localization_service.dart';
import 'services/log_service.dart';
import 'platform/window_controller.dart';
import 'platform/single_instance.dart';
import 'platform/settings_window_opener.dart';
import 'ui/main_page.dart';
import 'ui/settings_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 子窗口 engine：arguments == 'settings' → 跑设置窗口。
  if (_isSettingsEngine()) {
    await _runSettingsWindow();
    return;
  }

  // 主窗口 engine：单实例检测 + 原有启动流程。
  if (!SingleInstance().ensure()) {
    exit(0);
  }

  final dataDir = await _resolveDataDir();
  final configService = ConfigService(dataDir);
  final log = LogService(dataDir);
  final llm = LlmService(log);
  final l10n = LocalizationService();

  final config = configService.load();
  l10n.initialize(config.language);

  final window = WindowController();
  await window.setup(
    width: ConfigService.widthForLanguage(l10n.current),
    height: ConfigService.expandedHeight,
    alwaysOnTop: config.isAlwaysOnTop,
  );

  runApp(_App(
    config: config,
    configService: configService,
    llm: llm,
    log: log,
    l10n: l10n,
    window: window,
    settingsOpener: DesktopMultiWindowSettingsOpener(),
  ));
}

/// 判断当前 engine 是否为设置窗口（按 desktop_multi_window 的 arguments）。
/// 实现期对照包 API：fromCurrentEngine().arguments 或 parseArguments(args)。
bool _isSettingsEngine() {
  try {
    // desktop_multi_window 0.3.0：当前 engine 控制器可取 arguments。
    return WindowController.fromCurrentEngineSync()?.arguments == 'settings';
  } catch (_) {
    return false;
  }
}

Future<void> _runSettingsWindow() async {
  final dataDir = await _resolveDataDir();
  final configService = ConfigService(dataDir);
  final l10n = LocalizationService();
  l10n.initialize(configService.load().language);
  final self = await WindowController.fromCurrentEngine();
  runApp(SettingsApp(
    configService: configService,
    l10n: l10n,
    windowController: _SettingsWindowController(self),
    onSave: (_) => DesktopMultiWindowSettingsOpener.notifyClosed(self, true),
    onCancel: () => DesktopMultiWindowSettingsOpener.notifyClosed(self, false),
  ));
}

/// 设置窗口内复用主窗口 WindowController 的拖动能力（适配 desktop_multi_window 控制器）。
/// 实现期：若 WindowController 能直接包裹子窗口控制器则简化此类。
class _SettingsWindowController extends WindowController {
  final WindowController _self;
  _SettingsWindowController(this._self);
  @override
  Future<void> startDragging() => _self.startDragging();
}

Future<Directory> _resolveDataDir() async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    final dir = Directory('$appData${Platform.pathSeparator}CodingPlanTimeRefresh');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
  final support = await getApplicationSupportDirectory();
  return support;
}

class _App extends StatelessWidget {
  final AppConfig config;
  final ConfigService configService;
  final LlmService llm;
  final LogService log;
  final LocalizationService l10n;
  final WindowController window;
  final SettingsWindowOpener settingsOpener;
  const _App({
    required this.config,
    required this.configService,
    required this.llm,
    required this.log,
    required this.l10n,
    required this.window,
    required this.settingsOpener,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Coding Plan Time Refresh',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF2D2D30)),
      home: MainPage(
        config: config,
        configService: configService,
        llm: llm,
        log: log,
        l10n: l10n,
        window: window,
        settingsOpener: settingsOpener,
      ),
    );
  }
}
```

> 实现期核对点：`WindowController.fromCurrentEngineSync()`/`fromCurrentEngine()` 是否存在；arguments 取法（`fromCurrentEngine().arguments` vs `parseArguments(args)`）。以包 `example` 为准。`MainPage` 新增 `settingsOpener` 参数（Task 5 接线，本任务先在 `_App` 传入；Task 4/5 改 `MainPage` 构造接收）。
> **注意**：Task 3 改 `_App` 传 `settingsOpener`，但 `MainPage` 构造此时还没该参数 → 会编译失败。故 **Task 3 必须与 Task 4 Step 1（给 MainPage 加 settingsOpener 字段）合并执行**，或在 Task 3 先给 `MainPage` 加可选 `settingsOpener` 参数占位。推荐：Task 3 先在 `MainPage` 加 `final SettingsWindowOpener? settingsOpener;`（可选，本任务不使用），保证编译；Task 5 正式接线。

- [ ] **Step 3: 给 MainPage 加可选 settingsOpener 占位字段（保证 Task 3 编译）**

修改 `codingplan_refresh/lib/ui/main_page.dart`：
- import `'../platform/settings_window_opener.dart'`
- `MainPage` 类加字段 `final SettingsWindowOpener? settingsOpener;`
- `const MainPage({...})` 构造加 `this.settingsOpener,`

（本任务不接线使用，Task 5 接。）

- [ ] **Step 4: 跑全量测试确认编译通过**

Run: `cd codingplan_refresh && flutter test`
Expected: 全部既有测试 PASS（Task 3 未改既有行为，仅加分发与占位字段）。
> 若 `desktop_multi_window` API 不匹配导致编译失败，按 Step 1/2 核对点修正后重跑。

- [ ] **Step 5: 手动验证清单（真实多窗口，Windows）**

发布/运行 `dotnet run` 或 `flutter run -d windows`，验证：
1. 启动主窗口，无系统标题栏（Task 4 后生效；本任务先确认不崩）。
2. （Task 5 接线后）点「设置」→ 弹出独立设置窗口，可独立移动。
3. 设置窗口点「保存」→ 设置窗口关闭 → 主窗口用量刷新为新配置。
4. 设置窗口点「取消」/X → 关闭 → 主窗口不 reload。
5. 设置窗口打开期间，主窗口半透遮罩、不可交互；关闭后恢复。

- [ ] **Step 6: 提交**

```bash
git add codingplan_refresh/lib/platform/settings_window_opener.dart \
        codingplan_refresh/lib/main.dart \
        codingplan_refresh/lib/ui/main_page.dart
git commit -m "feat(main): desktop_multi_window 生产 opener + 多窗口 engine 分发"
```

---

### Task 4: 主窗口顶部栏 4 按钮 + 全界面拖动 + minimize/close + hidden 标题栏

**Files:**
- Modify: `codingplan_refresh/lib/platform/window_controller.dart`（`TitleBarStyle.hidden`、+ `minimize()`/`close()`）
- Modify: `codingplan_refresh/lib/ui/main_page.dart`（`_buildTopBar` 重构、全界面拖动）
- Modify: `codingplan_refresh/test/ui/main_page_test.dart`（FakeWindowController + minimize/close 记录、置顶图标、拖动）

**Interfaces:**
- Consumes: `WindowController.minimize()`/`close()`/`startDragging()`/`setAlwaysOnTop()`。
- Produces: 主窗口隐藏系统标题栏 + 自绘右侧 4 按钮（置顶图标互切/设置占位/最小化/关闭）+ 整个 mini body 可拖动。
- 注：本任务「设置」按钮先 `null`（disabled），Task 5 接 opener。放大态代码本任务**暂保留**（死代码，Task 5 删），保证编译。

- [ ] **Step 1: window_controller 改 hidden + 加 minimize/close**

修改 `codingplan_refresh/lib/platform/window_controller.dart`：
- `setup()` 内 `titleBarStyle: TitleBarStyle.normal` → `titleBarStyle: TitleBarStyle.hidden`。
- 在 `setAlwaysOnTop` 附近加：

```dart
  /// 最小化窗口到任务栏。
  Future<void> minimize() => windowManager.minimize();

  /// 关闭窗口 = 退出应用（主窗口关闭按钮）。
  Future<void> close() => windowManager.close();
```

- [ ] **Step 2: 写失败测试（4 按钮 + 拖动 + 置顶图标互切）**

在 `codingplan_refresh/test/ui/main_page_test.dart` 的 `FakeWindowController` 类内加字段记录：

```dart
  int minimizeCalls = 0;
  int closeCalls = 0;
  int startDraggingCalls = 0;
  @override
  Future<void> minimize() async => minimizeCalls++;
  @override
  Future<void> close() async => closeCalls++;
  @override
  Future<void> startDragging() async => startDraggingCalls++;
```

在 `main()` 测试组末尾加：

```dart
  testWidgets('顶部栏：最小化/关闭按钮触发 window 控制', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k')]),
      window: window,
    ));
    await tester.pump();
    // 最小化（horizontal_rule 图标）。
    await tester.tap(find.byIcon(Icons.horizontal_rule));
    await tester.pump();
    expect(window.minimizeCalls, 1);
    // 关闭（close 图标）。
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(window.closeCalls, 1);
  });

  testWidgets('置顶按钮：未置顶显示 pin_off，点击后切 push_pin + setAlwaysOnTop(true)', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k')], isAlwaysOnTop: false),
      window: window,
    ));
    await tester.pump();
    expect(find.byIcon(Icons.pin_off), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsNothing);
    await tester.tap(find.byIcon(Icons.pin_off));
    await tester.pump();
    expect(window.alwaysOnTop, isTrue);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byIcon(Icons.pin_off), findsNothing);
  });

  testWidgets('mini 界面拖动：onPanStart 触发 startDragging', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k')]),
      window: window,
    ));
    await tester.pump();
    final gesture = await tester.startPointerGesture(
      tester.getCenter(find.byType(Scaffold)),
    );
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(window.startDraggingCalls, greaterThanOrEqualTo(1));
  });
```

> `startPointerGesture` 不可用时改用 `await tester.drag(find.byType(Scaffold), const Offset(10, 0))`。

- [ ] **Step 3: 跑测试确认失败**

Run: `cd codingplan_refresh && flutter test test/ui/main_page_test.dart`
Expected: FAIL（按钮/图标未实现）。

- [ ] **Step 4: 重构 _buildTopBar 为 4 按钮 + mini body 包拖动**

修改 `codingplan_refresh/lib/ui/main_page.dart`：

`_buildTopBar` 整体替换为：

```dart
  /// 顶部栏：右侧 4 按钮（置顶图标互切 / 设置 / 最小化 / 关闭）。左侧留白兼拖动区。
  /// 整个 mini body 在外层已包 GestureDetector(onPanStart: startDragging)，按钮作为
  /// 子节点 tap 优先命中，留白/用量框区域可拖动窗口。
  Widget _buildTopBar() {
    final l = widget.l10n;
    final pinned = _config.isAlwaysOnTop;
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 置顶：两个不同图标互切（pin_off 未置顶 / push_pin 已置顶）。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            tooltip: l.t('pinLabel'),
            icon: Icon(
              pinned ? Icons.push_pin : Icons.pin_off,
              color: pinned ? const Color(0xFF007ACC) : const Color(0xFFAAAAAA),
              size: 14,
            ),
            onPressed: () {
              setState(() => _config.isAlwaysOnTop = !pinned);
              widget.window.setAlwaysOnTop(_config.isAlwaysOnTop);
              widget.configService.save(_config);
            },
          ),
          // 设置（Task 5 接 settingsOpener.open()，此处先 disabled）。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            tooltip: l.t('settings'),
            icon: const Icon(Icons.settings, color: Color(0xFFAAAAAA), size: 14),
            onPressed: null,
          ),
          // 最小化。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            icon: const Icon(Icons.horizontal_rule, color: Color(0xFFAAAAAA), size: 14),
            onPressed: () => widget.window.minimize(),
          ),
          // 关闭 = 退出应用。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            icon: const Icon(Icons.close, color: Color(0xFFAAAAAA), size: 14),
            onPressed: () => widget.window.close(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
```

`_buildMini` 外层包拖动手势——把 `_buildMini` 的 `return Padding(...)` 改为：

```dart
  Widget _buildMini() {
    final l = widget.l10n;
    return GestureDetector(
      // 整个 mini 界面可拖动窗口；按钮 tap 优先命中不影响。
      onPanStart: (_) => widget.window.startDragging(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        key: _contentKey,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _config.providers
                    .map((p) => UsageFrame(
                          result: _usages[p.id] ?? const UsageResult('', [], null),
                          l10n: l,
                          resetText: _resetText,
                          displayName: p.name,
                          isLoading: _usages[p.id] == null,
                          nextTriggerText: _nextTriggerText,
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd codingplan_refresh && flutter test test/ui/main_page_test.dart`
Expected: 含新 3 测试在内的全部 PASS。
> 若既有「齿轮按钮点击→打开 ConfigPanel」测试因设置按钮变 disabled 而失败，先注释/调整该测试（Task 5 设置走新窗口后会重写）。

- [ ] **Step 6: 提交**

```bash
git add codingplan_refresh/lib/platform/window_controller.dart \
        codingplan_refresh/lib/ui/main_page.dart \
        codingplan_refresh/test/ui/main_page_test.dart
git commit -m "feat(ui): 无系统标题栏 + 自绘 4 按钮顶部栏 + 全界面拖动"
```

---

### Task 5: 设置走 opener + 模态遮罩 + reload + 删放大态全组

**Files:**
- Modify: `codingplan_refresh/lib/ui/main_page.dart`（设置按钮接 opener、模态遮罩、`_applyConfig`、删放大态全组、`MainPage.settingsOpener` 改必填）
- Modify: `codingplan_refresh/lib/platform/window_controller.dart`（删 `enlarge`/`shrinkToContent`/`setOpacityForcedActive`、`opacityFor` 去 forcedActive）
- Modify: `codingplan_refresh/test/platform/window_controller_test.dart`（删 forcedActive 相关测试）
- Modify: `codingplan_refresh/test/ui/main_page_test.dart`（删放大态测试、加模态/reload 测试）

**Interfaces:**
- Consumes: `SettingsWindowOpener`（Task 1）、`ConfigService.load()`、`_updateNextTrigger()`（既有）。
- Produces: 设置按钮打开独立设置窗口（模态）；关闭后按 saved reload 配置；放大态全组移除。

- [ ] **Step 1: 写失败测试（模态遮罩 + reload）**

在 `codingplan_refresh/test/ui/main_page_test.dart` 顶部 import：
```dart
import 'package:codingplan_refresh/platform/settings_window_opener.dart';
```
把 `buildApp` 改为注入 fake opener（加参数 `SettingsWindowOpener? settingsOpener`，默认 `FakeSettingsWindowOpener()`）。

在 `main()` 末尾加：

```dart
  testWidgets('点设置 → opener.open + 显遮罩；onClosed(false) → 移遮罩不 reload', (tester) async {
    final window = FakeWindowController();
    final op = FakeSettingsWindowOpener();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k', name: '原名')]),
      window: window,
      settingsOpener: op,
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    expect(op.openCalls, 1);
    expect(find.byType(AbsorbPointer), findsOneWidget); // 模态遮罩生效
    op.simulateClosed(false);
    await tester.pump();
    expect(find.byType(AbsorbPointer), findsNothing); // 遮罩移除
    expect(find.textContaining('原名'), findsWidgets); // 未 reload，原名仍在
  });

  testWidgets('onClosed(true) → reload 配置（文件改后主窗口读取新名）', (tester) async {
    final dir = Directory.systemTemp.createTempSync('cfg5_');
    final cs = ConfigService(dir);
    cs.save(AppConfig(providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k', name: '原名')]));
    final window = FakeWindowController();
    final op = FakeSettingsWindowOpener();
    await tester.pumpWidget(MaterialApp(home: MainPage(
      config: cs.load(),
      configService: cs,
      llm: LlmService(LogService(dir)),
      log: LogService(dir),
      l10n: LocalizationService()..initialize('zh'),
      window: window,
      settingsOpener: op,
    )));
    await tester.pump();
    // 模拟设置窗口写盘改名后回传 saved=true。
    cs.save(AppConfig(providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k', name: '新名')]));
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    op.simulateClosed(true);
    await tester.pump();
    expect(find.textContaining('新名'), findsWidgets);
    dir.deleteSync(recursive: true);
  });
```

> 把 `FakeSettingsWindowOpener` 从 `test/platform/settings_window_opener_test.dart` 提到共享文件 `test/helpers/fake_settings_window_opener.dart` 并在两处 import，避免重复定义。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd codingplan_refresh && flutter test test/ui/main_page_test.dart`
Expected: FAIL（设置按钮 disabled / 无遮罩 / 无 reload）。

- [ ] **Step 3: main_page 接线 opener + 模态遮罩 + _applyConfig + 删放大态**

修改 `codingplan_refresh/lib/ui/main_page.dart`：

(a) `MainPage` 字段 `settingsOpener` 去掉 `?` 改必填（Task 3 已加占位字段）：
```dart
  final SettingsWindowOpener settingsOpener;
```

(b) `_MainPageState` 加模态态字段：
```dart
  bool _settingsOpen = false; // 设置窗口打开期间主窗口模态遮罩
```
initState 末尾注册关闭回调：
```dart
    widget.settingsOpener.onClosed((saved) {
      if (!mounted) return;
      if (saved) {
        _applyConfig(widget.configService.load());
      }
      setState(() => _settingsOpen = false);
    });
```

(c) `_buildTopBar` 的「设置」IconButton `onPressed: null` 改为：
```dart
            onPressed: () {
              setState(() => _settingsOpen = true);
              widget.settingsOpener.open();
            },
```

(d) `build()` 包模态遮罩——改为：
```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: Stack(
        children: [
          _buildMini(),
          // 设置窗口模态：半透遮罩 + 禁用主窗口交互（含拖动/按钮）。
          if (_settingsOpen)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: const AbsorbPointer(),
            ),
        ],
      ),
    );
  }
```
> 删除 `_enlarged ? _buildEnlarged() : _buildMini()` 的三元，直接 `_buildMini()`。

(e) 加 `_applyConfig`（提炼自既有 `_onConfigSaved` 的对齐逻辑）——用新方法替换旧 `_onConfigSaved`：
```dart
  /// 应用（reload 来的）新配置：对齐运行时态、语言、triggerHours，setState 重建。
  void _applyConfig(AppConfig next) {
    final oldIds = _config.providers.map((p) => p.id).toSet();
    final newIds = next.providers.map((p) => p.id).toSet();
    for (final id in oldIds.difference(newIds)) {
      _results.remove(id);
      _usages.remove(id);
      _config.lastTriggerKeys.remove(id);
    }
    for (final id in newIds.difference(oldIds)) {
      _results[id] = ResultState();
    }
    final langChanged = _config.language != next.language;
    setState(() {
      _config = next;
      if (langChanged) widget.l10n.initialize(next.language ?? 'auto');
    });
    widget.configService.save(_config);
    _updateNextTrigger();
    _queryAllUsage();
  }
```

(f) **删除放大态全组**：移除 `_enlarged`、`_lastEnlargedH`、`_enlargedW`、`_enlargedInitH`、`_openEnlarged`、`_closeEnlarged`、`_onConfigHeight`、`_buildEnlarged`、旧 `_onConfigSaved`，及其在 `_resizeToContent`（`if (_enlarged) return`）内的引用。

- [ ] **Step 4: window_controller 删放大态方法 + opacityFor 简化**

修改 `codingplan_refresh/lib/platform/window_controller.dart`：
- 删除 `enlarge`、`shrinkToContent`、`setOpacityForcedActive`、`_forcedActive`、`_lastEnlargedH` 相关。
- `opacityFor` 去掉 `forcedActive` 参数：`static double opacityFor({required bool focused}) => focused ? activeOpacity : inactiveOpacity;`
- `setOpacityByFocus`：`await applyOpacity(opacityFor(focused: focused));`
- `onWindowFocus`/`onWindowBlur` 不变（调 `setOpacityByFocus`）。
- `_screenSize`/`_frameRectForClient`/`_frameOffset`/`_cachedFrameOffset`/`setHeight` 保留（高度自适应仍用）。

- [ ] **Step 5: 更新 window_controller_test（删 forcedActive 测试）**

修改 `codingplan_refresh/test/platform/window_controller_test.dart`：
- 删 `setOpacityForcedActive` 相关 2 个测试。
- `opacityFor` 测试改为两参（focused true/false）。
- `_FakeCtrl` 不再需 forcedActive 相关。

- [ ] **Step 6: 更新 main_page_test（删放大态测试）**

修改 `codingplan_refresh/test/ui/main_page_test.dart`：
- `FakeWindowController` 删 `enlargeCalls`/`shrinkCalls`/`forcedActiveCalls`/`forcedValues`、`enlarge`/`shrinkToContent`/`setOpacityForcedActive` override。
- 删「齿轮→放大态」「ConfigPanel 保存→缩回」「ConfigPanel 取消→缩回」「放大态→setOpacityForcedActive」等放大态测试。
- `_resizeToContent` 相关高度测试若依赖放大态则调整。

- [ ] **Step 7: 跑全量测试**

Run: `cd codingplan_refresh && flutter test`
Expected: 全部 PASS。

- [ ] **Step 8: 手动验证（Windows 真机）**

Run: `cd codingplan_refresh && flutter run -d windows`
验证：① 无系统标题栏、整个界面可拖动；② 4 按钮：置顶图标互切、最小化、关闭=退出、设置弹独立窗口；③ 设置窗口保存→主窗口刷新、取消→不刷新；④ 设置窗口打开期间主窗口半透遮罩不可交互；⑤ 失焦半透仍生效。

- [ ] **Step 9: 提交**

```bash
git add codingplan_refresh/lib/ui/main_page.dart \
        codingplan_refresh/lib/platform/window_controller.dart \
        codingplan_refresh/test/platform/window_controller_test.dart \
        codingplan_refresh/test/ui/main_page_test.dart \
        codingplan_refresh/test/helpers/fake_settings_window_opener.dart
git commit -m "feat(ui): 设置走独立窗口（模态+reload）+ 删放大态全组"
```

---

## Self-Review 记录

- **Spec coverage**：§1 目标 1-6 → Task 4（隐藏/拖动/4按钮/置顶图标）、Task 5（设置独立窗口/模态/reload）、Task 4 close（退出）；§3 窗口模型 → Task 3；§4 全部 → Task 4；§5 全部 → Task 2/3/5；§6 错误处理（创建失败 try-catch、异常关闭兜底）→ Task 3/5 实现期补 try-catch + 关闭事件监听（标注）；§7 测试 → Task 1/2/4/5；§8 改动面 → 各 Task；§9 风险 → Global Constraints + Task 3 标注。
- **异常关闭兜底**：spec §6 要求监听设置窗口 destroyed 兜底移遮罩。Task 3 生产 opener 实现期需补「设置窗口关闭事件」监听（desktop_multi_window 的 onWindowClose 或 destroyed 回调）→ 在 Task 3 Step 1 补注：`notifyClosed` 之外，设置窗口 engine 退出时也确保主窗口收到回调（兜底 saved=false）。已在 Task 3 标注核对点。
- **Placeholder**：Task 3 因 desktop_multi_window API 跨来源不一致，标注「实现期对照包 example」——给完整结构代码，非占位。
- **Type consistency**：`SettingsWindowOpener.open()/onClosed()`、`SettingsApp` 构造、`WindowController.minimize()/close()/startDragging()`、`_applyConfig(AppConfig)` 跨任务签名一致。
