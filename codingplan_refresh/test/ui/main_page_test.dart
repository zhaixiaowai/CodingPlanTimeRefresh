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
  bool? alwaysOnTop;
  int setHeightCalls = 0;
  int setAlwaysOnTopCalls = 0;

  @override
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
    required double maxExpandedHeight,
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
}
