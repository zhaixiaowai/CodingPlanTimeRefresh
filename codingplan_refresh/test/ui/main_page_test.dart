import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/llm_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/ui/main_page.dart';
import 'package:codingplan_refresh/ui/widgets/usage_frame.dart';
// 置顶图标断言用 Symbols.push_pin / Symbols.offline_pin_off（与 main_page.dart 同源）。
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';
import 'package:codingplan_refresh/ui/widgets/config_panel.dart';

/// mini 多框测试：验证每 provider 一个 UsageFrame、置顶按钮触发 setAlwaysOnTop、
/// 设置走独立窗口（模态遮罩 + reload）。
///
/// 用 [FakeWindowController]（extends WindowController override 全部平台调用）
/// 注入；providers 的 apiUrl 用非 bigmodel / 非 ark 域名，使 [_providerFor]
/// 返回 null → 显示「未知厂商」，避免真实网络 / arkcli 调用。
class FakeWindowController extends WindowController {
  double? lastWidth;
  double? lastHeight;
  bool? alwaysOnTop;
  int setHeightCalls = 0;
  int setAlwaysOnTopCalls = 0;
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
  Future<void> setAlwaysOnTop(bool v) async {
    alwaysOnTop = v;
    setAlwaysOnTopCalls++;
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
    expect(window.lastHeight, lessThan(520));
    expect(window.lastHeight, greaterThan(50));
    // 宽度统一英文版宽度 expandedWidth=260（曾按语言中文 230 过窄、标题栏无法拖动）。
    expect(window.lastWidth, ConfigService.expandedWidth);
  });

  // ===== T4 顶部栏 4 按钮 + 全界面拖动 =====

  testWidgets('顶部栏：最小化/关闭按钮触发 window 控制', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [
            ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
          ],
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
    '置顶按钮：未置顶显示 offline_pin_off，点击切 push_pin + setAlwaysOnTop(true)',
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
      expect(find.byIcon(Symbols.offline_pin_off), findsOneWidget);
      expect(find.byIcon(Symbols.push_pin), findsNothing);
      await tester.tap(find.byIcon(Symbols.offline_pin_off));
      await tester.pump();
      expect(window.alwaysOnTop, isTrue);
      expect(find.byIcon(Symbols.push_pin), findsOneWidget);
      expect(find.byIcon(Symbols.offline_pin_off), findsNothing);
    },
  );

  testWidgets('mini 界面拖动：拖动手势触发 startDragging', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [
            ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
          ],
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

  // ===== 设置视图原地切换（方案 B：窗口内 mini ↔ ConfigPanel）=====

  testWidgets('点设置 → 切到 ConfigPanel 视图；X 关闭 → 切回 mini', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [
            ProviderConfig(
              id: 'p1',
              apiUrl: 'https://x',
              apiKey: 'k',
              name: '原名',
            ),
          ],
        ),
        window: window,
      ),
    );
    await tester.pump();
    expect(find.byType(UsageFrame), findsOneWidget); // mini 态
    expect(find.byType(ConfigPanel), findsNothing);
    // 点设置 → 切到 ConfigPanel 视图（窗口内原地切换，非独立窗口）。
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    expect(find.byType(ConfigPanel), findsOneWidget);
    // X 关闭 → 切回 mini。
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byType(ConfigPanel), findsNothing);
    expect(find.byType(UsageFrame), findsOneWidget);
  });
}
