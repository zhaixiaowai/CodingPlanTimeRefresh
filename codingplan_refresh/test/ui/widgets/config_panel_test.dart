import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/widgets/config_panel.dart';

void main() {
  testWidgets('新增一个 provider', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    var saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [ProviderConfig(id: 'a', name: '智谱')]),
      l10n: l10n,
      onSave: (next, _) => saved = next,
      onCancel: () {},
    ))));
    await tester.pump();
    await tester.tap(find.text('新增'));
    await tester.pump();
    expect(find.text('新配置'), findsOneWidget); // 追加默认名
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saved.providers.length, 2);
  });

  testWidgets('删除需确认', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    var saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [ProviderConfig(id: 'a', name: '智谱'), ProviderConfig(id: 'b', name: '火山')]),
      l10n: l10n,
      onSave: (next, _) => saved = next,
      onCancel: () {},
    ))));
    await tester.pump();
    await tester.tap(find.text('删除').first);
    await tester.pump();
    expect(find.text('确认删除'), findsOneWidget); // 确认对话框
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saved.providers.length, 1);
  });
}
