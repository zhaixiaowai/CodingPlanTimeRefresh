import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/llm_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/ui/main_page.dart';

/// 测试替身：把所有 `window_manager` 调用 override 为空，并记录 setHeight /
/// setAlwaysOnTop 入参，避免 widget test 拉起真实窗口。
class FakeWindowController extends WindowController {
  final List<double> heights = [];
  final List<bool> onTop = [];
  @override
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
    required double maxExpandedHeight,
  }) async {}
  @override
  Future<void> setHeight(double width, double h) async => heights.add(h);
  @override
  Future<void> setAlwaysOnTop(bool v) async => onTop.add(v);
  @override
  Future<void> setTitle(String t) async {}
  @override
  Future<void> center() async {}
}

void main() {
  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('ui_'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  // 用一个非空、不含 bigmodel.cn 的 url，避免配置浮层遮挡主内容、且不触发用量网络请求。
  Widget buildApp(FakeWindowController win) => MaterialApp(
        home: MainPage(
          config: AppConfig(apiUrl: 'https://x', apiKey: 'k'),
          configService: ConfigService(tmpDir),
          llm: LlmService(LogService(tmpDir)),
          log: LogService(tmpDir),
          l10n: LocalizationService()..initialize('zh'),
          window: win,
        ),
      );

  testWidgets('置顶 checkbox 触发 setAlwaysOnTop(true)', (tester) async {
    final win = FakeWindowController();
    await tester.pumpWidget(buildApp(win));
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(win.onTop, contains(true));
  });

  testWidgets('点击折叠三角触发 setHeight', (tester) async {
    final win = FakeWindowController();
    await tester.pumpWidget(buildApp(win));
    await tester.pump();
    // 展开态三角为 arrow_drop_up；点击触发折叠 → setHeight 被调用。
    await tester.tap(find.byIcon(Icons.arrow_drop_up).first);
    await tester.pump();
    expect(win.heights, isNotEmpty);
  });
}
