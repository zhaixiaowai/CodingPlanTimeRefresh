import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/settings_window.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// Task 2 测试：SettingsApp 自绘 X 关闭栏 + 复用 ConfigPanel。
///
/// 用 [FakeWindowController] 注入（绕开真实 windowManager channel），
/// 验证：(1) 加载 config.dat 作为 ConfigPanel initial；
/// (2) 点保存 → 写盘 + 触发 onSave(next)；(3) 点 X → 触发 onCancel。
class FakeWindowController extends WindowController {
  int startDraggingCalls = 0;

  @override
  Future<void> startDragging() async {
    startDraggingCalls++;
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('settings_'));
  tearDown(() => dir.deleteSync(recursive: true));

  ConfigService cs() => ConfigService(dir);
  AppConfig seeded(String name) =>
      AppConfig(providers: [ProviderConfig(id: 'p1', name: name, apiUrl: 'https://x', apiKey: 'k')]);

  testWidgets('加载 config.dat 作为 ConfigPanel initial，显示已存 provider 名', (tester) async {
    cs().save(seeded('智谱'));
    final l10n = LocalizationService()..initialize('zh');
    await tester.pumpWidget(SettingsApp(
      configService: cs(),
      l10n: l10n,
      windowController: FakeWindowController(),
      onSave: (_) {},
      onCancel: () {},
    ));
    await tester.pump();
    expect(find.textContaining('智谱'), findsWidgets);
  });

  testWidgets('点保存 → 写盘 + 触发 onSave(next)', (tester) async {
    final svc = cs();
    svc.save(seeded('旧名'));
    final l10n = LocalizationService()..initialize('zh');
    AppConfig? saved;
    await tester.pumpWidget(SettingsApp(
      configService: svc,
      l10n: l10n,
      windowController: FakeWindowController(),
      onSave: (next) => saved = next,
      onCancel: () {},
    ));
    await tester.pumpAndSettle();
    // 点 ConfigPanel 的「保存」按钮（本地化 key 'save' = '保存'）。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    // 写盘成功：重新 load 拿到的是保存后的内容（providers 结构一致）。
    expect(svc.load().providers.length, saved!.providers.length);
  });

  testWidgets('点 X 关闭 → 触发 onCancel（不保存）', (tester) async {
    cs().save(seeded('x'));
    final l10n = LocalizationService()..initialize('zh');
    bool cancelled = false;
    await tester.pumpWidget(SettingsApp(
      configService: cs(),
      l10n: l10n,
      windowController: FakeWindowController(),
      onSave: (_) {},
      onCancel: () => cancelled = true,
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
  });
}
