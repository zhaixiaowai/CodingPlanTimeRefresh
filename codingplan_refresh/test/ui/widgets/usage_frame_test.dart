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
  testWidgets('成功行：进度条内嵌百分比；重置默认隐藏（hover 显示）', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, 1782478364000),
      UsageItem('mcpMonthly', 12, null),
    ], null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageFrame(result: result, l10n: l10n, resetText: _reset),
        ),
      ),
    );
    await tester.pump();
    // legend 标题。
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
    // label。
    expect(find.text('5H'), findsOneWidget);
    expect(
      find.text('月'),
      findsOneWidget,
    ); // mcpMonthly label=月，resetAtMs=null 故无 (MCP) 前缀
    // 百分比内嵌进度条（textContaining 匹配）。mcp 行前缀 (mcp)。
    expect(find.textContaining('34%'), findsOneWidget);
    expect(find.textContaining('(mcp)12%'), findsOneWidget);
    // 重置时间默认不显示（hover 进度条才浮出，见 _ProgressBar）。
    expect(find.textContaining('重置'), findsNothing);
  });

  testWidgets('Tooltip 包裹：默认不显示重置（hover 由系统气泡）', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, 1782478364000),
    ], null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageFrame(result: result, l10n: l10n, resetText: _reset),
        ),
      ),
    );
    await tester.pump();
    // 默认（未 hover）：Tooltip message 不在 tree，重置不显示。
    expect(find.textContaining('重置'), findsNothing);
  });

  testWidgets('nextTriggerText 非空 → legend 标题后接提示', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, null),
    ], null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageFrame(
            result: result,
            l10n: l10n,
            resetText: _reset,
            nextTriggerText: '下次触发在 19:00',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('智谱 Pro : 下次触发在 19:00'), findsOneWidget);
  });

  testWidgets('nextTriggerText 空 → 仅标题', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, null),
    ], null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageFrame(
            result: result,
            l10n: l10n,
            resetText: _reset,
            nextTriggerText: '',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('下次触发'), findsNothing);
    expect(find.textContaining('智谱 Pro'), findsOneWidget);
  });

  testWidgets('失败：显示 errorMessage', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = const UsageResult('火山方舟', [], 'arkcliNotInstalled');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageFrame(result: result, l10n: l10n, resetText: _reset),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('arkcli 未安装，参考 README'), findsOneWidget);
  });

  testWidgets('mcpMonthly → 进度条内嵌 (mcp)NN% 标注', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('mcpMonthly', 12, 1782478364000),
    ], null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageFrame(result: result, l10n: l10n, resetText: _reset),
        ),
      ),
    );
    await tester.pump();
    // mcpMonthly label=月，进度条百分比前加 (mcp) 标注。
    expect(find.text('月'), findsOneWidget);
    expect(find.textContaining('(mcp)12%'), findsOneWidget);
    // 重置时间默认隐藏（hover 进度条才显示，见 _ProgressBar）。
    expect(find.textContaining('重置'), findsNothing);
  });

  testWidgets('超配额(>100%) → 进度条文字显示真实值「150%」不丢告警', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 150, null),
    ], null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageFrame(result: result, l10n: l10n, resetText: _reset),
        ),
      ),
    );
    await tester.pump();
    // 文字用真实 pct（非钳制值），超配额显示 150% 告警，不显示「100%」。
    expect(find.textContaining('150%'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
  });
}
