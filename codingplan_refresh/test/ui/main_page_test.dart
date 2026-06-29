import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/llm_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/ui/main_page.dart';
// T4: ConfigPanel 入口测试已停用，import 暂注释避免 unused 警告（Task 5 恢复）。
// import 'package:codingplan_refresh/ui/widgets/config_panel.dart';
import 'package:codingplan_refresh/ui/widgets/usage_frame.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// T6 mini 多框测试：验证每 provider 一个 UsageFrame、齿轮按钮打开 ConfigPanel、
/// 置顶 checkbox 触发 setAlwaysOnTop。
///
/// 用 [FakeWindowController]（extends WindowController override 全部平台调用）
/// 注入；providers 的 apiUrl 用非 bigmodel / 非 ark 域名，使 [_providerFor]
/// 返回 null → 显示「未知厂商」，避免真实网络 / arkcli 调用。
class FakeWindowController extends WindowController {
  double? lastWidth;
  double? lastHeight;
  double? enlargedW;
  double? enlargedH;
  double? shrunkH;
  bool? alwaysOnTop;
  int setHeightCalls = 0;
  int setAlwaysOnTopCalls = 0;
  int enlargeCalls = 0;
  int shrinkCalls = 0;
  int forcedActiveCalls = 0;
  List<bool> forcedValues = [];
  // T4: minimize/close/startDragging 调用计数。
  int minimizeCalls = 0;
  int closeCalls = 0;
  int startDraggingCalls = 0;

  @override
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
  }) async {}

  @override
  Future<void> setHeight(double width, double h) async {
    lastWidth = width;
    lastHeight = h;
    setHeightCalls++;
  }

  @override
  Future<void> enlarge({required double w, required double h}) async {
    enlargedW = w;
    enlargedH = h;
    enlargeCalls++;
  }

  @override
  Future<void> shrinkToContent(double contentHeight, double width) async {
    shrunkH = contentHeight;
    shrinkCalls++;
  }

  @override
  Future<void> setAlwaysOnTop(bool v) async {
    alwaysOnTop = v;
    setAlwaysOnTopCalls++;
  }

  @override
  Future<void> setOpacityForcedActive(bool forced) async {
    forcedActiveCalls++;
    forcedValues.add(forced);
  }

  @override
  Future<void> setTitle(String t) async {}

  @override
  Future<void> center() async {}

  @override
  Future<void> minimize() async => minimizeCalls++;

  @override
  Future<void> close() async => closeCalls++;

  @override
  Future<void> startDragging() async => startDraggingCalls++;
}

