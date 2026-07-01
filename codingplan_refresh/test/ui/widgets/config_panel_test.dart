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
    expect(saved!.triggerHours, isNot(contains(7)));
  });

  testWidgets('火山方舟 provider 显示 Access Key / Secret Access Key 输入框', (
    tester,
  ) async {
    final l10n = LocalizationService()..initialize('zh');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [
        ProviderConfig(
          id: 'v',
          name: '火山',
          apiUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
        ),
      ]),
      l10n: l10n,
      onSave: (_, __) {},
      onCancel: () {},
    ))));
    await tester.pump();
    expect(find.text('Access Key'), findsOneWidget);
    expect(find.text('Secret Access Key'), findsOneWidget);
  });

  testWidgets('智谱 provider 不显示 AK/SK 输入框', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [
        ProviderConfig(
          id: 'z',
          name: '智谱',
          apiUrl: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
        ),
      ]),
      l10n: l10n,
      onSave: (_, __) {},
      onCancel: () {},
    ))));
    await tester.pump();
    expect(find.text('Access Key'), findsNothing);
    expect(find.text('Secret Access Key'), findsNothing);
  });

  testWidgets('火山方舟 AK/SK 输入后保存写回 ProviderConfig', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    AppConfig? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [
        ProviderConfig(
          id: 'v',
          name: '火山',
          apiUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
        ),
      ]),
      l10n: l10n,
      onSave: (next, _) => saved = next,
      onCancel: () {},
    ))));
    await tester.pump();
    // AK/SK 字段与保存按钮在表单底部，火山方舟多两个输入框后内容超高 600 视口，
    // 需先 ensureVisible 滚入视口再 enterText / tap，否则 tap 命中失败、onSave 不触发。
    await tester.ensureVisible(find.byKey(const ValueKey('Access Key')));
    await tester.enterText(find.byKey(const ValueKey('Access Key')), 'AK123');
    await tester.enterText(
      find.byKey(const ValueKey('Secret Access Key')),
      'SK456',
    );
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!.providers[0].accessKey, 'AK123');
    expect(saved!.providers[0].secretKey, 'SK456');
  });
}
