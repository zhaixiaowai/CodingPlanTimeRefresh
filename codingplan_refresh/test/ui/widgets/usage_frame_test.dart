import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/widgets/usage_frame.dart';

void main() {
  testWidgets('成功多行：显示标题 + 各行 label', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, null),
      UsageItem('mcpMonthly', 12, null),
    ], null);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: (_) => ''))));
    await tester.pump();
    // legend 用 Text.rich 拼接，整段含标题；用 containing 匹配标题片段。
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
    expect(find.text('Token(5H)'), findsOneWidget);
    expect(find.text('MCP(月)'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
  });

  testWidgets('nextTriggerText 非空 → legend 标题后接「下次触发在 HH:mm」', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [UsageItem('token5h', 34, null)], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(
        result: result, l10n: l10n, resetText: (_) => '',
        nextTriggerText: '下次触发在 19:00',
      )),
    ));
    await tester.pump();
    // 拼成「智谱 Pro : 下次触发在 19:00」
    expect(find.textContaining('智谱 Pro : 下次触发在 19:00'), findsOneWidget);
  });

  testWidgets('nextTriggerText 空 → 仅标题，不出现「下次触发」', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [UsageItem('token5h', 34, null)], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(
        result: result, l10n: l10n, resetText: (_) => '', nextTriggerText: '',
      )),
    ));
    await tester.pump();
    expect(find.textContaining('下次触发'), findsNothing);
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
  });

  testWidgets('失败：显示 errorMessage', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = const UsageResult('火山方舟', [], 'arkcli 未安装，参考 README');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: (_) => ''))));
    await tester.pump();
    expect(find.text('arkcli 未安装，参考 README'), findsOneWidget);
  });
}