void main() {
  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('ui_'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  /// 构造一个最小可挂载的 MainPage（url 非 bigmodel / 非 ark → 无 provider 调用）。
  Widget buildApp({
    required AppConfig config,
    required FakeWindowController window,
  }) {
    return MaterialApp(
      home: MainPage(
        config: config,
        configService: ConfigService(tmpDir),
        llm: LlmService(LogService(tmpDir)),
        log: LogService(tmpDir),
        l10n: LocalizationService()..initialize('zh'),
        window: window,
      ),
    );
  }

  testWidgets('多 provider → 渲染多个 UsageFrame（每 provider 一个）', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [
            ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
            ProviderConfig(id: 'p2', apiUrl: 'https://y', apiKey: 'k'),
          ],
        ),
        window: window,
      ),
    );
    await tester.pump();
    // 2 个 provider 应渲染 2 个 UsageFrame。
    expect(find.byType(UsageFrame), findsNWidgets(2));
    // 未知厂商文案应各显示一次。
    expect(find.text('未知厂商，不支持用量查询'), findsNWidgets(2));
  });

  // T4: 设置按钮本任务 disabled（Task 5 接 settingsOpener 走新窗口后重写）。
  // 置顶由 Checkbox 改为 IconButton 图标互切（见下方 T4 新测试）。原「齿轮按钮点击 →
  // 打开 ConfigPanel」「置顶 checkbox」两个测试用例覆盖的入口已变化，注释删除。
  // testWidgets('齿轮按钮点击 → 打开 ConfigPanel，无「手动触发」菜单项', (tester) async {
  //   ...
  // });
  // testWidgets('置顶 checkbox → 触发 window.setAlwaysOnTop + save', (tester) async {
  //   ...
  // });

  testWidgets('未知厂商 url：_providerFor 返回 null，无 provider 调用', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [
            ProviderConfig(
              id: 'p1',
              apiUrl: 'https://example.com',
              apiKey: 'k',
            ),
          ],
        ),
        window: window,
      ),
    );
    await tester.pump();
    // 非 bigmodel / 非 ark → 显示「未知厂商」，不会触发 HTTP / arkcli。
    expect(find.text('未知厂商，不支持用量查询'), findsOneWidget);
  });

  // ===== T8 放大态测试（T4 临时停用）=====
  // 设置按钮本任务 disabled（onPressed:null），3 个放大态测试都靠 tap(Icons.settings)
  // 进入放大态——入口已断，测试会失败。放大态代码本身保留（_openEnlarged 等），
  // Task 5 设置走新窗口后会重写这组测试。整体块注释保留待恢复参考。
  /*
  testWidgets('齿轮「设置」→ 放大态 + 显示 ConfigPanel', (tester) async {
    ...
  });

  testWidgets('ConfigPanel 保存后 → _results/_usages 同步 + 缩回 mini', (
    tester,
  ) async {
    ...
  });

  testWidgets('ConfigPanel 取消按钮 → 缩回 mini', (tester) async {
    ...
  });
  */

  // ===== mini 高度自适应回归测试 =====

  testWidgets('mini 高度自适应：多 provider 渲染后 setHeight 被调且高度 < 520', (
    tester,
  ) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [
            ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
            ProviderConfig(id: 'p2', apiUrl: 'https://y', apiKey: 'k'),
          ],
        ),
        window: window,
      ),
    );
    // pump 触发首帧 + initState 末尾的 PostFrameCallback(_resizeToContent)；
    // 再 pump 一次触发 _queryAllUsage 末尾排的 PostFrameCallback（未知厂商同步完成）。
    await tester.pump();
    await tester.pump();
    // setHeight 应被调用（mini 高度自适应量到实际内容高）。
    expect(window.setHeightCalls, greaterThanOrEqualTo(1));
    // 高度应是实际内容高（顶部栏 + 2 个 UsageFrame），不是启动高 520 / 测试 surface 600。
    // 修复前量 Scaffold（=600）会在此断言失败；修复后量内容（~120-180）通过。
    expect(window.lastHeight, lessThan(520));
    expect(window.lastHeight, greaterThan(50));
    // 宽度统一英文版宽度 expandedWidth=260（曾按语言中文 230 过窄、标题栏无法拖动）。
    expect(window.lastWidth, ConfigService.expandedWidth);
  });

  // ===== T8 放大态强制全显接线（T4 临时停用：入口已断，见上方说明）=====
  /*
  testWidgets('打开放大态 → setOpacityForcedActive(true)，关闭 → false', (
    tester,
  ) async {
    ...
  });
  */

  // ===== T4 顶部栏 4 按钮 + 全界面拖动 =====

  testWidgets('顶部栏：最小化/关闭按钮触发 window 控制', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k')],
        ),
        window: window,
      ),
    );
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

  testWidgets(
    '置顶按钮：未置顶显示 push_pin_outlined，点击切 push_pin + setAlwaysOnTop(true)',
    (tester) async {
      final window = FakeWindowController();
      await tester.pumpWidget(
        buildApp(
          config: AppConfig(
            providers: [
              ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
            ],
            isAlwaysOnTop: false,
          ),
          window: window,
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsNothing);
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pump();
      expect(window.alwaysOnTop, isTrue);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    },
  );

  testWidgets('mini 界面拖动：拖动手势触发 startDragging', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k')],
        ),
        window: window,
      ),
    );
    await tester.pump();
    // 在顶部栏（SizedBox height:22）的左侧留白区发起 dragFrom：该区为 Row 的
    // MainAxisAlignment.end 留白，无子控件，避免与 IconButton/UsageFrame 命中竞争。
    // dragFrom 跨过 touch slop 触发外层 GestureDetector.onPanStart → startDragging。
    final topBarBox = tester.getRect(find.byType(SizedBox).first);
    await tester.dragFrom(
      Offset(topBarBox.left + 4, topBarBox.top + 11),
      const Offset(20, 20),
    );
    expect(window.startDraggingCalls, greaterThanOrEqualTo(1));
  });
}
