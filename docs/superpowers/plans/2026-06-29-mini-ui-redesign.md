# mini UI 重构 + 删除手动触发 + 触发时刻可配置 + 失焦半透 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已落地的 Flutter 多厂商版上，删掉手动触发、把用量框改造成进度条卡片、让触发时刻可在设置里配置、并让窗口失焦时半透（0.72）、激活时全显（1.0）。

**Architecture:** 增量改造现有 `codingplan_refresh/` Flutter 工程。数据层加 `triggerHours` 并把 `SchedulerService` 参数化；UI 层重构 `UsageFrame` 为 Stack 进度条（百分比内嵌）；`WindowController` 用 `window_manager` 的 `setOpacity` + `WindowListener` 实现焦点透明度（遵循现有「MainPage 只通过 WindowController 触达 window_manager」的可测模式，焦点监听注册放在 `WindowController.setup`，由 `main.dart` 调用，不经 MainPage.initState，避开 widget 测试里 `MissingPluginException`）。

**Tech Stack:** Flutter (Dart), `window_manager ^0.5.1`（`setOpacity` / `isFocused` / `WindowListener.onWindowFocus`+`onWindowBlur`），TDD（`flutter test`）。

## Global Constraints

- 所有注释、文档、回答用中文。
- 仅本地 commit，禁止 push 远端（用户全局规则）。
- 工程根：`D:\My\Project\Common\Other\CodingPlanTimeRefresh\codingplan_refresh\`。所有路径相对该目录。
- 编译/测试命令：`flutter analyze`、`flutter test`、`flutter build windows --release`。
- 透明度常量：失焦 `0.72`、激活 `1.0`（spec §6）。
- 触发时刻默认值 `[1, 7, 13, 19]`，仅整点 0-23，空列表合法（关保活）（spec §5）。
- 进度条配色沿用 `UsageFrame.pctColor`（≥80 红 / ≥50 橙 / 其余蓝）；重置文案沿用 `resetToday`/`resetOther` 本地化资源（spec §3）。
- 删手动触发后保留本地化 key：`loading`/`jokePrompt`/`resultTimestamp`（定时触发 `_callLlmOnce` 仍用）；删除 `manualTrigger`/`manualTriggerPopup`/`waitingPlaceholder`/`resultHeader`（spec §2）。
- mini 窗口宽度 `ConfigService.expandedWidth` 由 `330` 改 `280`（spec §3）。
- macOS 透明度留 TODO（spec §6），本次以 Windows 为准、保证不崩。

---

### Task 1: AppConfig 新增 triggerHours 字段 + 迁移默认

**Files:**
- Modify: `lib/models/app_config.dart`
- Test: `test/models/app_config_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `AppConfig.triggerHours`（`List<int>`，默认 `[1,7,13,19]`）；`AppConfig.fromJson` 读 `TriggerHours` 缺失走默认；`AppConfig.toJson` 写 `TriggerHours`。后续 Task 5/8 依赖此字段。

- [ ] **Step 1: 写失败测试（默认值 + 序列化往返 + 迁移默认）**

在 `test/models/app_config_test.dart` 末尾 `main()` 内追加：

```dart
  test('triggerHours 默认 [1,7,13,19]', () {
    final c = AppConfig(providers: []);
    expect(c.triggerHours, [1, 7, 13, 19]);
  });

  test('triggerHours 序列化往返', () {
    final c = AppConfig(
      providers: [ProviderConfig(id: 'a', name: 'x')],
      triggerHours: [2, 8, 14, 20],
    );
    final loaded = AppConfig.fromJson(c.toJson());
    expect(loaded.triggerHours, [2, 8, 14, 20]);
  });

  test('新格式 JSON 无 TriggerHours → 默认', () {
    final json = <String, dynamic>{
      'Providers': [
        {'Id': 'a', 'Name': 'x', 'ApiUrl': '', 'ApiKey': '', 'Model': 'glm-5.1'}
      ],
      'IsAlwaysOnTop': false,
    };
    final c = AppConfig.fromJson(json);
    expect(c.triggerHours, [1, 7, 13, 19]);
  });

  test('旧单组格式迁移 → triggerHours 默认', () {
    final legacy = <String, dynamic>{
      'ApiUrl': 'https://x', 'ApiKey': 'k', 'Model': 'glm-5.1',
    };
    final c = AppConfig.fromJson(legacy);
    expect(c.triggerHours, [1, 7, 13, 19]);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/models/app_config_test.dart`
Expected: FAIL（`triggerHours` getter 不存在，编译错误）。

- [ ] **Step 3: 实现 triggerHours 字段**

`lib/models/app_config.dart`：在 `AppConfig` 类加字段与默认值。修改类体：

