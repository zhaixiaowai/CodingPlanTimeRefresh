import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/llm_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/ui/main_page.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// T1 桩化阶段：`MainPage` 已占位化（旧 checkbox/折叠三角/用量行 UI 移除，
/// 由 T6 重写为 mini 主窗口）。原「置顶 checkbox / 折叠三角」交互测试已不适用，
/// 此处仅验证桩能正常挂载（不抛异常），T6 重写后再补交互用例。
class FakeWindowController extends WindowController {
  @override
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
    required double maxExpandedHeight,
  }) async {}
  @override
  Future<void> setHeight(double width, double h) async {}
  @override
  Future<void> setAlwaysOnTop(bool v) async {}
  @override
  Future<void> setTitle(String t) async {}
  @override
  Future<void> center() async {}
}

void main() {
  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('ui_'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  testWidgets('T1 桩：MainPage 可正常挂载', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MainPage(
        config: AppConfig(
          providers: [
            ProviderConfig(id: 'p1', apiUrl: 'https://x', apiKey: 'k'),
          ],
        ),
        configService: ConfigService(tmpDir),
        llm: LlmService(LogService(tmpDir)),
        log: LogService(tmpDir),
        l10n: LocalizationService()..initialize('zh'),
        window: FakeWindowController(),
      ),
    ));
    await tester.pump();
    expect(find.byType(MainPage), findsOneWidget);
  });
}
