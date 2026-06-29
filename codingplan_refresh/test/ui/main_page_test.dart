import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/llm_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/ui/main_page.dart';
import 'package:codingplan_refresh/ui/widgets/config_panel.dart';
import 'package:codingplan_refresh/ui/widgets/result_panel.dart';
import 'package:codingplan_refresh/ui/widgets/usage_frame.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// T6 mini 多框测试：验证每 provider 一个 UsageFrame、☰ 菜单弹出菜单项、
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
  Future<void> shrinkToContent(double contentHeight) async {
    shrunkH = contentHeight;
    shrinkCalls++;
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

  testWidgets('多 provider → 渲染多个 UsageFrame（每 provider 一个）',
      (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
        ProviderConfig(id: 'p2', apiUrl: 'https://y', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    // 2 个 provider 应渲染 2 个 UsageFrame。
    expect(find.byType(UsageFrame), findsNWidgets(2));
    // 未知厂商文案应各显示一次。
    expect(find.text('未知厂商，不支持用量查询'), findsNWidgets(2));
  });

  testWidgets('☰ 菜单点击弹出「设置 / 手动触发」菜单项', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    // 点击 ☰ 菜单按钮（PopupMenuButton 内的 icon）。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('手动触发大模型'), findsOneWidget);
  });

  testWidgets('置顶 checkbox → 触发 window.setAlwaysOnTop + save', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(
        providers: [
          ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
        ],
        isAlwaysOnTop: false,
      ),
      window: window,
    ));
    await tester.pump();
    expect(window.alwaysOnTop, isNull);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    // checkbox 切换后应调用 setAlwaysOnTop(true)。
    expect(window.alwaysOnTop, isTrue);
    expect(window.setAlwaysOnTopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('未知厂商 url：_providerFor 返回 null，无 provider 调用',
      (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://example.com', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    // 非 bigmodel / 非 ark → 显示「未知厂商」，不会触发 HTTP / arkcli。
    expect(find.text('未知厂商，不支持用量查询'), findsOneWidget);
  });

  // ===== T8 放大态测试 =====

  testWidgets('☰ 菜单「手动触发」→ 放大态 420×520 + 显示 ResultPanel', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    expect(window.enlargeCalls, 0);
    // 点击 ☰ → 「手动触发大模型」。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动触发大模型'));
    await tester.pumpAndSettle();
    // 应调用 enlarge(420, 520)。
    expect(window.enlargeCalls, 1);
    expect(window.enlargedW, 420);
    expect(window.enlargedH, 520);
    // 放大态应显示 ResultPanel（触发按钮文案 manualTriggerPopup）。
    expect(find.byType(ResultPanel), findsOneWidget);
  });

  testWidgets('☰ 菜单「设置」→ 放大态 + 显示 ConfigPanel', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', name: '智谱', apiUrl: 'https://x', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(window.enlargeCalls, 1);
    expect(find.byType(ConfigPanel), findsOneWidget);
    // mini 态的 UsageFrame 应消失。
    expect(find.byType(UsageFrame), findsNothing);
  });

  testWidgets('ConfigPanel 保存后 → _results/_usages 同步 + 缩回 mini',
      (tester) async {
    final window = FakeWindowController();
    final dir = Directory.systemTemp.createTempSync('cfg_');
    try {
      final cs = ConfigService(dir);
      await tester.pumpWidget(MaterialApp(
        home: MainPage(
          config: AppConfig(providers: [
            ProviderConfig(id: 'p1', name: '智谱', apiUrl: 'https://x', apiKey: 'k'),
            ProviderConfig(id: 'p2', name: '火山', apiUrl: 'https://y', apiKey: 'k'),
          ]),
          configService: cs,
          llm: LlmService(LogService(dir)),
          log: LogService(dir),
          l10n: LocalizationService()..initialize('zh'),
          window: window,
        ),
      ));
      await tester.pump();
      // 进设置放大态。
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      // 删除 p2（点其「删除」→ 确认）。
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      // 点保存。
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 应缩回（shrinkToContent 被调用）。
      expect(window.shrinkCalls, greaterThanOrEqualTo(1));
      // mini 态只剩 1 个 UsageFrame（p2 已删）。
      expect(find.byType(UsageFrame), findsOneWidget);
      // 配置文件应持久化（含 1 个 provider）。
      final saved = cs.load();
      expect(saved.providers.length, 1);
      expect(saved.providers.first.id, 'p1');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('放大态关闭按钮 → 缩回 mini 保留状态', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
      ]),
      window: window,
    ));
    await tester.pump();
    // 进手动触发放大态。
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动触发大模型'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultPanel), findsOneWidget);
    // 点关闭（IconButton(Icons.close)）。
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    // 应缩回，mini 态恢复 UsageFrame。
    expect(window.shrinkCalls, greaterThanOrEqualTo(1));
    expect(find.byType(ResultPanel), findsNothing);
    expect(find.byType(UsageFrame), findsOneWidget);
  });

  // ===== mini 高度自适应回归测试 =====

  testWidgets('mini 高度自适应：多 provider 渲染后 setHeight 被调且高度 < 520',
      (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(buildApp(
      config: AppConfig(providers: [
        ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
        ProviderConfig(id: 'p2', apiUrl: 'https://y', apiKey: 'k'),
      ]),
      window: window,
    ));
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
    // 宽度固定 280。
    expect(window.lastWidth, 280);
  });
}