```dart
class AppConfig {
  List<ProviderConfig> providers;
  bool isAlwaysOnTop;
  String? language;
  Map<String, String> lastTriggerKeys;
  /// 定时触发时刻（整点 0-23）。默认 [1,7,13,19]；空列表 = 关闭定时保活。
  List<int> triggerHours;

  AppConfig({
    List<ProviderConfig>? providers,
    this.isAlwaysOnTop = false,
    this.language,
    Map<String, String>? lastTriggerKeys,
    List<int>? triggerHours,
  })  : providers = providers ?? [],
        lastTriggerKeys = lastTriggerKeys ?? {},
        triggerHours = triggerHours ?? const [1, 7, 13, 19];
```

`fromJson` 新格式分支末尾补 `triggerHours`：

```dart
      return AppConfig(
        providers: providers,
        isAlwaysOnTop: json['IsAlwaysOnTop'] as bool? ?? false,
        language: json['Language'] as String?,
        lastTriggerKeys: ltk,
        triggerHours: (json['TriggerHours'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [1, 7, 13, 19],
      );
```

旧单组迁移分支补 `triggerHours: const [1, 7, 13, 19]`（在 `lastTriggerKeys` 后加一行）。

`toJson` 加键：

```dart
  Map<String, dynamic> toJson() => {
        'Providers': providers.map((p) => p.toJson()).toList(),
        'IsAlwaysOnTop': isAlwaysOnTop,
        if (language != null) 'Language': language,
        'LastTriggerKeys': lastTriggerKeys,
        'TriggerHours': triggerHours,
      };
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/models/app_config_test.dart`
Expected: PASS（全部用例，含新增 4 个）。

- [ ] **Step 5: Commit**

```bash
git add lib/models/app_config.dart test/models/app_config_test.dart
git commit -m "feat(config): AppConfig 新增 triggerHours 字段（默认 1/7/13/19）+ 迁移默认"
```

---

### Task 2: SchedulerService 参数化（hours 参数）

**Files:**
- Modify: `lib/services/scheduler_service.dart`
- Test: `test/services/scheduler_service_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `SchedulerService.checkTrigger(DateTime now, String lastKey, [List<int>? hours])` 与 `SchedulerService.nextTrigger(DateTime now, String lastKey, [List<int>? hours])`（`hours` 缺省用 `SchedulerService.defaultTriggerHours`）。Task 8 的 MainPage 调用点传 `_config.triggerHours`。注意：现有调用点（main_page.dart 两处）暂不传 hours 也能编译（可选参数）。

- [ ] **Step 1: 写失败测试（自定义 hours + 空列表 + 保留默认行为）**

`test/services/scheduler_service_test.dart`：现有用例调用 `checkTrigger(now, '')`（2 参）需更新为传 hours，避免歧义。把现有 5 个用例的调用补第三参 `SchedulerService.defaultTriggerHours`，并新增用例：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/scheduler_service.dart';

void main() {
  const def = SchedulerService.defaultTriggerHours;

  test('命中 01:00 且 lastKey 不同 → trigger', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '', def);
    expect(r.trigger, isTrue);
    expect(r.key, '2026-06-25 01:00');
  });

  test('同一 key 已触发过 → 不再触发', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '2026-06-25 01:00', def);
    expect(r.trigger, isFalse);
  });

  test('非触发时段 → 不触发', () {
    final now = DateTime(2026, 6, 25, 2, 30);
    final r = SchedulerService.checkTrigger(now, '', def);
    expect(r.trigger, isFalse);
  });

  test('nextTrigger：当前 00:30 → 当天 01:00', () {
    final now = DateTime(2026, 6, 25, 0, 30);
    final next = SchedulerService.nextTrigger(now, '', def)!;
    expect(next, DateTime(2026, 6, 25, 1, 0));
  });

  test('nextTrigger：当前 23:00 → 次日 01:00', () {
    final now = DateTime(2026, 6, 25, 23, 0);
    final next = SchedulerService.nextTrigger(now, '', def)!;
    expect(next, DateTime(2026, 6, 26, 1, 0));
  });

  test('自定义 hours=[2,14] → 02:00 命中', () {
    final now = DateTime(2026, 6, 25, 2, 0);
    final r = SchedulerService.checkTrigger(now, '', const [2, 14]);
    expect(r.trigger, isTrue);
    expect(r.key, '2026-06-25 02:00');
  });

  test('自定义 hours=[2,14]：当前 01:00 → 当天 02:00', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final next = SchedulerService.nextTrigger(now, '', const [2, 14])!;
    expect(next, DateTime(2026, 6, 25, 2, 0));
  });

  test('空 hours → 永不触发，nextTrigger 为 null', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    expect(SchedulerService.checkTrigger(now, '', const []).trigger, isFalse);
    expect(SchedulerService.nextTrigger(now, '', const []), isNull);
  });

  test('hours 缺省 → 用 defaultTriggerHours（1:00 命中）', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    expect(SchedulerService.checkTrigger(now, '').trigger, isTrue);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/scheduler_service_test.dart`
Expected: FAIL（`defaultTriggerHours` 不存在；旧 `triggerTimes` 仍硬编码）。

