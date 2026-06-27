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
    expect(find.text('智谱 Pro'), findsOneWidget);
    expect(find.text('Token(5H)'), findsOneWidget);
    expect(find.text('MCP(月)'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
  });

  testWidgets('失败：显示 errorMessage', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = const UsageResult('火山方舟', [], 'arkcli 未安装，参考 README');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: (_) => ''))));
    await tester.pump();
    expect(find.text('arkcli 未安装，参考 README'), findsOneWidget);
  });
}
