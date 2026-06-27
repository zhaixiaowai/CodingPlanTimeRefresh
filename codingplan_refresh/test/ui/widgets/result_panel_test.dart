import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/widgets/result_panel.dart';

/// ResultPanel 测试：下拉切换显示对应 provider 的 text、点触发调用 onTrigger。
void main() {
  late LocalizationService l10n;

  setUp(() {
    l10n = LocalizationService()..initialize('zh');
  });

  testWidgets('初始显示第一个 provider 的 text', (tester) async {
    final providers = [
      ProviderConfig(id: 'p1', name: '智谱', apiUrl: 'https://a'),
      ProviderConfig(id: 'p2', name: '火山', apiUrl: 'https://b'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 500,
          child: ResultPanel(
            providers: providers,
            getText: (id) => id == 'p1' ? '笑话A' : '笑话B',
            getHeader: (id) => id == 'p1' ? '头部A' : '头部B',
            onTrigger: (_) async => true,
            l10n: l10n,
          ),
        ),
      ),
    ));
    await tester.pump();
    // 初始选中 p1，应显示 p1 的 text/header。
    expect(find.text('笑话A'), findsOneWidget);
    expect(find.text('头部A'), findsOneWidget);
    // p2 的内容不应显示。
    expect(find.text('笑话B'), findsNothing);
  });

  testWidgets('下拉切换 provider → 显示该 provider 的 text/header',
      (tester) async {
    final providers = [
      ProviderConfig(id: 'p1', name: '智谱', apiUrl: 'https://a'),
      ProviderConfig(id: 'p2', name: '火山', apiUrl: 'https://b'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 500,
          child: ResultPanel(
            providers: providers,
            getText: (id) => id == 'p1' ? '笑话A' : '笑话B',
            getHeader: (id) => id == 'p1' ? '头部A' : '头部B',
            onTrigger: (_) async => true,
            l10n: l10n,
          ),
        ),
      ),
    ));
    await tester.pump();

    // 打开下拉。
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    // 选择「火山」。
    await tester.tap(find.text('火山').last);
    await tester.pumpAndSettle();

    // 切换后应显示 p2 的 text/header，不再显示 p1 的。
    expect(find.text('笑话B'), findsOneWidget);
    expect(find.text('头部B'), findsOneWidget);
    expect(find.text('笑话A'), findsNothing);
  });

  testWidgets('点击触发按钮 → 调用 onTrigger(当前选中 providerId)',
      (tester) async {
    final providers = [
      ProviderConfig(id: 'p1', name: '智谱', apiUrl: 'https://a'),
    ];
    String? triggeredId;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 500,
          child: ResultPanel(
            providers: providers,
            getText: (_) => 'x',
            getHeader: (_) => '',
            onTrigger: (id) async {
              triggeredId = id;
              return true;
            },
            l10n: l10n,
          ),
        ),
      ),
    ));
    await tester.pump();
    // 点击触发按钮（文案 = manualTriggerPopup）。
    await tester.tap(find.text(l10n.t('manualTriggerPopup')));
    await tester.pump();
    expect(triggeredId, 'p1');
  });

  testWidgets('空 text 显示 waitingPlaceholder', (tester) async {
    final providers = [
      ProviderConfig(id: 'p1', name: '智谱', apiUrl: 'https://a'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 500,
          child: ResultPanel(
            providers: providers,
            getText: (_) => '',
            getHeader: (_) => '',
            onTrigger: (_) async => true,
            l10n: l10n,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text(l10n.t('waitingPlaceholder')), findsOneWidget);
  });
}