- [ ] **Step 3: 参数化实现**

`lib/services/scheduler_service.dart` 全文替换为：

```dart
class SchedulerService {
  /// 默认触发时刻（整点）。AppConfig.triggerHours 缺失时用此作 fallback。
  static const List<int> defaultTriggerHours = [1, 7, 13, 19];

  static String _key(DateTime d, int h, int m) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// 判断 now 是否命中触发时段且本轮未触发。hours 为触发整点列表（0-23），
  /// 缺省用 [defaultTriggerHours]。空 hours 永不触发。
  static ({bool trigger, String key}) checkTrigger(
      DateTime now, String lastKey,
      [List<int>? hours]) {
    final times = hours ?? defaultTriggerHours;
    for (final h in times) {
      if (now.hour == h && now.minute == 0) {
        final key = _key(now, h, 0);
        if (key != lastKey) return (trigger: true, key: key);
      }
    }
    return (trigger: false, key: lastKey);
  }

  /// 计算下一个触发时刻。空 hours → null。缺省用 [defaultTriggerHours]。
  static DateTime? nextTrigger(DateTime now, String lastKey,
      [List<int>? hours]) {
    final times = hours ?? defaultTriggerHours;
    if (times.isEmpty) return null;
    DateTime? next;
    for (final h in times) {
      var target = DateTime(now.year, now.month, now.day, h, 0);
      final key = _key(now, h, 0);
      if (target.isAfter(now) || key != lastKey) {
        if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
        if (next == null || target.isBefore(next)) next = target;
      }
    }
    return next;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/scheduler_service_test.dart`
Expected: PASS（9 用例）。

- [ ] **Step 5: 全量回归 + Commit**

Run: `flutter analyze`（应无新 issue，旧调用点因可选参数仍编译）；`flutter test`
Expected: 全绿。

```bash
git add lib/services/scheduler_service.dart test/services/scheduler_service_test.dart
git commit -m "feat(scheduler): checkTrigger/nextTrigger 收 hours 参数（默认 1/7/13/19，空=关保活）"
```

---

### Task 3: WindowController 失焦半透逻辑（焦点→透明度 + 放大态强制）

**Files:**
- Modify: `lib/platform/window_controller.dart`
- Test: `test/platform/window_controller_test.dart`（新建）

**Interfaces:**
- Consumes: `window_manager`（`setOpacity` / `isFocused` / `WindowListener`）
- Produces: `WindowController` 混入 `WindowListener`；`setOpacityByFocus(bool focused)`、`setOpacityForcedActive(bool forced)`、`onFocusedChanged` 回调、`defaultTriggerHours` 无关。Task 8 的 MainPage 在放大态调用 `setOpacityForcedActive`。`windowManager.addListener(this)` 注册放在 `setup()`（main.dart 调用，不经 widget 测试）。

- [ ] **Step 1: 写失败测试（焦点路由 + 强制覆盖 + 空列表透明度常量）**

新建 `test/platform/window_controller_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// 不触达 window_manager 通道：override setOpacityByFocus 记录 focused 值，
/// 直接调 onWindowFocus/onWindowBlur 验证路由。
class _FakeCtrl extends WindowController {
  bool? lastFocused;
  @override
  Future<void> setOpacityByFocus(bool focused) async {
    lastFocused = focused;
  }
}

void main() {
  test('onWindowFocus → setOpacityByFocus(true)', () {
    final c = _FakeCtrl();
    c.onWindowFocus();
    expect(c.lastFocused, isTrue);
  });

  test('onWindowBlur → setOpacityByFocus(false)', () {
    final c = _FakeCtrl();
    c.onWindowBlur();
    expect(c.lastFocused, isFalse);
  });

  test('onFocusedChanged 回调被触发', () {
    final c = _FakeCtrl();
    bool? got;
    c.onFocusedChanged = (f) => got = f;
    c.onWindowFocus();
    expect(got, isTrue);
    c.onWindowBlur();
    expect(got, isFalse);
  });

  test('setOpacityForcedActive(true) → 强制 true（即使 onWindowBlur 后仍全显）', () async {
    final c = _FakeCtrl();
    await c.setOpacityForcedActive(true);
    expect(c.lastFocused, isTrue);
    c.onWindowBlur(); // 失焦但放大态强制全显
    expect(c.lastFocused, isTrue);
  });

  test('透明度常量：inactive 0.72 / active 1.0', () {
    expect(WindowController.inactiveOpacity, 0.72);
    expect(WindowController.activeOpacity, 1.0);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/platform/window_controller_test.dart`
Expected: FAIL（`setOpacityByFocus`/`setOpacityForcedActive`/`onFocusedChanged`/常量不存在）。

- [ ] **Step 3: 实现 WindowController 透明度**

`lib/platform/window_controller.dart`：类签名加 `with WindowListener`，import 已有 `window_manager`。在类内加常量与字段：

