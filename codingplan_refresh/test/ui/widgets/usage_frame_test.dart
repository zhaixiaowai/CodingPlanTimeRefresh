import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/widgets/usage_frame.dart';

String _reset(int? ms) {
  if (ms == null) return '';
  // 复用 resetToday 形态：「重置 HH:mm」
  final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  return '重置 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('成功行：进度条内嵌百分比 + 重置时间右侧', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, 1782478364000),
      UsageItem('mcpMonthly', 12, null),
    ], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: _reset)),
    ));
    await tester.pump();
    // legend 标题。
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
    // label。
    expect(find.text('5H'), findsOneWidget);
    expect(find.text('月'), findsOneWidget); // mcpMonthly label=月，resetAtMs=null 故无 (MCP) 前缀
    // 百分比内嵌进度条（textContaining 匹配）。mcp 行前缀 (mcp)。
    expect(find.textContaining('34%'), findsOneWidget);
    expect(find.textContaining('(mcp)12%'), findsOneWidget);
    // 有重置时间的行显示「重置 HH:mm」；无重置（mcpMonthly）不显示重置。
    expect(find.textContaining('重置'), findsOneWidget);
  });

  testWidgets('nextTriggerText 非空 → legend 标题后接提示', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [UsageItem('token5h', 34, null)], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(
        result: result, l10n: l10n, resetText: _reset,
        nextTriggerText: '下次触发在 19:00',
      )),
    ));
    await tester.pump();
    expect(find.textContaining('智谱 Pro : 下次触发在 19:00'), findsOneWidget);
  });

  testWidgets('nextTriggerText 空 → 仅标题', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [UsageItem('token5h', 34, null)], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(
        result: result, l10n: l10n, resetText: _reset, nextTriggerText: '',
      )),
    ));
    await tester.pump();
    expect(find.textContaining('下次触发'), findsNothing);
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
  });

  testWidgets('失败：显示 errorMessage', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = const UsageResult('火山方舟', [], 'arkcli 未安装，参考 README');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: _reset)),
    ));
    await tester.pump();
    expect(find.text('arkcli 未安装，参考 README'), findsOneWidget);
  });

  testWidgets('mcpMonthly → 进度条内嵌 (mcp)NN% 标注，重置文本纯重置', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('mcpMonthly', 12, 1782478364000),
    ], null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: _reset)),
    ));
    await tester.pump();
    // mcpMonthly label=月，进度条百分比前加 (mcp) 标注。
    expect(find.text('月'), findsOneWidget);
    expect(find.textContaining('(mcp)12%'), findsOneWidget);
    // 重置文本不带标注（纯「重置 HH:mm」）。
    expect(find.textContaining('重置'), findsOneWidget);
  });
}
