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

  testWidgets('齿轮按钮点击 → 打开 ConfigPanel，无「手动触发」菜单项', (tester) async {
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
    // 顶部齿轮图标按钮。
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(ConfigPanel), findsOneWidget);
    // 不存在「手动触发大模型」菜单项（已删 ☰ 菜单）。
    expect(find.text('手动触发大模型'), findsNothing);
  });

  testWidgets('置顶 checkbox → 触发 window.setAlwaysOnTop + save', (tester) async {
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
    expect(window.alwaysOnTop, isNull);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    // checkbox 切换后应调用 setAlwaysOnTop(true)。
    expect(window.alwaysOnTop, isTrue);
    expect(window.setAlwaysOnTopCalls, greaterThanOrEqualTo(1));
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

  // ===== T8 放大态测试 =====

  testWidgets('齿轮「设置」→ 放大态 + 显示 ConfigPanel', (tester) async {
    final window = FakeWindowController();
    await tester.pumpWidget(
      buildApp(
        config: AppConfig(
          providers: [
            ProviderConfig(
              id: 'p1',
              name: '智谱',
              apiUrl: 'https://x',
              apiKey: 'k',
            ),
          ],
        ),
        window: window,
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(window.enlargeCalls, 1);
    expect(find.byType(ConfigPanel), findsOneWidget);
    // mini 态的 UsageFrame 应消失。
    expect(find.byType(UsageFrame), findsNothing);
  });

  testWidgets('ConfigPanel 保存后 → _results/_usages 同步 + 缩回 mini', (
    tester,
  ) async {
    final window = FakeWindowController();
    final dir = Directory.systemTemp.createTempSync('cfg_');
    try {
      final cs = ConfigService(dir);
      await tester.pumpWidget(
        MaterialApp(
          home: MainPage(
            config: AppConfig(
              providers: [
                ProviderConfig(
                  id: 'p1',
                  name: '智谱',
                  apiUrl: 'https://x',
                  apiKey: 'k',
                ),
                ProviderConfig(
                  id: 'p2',
                  name: '火山',
                  apiUrl: 'https://y',
                  apiKey: 'k',
                ),
              ],
            ),
            configService: cs,
            llm: LlmService(LogService(dir)),
            log: LogService(dir),
            l10n: LocalizationService()..initialize('zh'),
            window: window,
          ),
        ),
      );
      await tester.pump();
      // 进设置放大态。
      await tester.tap(find.byIcon(Icons.settings));
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

  testWidgets('ConfigPanel 取消按钮 → 缩回 mini', (tester) async {
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
    // 宽度按语言：中文（测试 initialize 'zh'）= 230。
    expect(window.lastWidth, 230);
  });

  // ===== T8 放大态强制全显接线 =====

  testWidgets('打开放大态 → setOpacityForcedActive(true)，关闭 → false', (
    tester,
  ) async {
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
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    // 打开放大态 → 强制全显。
    expect(window.forcedValues, contains(true));
    // 关闭（取消）→ 恢复按焦点。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(window.forcedValues, contains(false));
  });

  // ===== 顶部栏失焦 Opacity 隐去 =====

  testWidgets('失焦 → 顶部栏 Opacity 0，聚焦 → 1.0', (tester) async {
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
    Opacity findTopBarOpacity() => tester.widget<Opacity>(
      find.ancestor(of: find.byIcon(Icons.settings), matching: find.byType(Opacity))
          .first,
    );
    // 初始 _focused=true → 顶部栏 Opacity 1.0。
    expect(findTopBarOpacity().opacity, 1.0);
    // 模拟失焦 → 顶部栏 Opacity 0（齿轮+置顶隐去）。
    window.onFocusedChanged?.call(false);
    await tester.pump();
    expect(findTopBarOpacity().opacity, 0.0);
    // 恢复聚焦 → Opacity 1.0。
    window.onFocusedChanged?.call(true);
    await tester.pump();
    expect(findTopBarOpacity().opacity, 1.0);
  });
}