```dart
class WindowController with WindowListener {
  /// 失焦半透常量（spec §6）。
  static const double inactiveOpacity = 0.72;
  static const double activeOpacity = 1.0;
  /// 放大态强制全显覆盖（放大态窗口必须看清，不受失焦半透影响）。
  bool _forcedActive = false;
  /// 焦点变化回调（供 MainPage 订阅做联动，如需要）。
  void Function(bool focused)? onFocusedChanged;
```

在类内（`setAlwaysOnTop` 旁）加方法：

```dart
  /// 按焦点设窗口透明度：focused 或放大态强制 → 1.0，否则 0.72。
  Future<void> setOpacityByFocus(bool focused) async {
    await windowManager
        .setOpacity((focused || _forcedActive) ? activeOpacity : inactiveOpacity);
  }

  /// 放大态强制全显（true）/ 关闭放大态恢复按焦点（false）。
  Future<void> setOpacityForcedActive(bool forced) async {
    _forcedActive = forced;
    if (forced) {
      await setOpacityByFocus(true);
    } else {
      await setOpacityByFocus(await windowManager.isFocused());
    }
  }

  @override
  void onWindowFocus() {
    setOpacityByFocus(true);
    onFocusedChanged?.call(true);
  }

  @override
  void onWindowBlur() {
    setOpacityByFocus(false);
    onFocusedChanged?.call(false);
  }
```

`setup()` 末尾（`setAlwaysOnTop` 之后、`setSize` 之后）注册焦点监听 + 设初始透明度：

```dart
        await windowManager.setSize(Size(width, height));
        // 失焦半透：注册焦点监听，按当前焦点设初始透明度（避启动全显后闪一下）。
        windowManager.addListener(this);
        await setOpacityByFocus(await windowManager.isFocused());
```

`dispose`/清理：WindowController 无 dispose 生命周期（随 app 退出），监听由进程结束回收，不另加 removeListener。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/platform/window_controller_test.dart`
Expected: PASS（5 用例）。

- [ ] **Step 5: 全量回归 + Commit**

Run: `flutter analyze`；`flutter test`
Expected: 全绿（现有 main_page_test 用 FakeWindowController，setup 已 override 为 no-op，不触发真实 addListener）。

```bash
git add lib/platform/window_controller.dart test/platform/window_controller_test.dart
git commit -m "feat(window): 失焦半透 0.72/激活 1.0 + 放大态强制全显（WindowController 焦点路由）"
```

---

### Task 4: UsageFrame 重构为进度条卡片（百分比内嵌 + 重置右侧）

**Files:**
- Modify: `lib/ui/widgets/usage_frame.dart`
- Modify: `lib/services/config_service.dart`（宽度常量 330→280）
- Modify: `lib/platform/window_controller.dart`（`shrinkToContent` 硬编码 330→280）
- Test: `test/ui/widgets/usage_frame_test.dart`

**Interfaces:**
- Consumes: `pctColor`（已有）、`resetText` 回调（已有）、`resetToday`/`resetOther`（已有本地化）
- Produces: `_row` 改为 `label(70,右对齐) + 进度条Stack(内嵌百分比) + 重置时间(右侧)`。

- [ ] **Step 1: 写失败测试（进度条内嵌百分比 + 重置时间右侧 + 无重置不显示）**

`test/ui/widgets/usage_frame_test.dart` 替换为（保留 legend/失败用例，更新行断言）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/widgets/usage_frame.dart';

String _reset(int? ms) {
  if (ms == null) return '';
  // 复用 resetToday 形态：「重置 HH:mm」
  final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  return '重置 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('成功行：进度条内嵌百分比 + 重置时间右侧', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, 1782478364000),
      UsageItem('mcpMonthly', 12, null),
    ], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: _reset)),
    ));
    await tester.pump();
    // legend 标题。
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
    // label。
    expect(find.text('Token(5H)'), findsOneWidget);
    expect(find.text('MCP(月)'), findsOneWidget);
    // 百分比内嵌进度条（textContaining 匹配）。
    expect(find.textContaining('34%'), findsOneWidget);
    expect(find.textContaining('12%'), findsOneWidget);
    // 有重置时间的行显示「重置 HH:mm」；无重置（mcpMonthly）不显示重置。
    expect(find.textContaining('重置'), findsOneWidget);
  });

  testWidgets('nextTriggerText 非空 → legend 标题后接提示', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [UsageItem('token5h', 34, null)], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(
        result: result, l10n: l10n, resetText: _reset,
        nextTriggerText: '下次触发在 19:00',
      )),
    ));
    await tester.pump();
    expect(find.textContaining('智谱 Pro : 下次触发在 19:00'), findsOneWidget);
  });

  testWidgets('nextTriggerText 空 → 仅标题', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [UsageItem('token5h', 34, null)], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(
        result: result, l10n: l10n, resetText: _reset, nextTriggerText: '',
      )),
    ));
    await tester.pump();
    expect(find.textContaining('下次触发'), findsNothing);
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
  });

  testWidgets('失败：显示 errorMessage', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = const UsageResult('火山方舟', [], 'arkcli 未安装，参考 README');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: _reset)),
    ));
    await tester.pump();
    expect(find.text('arkcli 未安装，参考 README'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/widgets/usage_frame_test.dart`
Expected: FAIL（旧 `_row` 三列结构，`34%` 不是独立 Text 进度条内嵌，断言不匹配）。

- [ ] **Step 3: 重构 UsageFrame `_row` 与宽度**

`lib/ui/widgets/usage_frame.dart`：替换 `_row` 方法为进度条版本，并新增 `_progressBar`：

```dart
  Widget _row(UsageItem it) {
    final pct = it.percentage;
    final reset = it.resetAtMs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              l10n.t(it.labelKey),
              textAlign: TextAlign.right,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: _progressBar(pct)),
          const SizedBox(width: 6),
          // 重置时间：null 不显示（不占位）。
          if (reset != null)
            Text(
              '⟳${resetText(reset)}',
              style: const TextStyle(color: Color(0xFF999999), fontSize: 10),
            ),
        ],
      ),
    );
  }

  /// 进度条 + 内嵌百分比文字（Stack：灰底条 + pct 着色填充 + 居中百分比）。
  Widget _progressBar(double pct) {
    final c = pct.clamp(0.0, 100.0);
    return SizedBox(
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 底层灰条。
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF3F3F46),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // 上层 pct 着色填充（按比例宽度）。
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: c / 100.0,
              child: Container(
                decoration: BoxDecoration(
                  color: pctColor(c),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          // 内嵌百分比文字（白色，居中于整条）。
          Text(
            '${c.toStringAsFixed(c == c.roundToDouble() ? 0 : 1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
```

宽度常量 `lib/services/config_service.dart`：

```dart
  static const double expandedWidth = 280;
```

`lib/platform/window_controller.dart` 的 `shrinkToContent` 硬编码 `330` 改 `280`：

```dart
  Future<void> shrinkToContent(double contentHeight) async {
    final frame = await _frameRectForClient(280, contentHeight);
    await windowManager.setSize(Size(280, frame.height));
  }
```

`test/ui/main_page_test.dart` 的 mini 高度自适应用例宽度断言同步改 280（避免 T4 提交时套件留红，宽度改动归 T4 一并完成）：

```dart
    expect(window.lastWidth, 280);
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/widgets/usage_frame_test.dart`
Expected: PASS（4 用例）。

- [ ] **Step 5: 全量回归（含 main_page_test 宽度 280 断言）+ Commit**

Run: `flutter analyze`；`flutter test`
Expected: 全绿（usage_frame 4 用例 + main_page_test 宽度断言已同步改 280，套件不留红）。

```bash
git add lib/ui/widgets/usage_frame.dart lib/services/config_service.dart lib/platform/window_controller.dart test/ui/widgets/usage_frame_test.dart test/ui/main_page_test.dart
git commit -m "feat(ui): UsageFrame 进度条卡片（百分比内嵌 + 重置时间右侧，宽度 280）"
```

---

### Task 5: ConfigPanel 触发时刻网格勾选 + triggerTimesLabel 本地化

**Files:**
- Modify: `lib/services/localization_service.dart`（加 `triggerTimesLabel`）
- Modify: `lib/ui/widgets/config_panel.dart`
- Test: `test/ui/widgets/config_panel_test.dart`

**Interfaces:**
- Consumes: `AppConfig.triggerHours`（Task 1）、`triggerTimesLabel`（本任务加）
- Produces: ConfigPanel 保存的 `AppConfig` 含 `triggerHours`（已选小时升序）。

- [ ] **Step 1: 写失败测试（勾选切换 + 保存写回 triggerHours）**

`test/ui/widgets/config_panel_test.dart` 末尾追加：

```dart
  testWidgets('触发时刻网格：切换并保存写回 triggerHours', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    AppConfig? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [ProviderConfig(id: 'a', name: '智谱')]),
      l10n: l10n,
      onSave: (next, _) => saved = next,
      onCancel: () {},
    ))));
    await tester.pump();
    // 默认勾选 1/7/13/19。取消 7、勾选 8。
    // 每个时刻按钮显示该小时数字。
    await tester.tap(find.text('7').first);
    await tester.pump();
    await tester.tap(find.text('8').first);
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saved!.triggerHours, containsAll([1, 8, 13, 19]));
    expect(saved.triggerHours, isNot(contains(7)));
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/widgets/config_panel_test.dart`
Expected: FAIL（无触发时刻网格，`find.text('7')` 找不到）。

- [ ] **Step 3a: 加 triggerTimesLabel 本地化键**

`lib/services/localization_service.dart` `_table` 内（`pinLabel` 旁）加：

```dart
    // TriggerTimesLabel —— 触发时刻分区标题
    'triggerTimesLabel': {'zh': '触发时刻（整点）', 'en': 'Trigger Hours'},
```

- [ ] **Step 3b: ConfigPanel 加状态 + 网格 UI + 保存写回**

`lib/ui/widgets/config_panel.dart` `_ConfigPanelState`：加状态字段，`initState` 初始化：

```dart
  late Set<int> _triggerHours;
```

`initState` 末尾（`_loadFields` 调用后）加：

```dart
    _triggerHours = Set<int>.from(widget.initial.triggerHours);
```

`build` 内 Column children：在语言切换 `Divider` 之后、`配置列表` 标题之前插入触发时刻分区。找到 `const Divider(color: Color(0xFF555555), height: 16),`（语言切换下方那条）之后插入：

```dart
            // 触发时刻（整点）网格勾选：24 个小时按钮，选中高亮。
            Text(
              l.t('triggerTimesLabel'),
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (int h = 0; h < 24; h++) _hourToggle(h)],
            ),
            const Divider(color: Color(0xFF555555), height: 16),
```

类内加 `_hourToggle`：

```dart
  Widget _hourToggle(int h) {
    final sel = _triggerHours.contains(h);
    return GestureDetector(
      onTap: () => setState(() {
        if (sel) {
          _triggerHours.remove(h);
        } else {
          _triggerHours.add(h);
        }
      }),
      child: Container(
        width: 28,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF007ACC) : const Color(0xFF3C3C3C),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          '$h',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    );
  }
```

`_onSave` 写回 triggerHours：

```dart
  void _onSave() {
    _saveCurrentFields();
    final lang = _langIndex == 1 ? 'zh' : (_langIndex == 2 ? 'en' : 'auto');
    final next = AppConfig(
      providers: _providers,
      isAlwaysOnTop: widget.initial.isAlwaysOnTop,
      language: lang,
      lastTriggerKeys: widget.initial.lastTriggerKeys,
      triggerHours: _triggerHours.toList()..sort(),
    );
    widget.onSave(next, lang != (widget.initial.language ?? 'auto'));
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/widgets/config_panel_test.dart`
Expected: PASS（3 用例）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/localization_service.dart lib/ui/widgets/config_panel.dart test/ui/widgets/config_panel_test.dart
git commit -m "feat(config): 触发时刻网格勾选（24 整点）+ triggerTimesLabel 本地化"
```

---

### Task 6: 删除手动触发（顶部栏齿轮 + 删 trigger 分支 + 删 result_panel + 同步测试 + 宽度断言 280）

**Files:**
- Delete: `lib/ui/widgets/result_panel.dart`
- Delete: `test/ui/widgets/result_panel_test.dart`
- Modify: `lib/ui/main_page.dart`
- Modify: `test/ui/main_page_test.dart`

**Interfaces:**
- Consumes: Task 4 宽度 280
- Produces: 顶部栏 `IconButton(Icons.settings)`；放大态只 ConfigPanel；无 ResultPanel。

- [ ] **Step 1: 写失败测试（齿轮打开 config + 无手动触发项 + 宽度 280）**

`test/ui/main_page_test.dart` 更新：
- 删除 import `result_panel.dart`（第 11 行）。
- 删除「☰ 菜单点击弹出「设置 / 手动触发」菜单项」用例，替换为：

```dart
  testWidgets('齿轮按钮点击 → 打开 ConfigPanel，无「手动触发」菜单项', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    // 顶部齿轮图标按钮。
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(ConfigPanel), findsOneWidget);
    // 不存在「手动触发大模型」菜单项（已删 ☰ 菜单）。
    expect(find.text('手动触发大模型'), findsNothing);
  });
```

- 删除「☰ 菜单「手动触发」→ 放大态 420×520 + 显示 ResultPanel」整条用例。
- 「☰ 菜单「设置」→ 放大态 + 显示 ConfigPanel」用例：把 `find.byType(PopupMenuButton<String>)` 点击改为 `find.byIcon(Icons.settings)`。
- 「放大态关闭按钮 → 缩回 mini」用例：原走手动触发路径，改走 ConfigPanel 取消按钮：

```dart
  testWidgets('ConfigPanel 取消按钮 → 缩回 mini', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(ConfigPanel), findsOneWidget);
    // 点取消（ConfigPanel 内「取消」按钮，文案 cancel=取消）。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(window.shrinkCalls, greaterThanOrEqualTo(1));
    expect(find.byType(ConfigPanel), findsNothing);
    expect(find.byType(UsageFrame), findsOneWidget);
  });
```

- 「ConfigPanel 保存后」用例：`find.byType(PopupMenuButton<String>)` 点击改 `find.byIcon(Icons.settings)`。
- import 顶部删 `result_panel.dart` 后，`ResultPanel` 引用全部清除（grep 确认）。
- 注意：宽度断言 `expect(window.lastWidth, 280)` 已在 Task 4 改好，本任务不动。透明度 override 不在本任务加（归 Task 8）。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/main_page_test.dart`
Expected: FAIL（齿轮不存在，仍 PopupMenuButton；ResultPanel 引用未删）。

- [ ] **Step 3a: 删 result_panel + 其测试**

```bash
git rm codingplan_refresh/lib/ui/widgets/result_panel.dart
git rm codingplan_refresh/test/ui/widgets/result_panel_test.dart
```

- [ ] **Step 3b: main_page.dart 删 trigger 分支 + 顶部栏改齿轮**

`lib/ui/main_page.dart`：
- 删 import `import 'widgets/result_panel.dart';`
- `_buildEnlarged` 改为只返回 ConfigPanel：

```dart
  Widget _buildEnlarged() {
    return ConfigPanel(
      initial: _config,
      l10n: widget.l10n,
      onSave: _onConfigSaved,
      onCancel: _closeEnlarged,
      onHeightChanged: _onConfigHeight,
    );
  }
```

- `_buildTopBar`：把 `PopupMenuButton<String> {...}` 整块替换为齿轮 `IconButton`：

```dart
            IconButton(
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minHeight: 20, minWidth: 20),
              tooltip: '',
              icon: const Icon(Icons.settings, color: Color(0xFFAAAAAA), size: 14),
              onPressed: () => _openEnlarged('config'),
            ),
```

（删掉 `onSelected`/`itemBuilder` 及 `l.t('settings')`/`l.t('manualTrigger')` 引用。`Spacer` 及置顶部分保留。）

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/main_page_test.dart`
Expected: PASS（全部用例）。

- [ ] **Step 5: 全量回归 + Commit**

Run: `flutter analyze`；`flutter test`
Expected: 全绿（含 main_page_test 宽度 280 断言）。

```bash
git add -A codingplan_refresh/
git commit -m "feat(ui): 删除手动触发（齿轮顶部栏 + 删 ResultPanel）+ mini 宽度 280"
```

---

### Task 7: 清理不再使用的本地化 key（manualTrigger / manualTriggerPopup / waitingPlaceholder / resultHeader）

**Files:**
- Modify: `lib/services/localization_service.dart`
- Test: `test/services/localization_service_test.dart`

**Interfaces:**
- Consumes: Task 6 已删 result_panel（唯一消费者）
- Produces: 删 4 key 后 `l10n.t('manualTrigger')` 回退返回键本身。

- [ ] **Step 1: 写失败测试（确认 4 key 已删 + 保留 key 仍在）**

`test/services/localization_service_test.dart`：把用 `resultHeader` 测 zh≠en 的用例改为用仍保留的 `settings` 键：

```dart
  test('zh 与 en 文案不同', () {
    final l = LocalizationService();
    l.initialize('zh');
    final zhText = l.t('settings');
    l.setLanguage('en');
    final enText = l.t('settings');
    expect(zhText, isNot(equals(enText)));
  });
```

末尾追加：

```dart
  test('已删 key 返回 key 本身（manualTrigger 等）', () {
    final l = LocalizationService()..initialize('zh');
    expect(l.t('manualTrigger'), 'manualTrigger');
    expect(l.t('manualTriggerPopup'), 'manualTriggerPopup');
    expect(l.t('waitingPlaceholder'), 'waitingPlaceholder');
    expect(l.t('resultHeader'), 'resultHeader');
  });

  test('保留的定时触发 key 仍可用', () {
    final l = LocalizationService()..initialize('zh');
    expect(l.t('loading'), '调用中...');
    expect(l.t('jokePrompt'), contains('冷笑话'));
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/localization_service_test.dart`
Expected: FAIL（4 key 仍在表里，`l.t('manualTrigger')` 返回「手动触发大模型」≠ 'manualTrigger'）。

- [ ] **Step 3: 删 4 key**

`lib/services/localization_service.dart` `_table` 内删这 4 条（保留 `loading`/`jokePrompt`/`resultTimestamp`/`settings`/`manualTriggerPopup` 删——确认 `manualTriggerPopup` 也删）：

删除条目：
```dart
    'manualTrigger': {...},
    'manualTriggerPopup': {...},
    'waitingPlaceholder': {...},
    'resultHeader': {...},
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/localization_service_test.dart`
Expected: PASS。

- [ ] **Step 5: 全量回归（grep 确认无残留引用）+ Commit**

Run: `flutter analyze`；`flutter test`
Expected: 全绿。
Grep 确认无残留：`grep -rn "manualTrigger\|waitingPlaceholder\|resultHeader" codingplan_refresh/lib codingplan_refresh/test`（应无命中，除测试里「返回 key 本身」用例）。

```bash
git add lib/services/localization_service.dart test/services/localization_service_test.dart
git commit -m "chore(i18n): 删除手动触发相关的 4 个未用本地化 key"
```

---

### Task 8: MainPage 接线（triggerHours 传入 scheduler + 放大态透明度强制）

**Files:**
- Modify: `lib/ui/main_page.dart`

**Interfaces:**
- Consumes: `AppConfig.triggerHours`（T1）、`SchedulerService.checkTrigger/nextTrigger` hours 参数（T2）、`WindowController.setOpacityForcedActive`（T3）
- Produces: 触发时刻配置生效（下个 6s tick 按新时刻判定）；放大态强制全显、关闭恢复按焦点。

- [ ] **Step 1: 写失败测试（放大态强制全显 + 关闭恢复）**

`test/ui/main_page_test.dart` 末尾追加。先给 `FakeWindowController` 加 `setOpacityForcedActive` override（带记录字段，本任务首次添加——MainPage 在放大态开启/关闭时调用此方法）：

```dart
  int forcedActiveCalls = 0;
  List<bool> forcedValues = [];
  @override
  Future<void> setOpacityForcedActive(bool forced) async {
    forcedActiveCalls++;
    forcedValues.add(forced);
  }
```

用例：

```dart
  testWidgets('打开放大态 → setOpacityForcedActive(true)，关闭 → false', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    // 打开放大态 → 强制全显。
    expect(window.forcedValues, contains(true));
    // 关闭（取消）→ 恢复按焦点。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(window.forcedValues, contains(false));
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/ui/main_page_test.dart`
Expected: FAIL（`_openEnlarged`/`_closeEnlarged` 未调 `setOpacityForcedActive`，`forcedValues` 为空）。

- [ ] **Step 3: main_page.dart 接线**

`lib/ui/main_page.dart`：
- `_openEnlarged`：在 `enlarge` 后、`setState` 前加强制全显：

```dart
  Future<void> _openEnlarged(String mode) async {
    await widget.window.enlarge(w: _enlargedW, h: _enlargedInitH);
    if (!mounted) return;
    await widget.window.setOpacityForcedActive(true);
    _lastEnlargedH = 0;
    setState(() {
      _enlarged = true;
      _enlargedMode = mode;
    });
  }
```

- `_closeEnlarged`：在 `shrinkToContent` 后加恢复：

```dart
  Future<void> _closeEnlarged() async {
    setState(() {
      _enlarged = false;
      _enlargedMode = null;
    });
    await widget.window.shrinkToContent(_lastContentHeight);
    await widget.window.setOpacityForcedActive(false);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
    }
  }
```

- `_onTriggerTick`：传 `_config.triggerHours`：

```dart
    final r = SchedulerService.checkTrigger(
      DateTime.now(),
      _globalTriggerKey(),
      _config.triggerHours,
    );
```

- `_updateNextTrigger`：传 `_config.triggerHours`：

```dart
    final next = SchedulerService.nextTrigger(
      DateTime.now(),
      _globalTriggerKey(),
      _config.triggerHours,
    );
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/ui/main_page_test.dart`
Expected: PASS。

- [ ] **Step 5: 全量回归 + Release 构建 + Commit**

Run: `flutter analyze`；`flutter test`；`flutter build windows --release`
Expected: 全绿；构建成功。

```bash
git add codingplan_refresh/lib/ui/main_page.dart codingplan_refresh/test/ui/main_page_test.dart
git commit -m "feat(ui): 触发时刻配置生效 + 放大态强制全显/关闭恢复按焦点"
```

---

## 自检

**Spec 覆盖（§1-9）：**
- §2 删手动触发 → Task 6（删 result_panel + 齿轮）+ Task 7（删 i18n key）。✓
- §3 UsageFrame 进度条卡片 → Task 4。✓
- §4 顶部栏简化 → Task 6（齿轮）。✓
- §5 触发时刻可配置 → Task 1（数据）+ Task 2（scheduler 参数）+ Task 5（UI 网格）+ Task 8（接线）。✓
- §6 失焦半透 → Task 3（WindowController 逻辑）+ Task 8（放大态强制接线）。✓
- §7 改动文件清单 → 全覆盖（usage_frame/main_page/result_panel 删/app_config/scheduler/config_panel/window_controller/localization/各 test）。✓
- §8 风险对策 → 启动闪烁（T3 initState 由 setup 设初始透明度）、放大态半透（T8 forcedActive）、误删 key（T7 grep 核实 + 保留 loading/jokePrompt/resultTimestamp）。✓
- §9 非目标 → 未越界（不改放大态尺寸机制、不做分钟级、透明度阈值固定不设项）。✓

**占位符扫描：** 无 TBD/TODO（macOS 透明度留 TODO 在代码注释，非计划占位）。✓

**类型一致性：** `triggerHours: List<int>`（T1 定义）→ T5 保存 `_triggerHours.toList()..sort()` → T8 读取 `_config.triggerHours` 传入 `checkTrigger(DateTime, String, [List<int>?])`（T2 签名）。`setOpacityByFocus(bool)`/`setOpacityForcedActive(bool)`（T3 定义）→ T8 调用。`WindowController.inactiveOpacity/activeOpacity`（T3）→ T3 测试引用。命名一致。✓
