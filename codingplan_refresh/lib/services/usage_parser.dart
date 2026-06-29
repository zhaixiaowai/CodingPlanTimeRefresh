import 'dart:convert';
import 'package:codingplan_refresh/models/usage_info.dart';

/// 解析 BigModel 配额响应 → [UsageResult]。
///
/// vendorTitle = 「智谱」+ level 首字母大写；items = [token5h, tokenWeekly, mcpMonthly]。
/// 归类逻辑（与旧 MAUI `MainPage.TryParseUsageInfo` 一致）：
/// - type=TIME_LIMIT → mcpMonthly（mcp 月度）
/// - type=TOKENS_LIMIT 且 unit=3 number=5 → token5h（5 小时）
/// - 其余 TOKENS_LIMIT → tokenWeekly（周）
/// 失败/无数据 → UsageResult('智谱', [], 'queryFailed')。
UsageResult parseBigmodelUsage(String jsonBody, {String vendorTitle = '智谱'}) {
  try {
    final doc = jsonDecode(jsonBody) as Map<String, dynamic>;
    final data = doc['data'];
    if (data is! Map<String, dynamic>) {
      return const UsageResult('智谱', [], 'queryFailed');
    }
    final limits = data['limits'];
    if (limits is! List) {
      return const UsageResult('智谱', [], 'queryFailed');
    }

    final level = data['level'] as String?;
    final title = level == null || level.isEmpty
        ? vendorTitle
        : '$vendorTitle ${level[0].toUpperCase()}${level.substring(1)}';

    int? mcpPct, mcpReset, hour5Pct, hour5Reset, weeklyPct, weeklyReset;
    for (final limit in limits) {
      if (limit is! Map<String, dynamic>) continue;
      final pct = limit['percentage'];
      if (pct is! int) continue;
      final nrt = limit['nextResetTime'];
      final reset = nrt is int ? nrt : null;
      final type = limit['type'] as String?;
      if (type == 'TIME_LIMIT') {
        mcpPct = pct;
        mcpReset = reset;
      } else if (type == 'TOKENS_LIMIT') {
        final unit = limit['unit'] is int ? limit['unit'] as int : 0;
        final number = limit['number'] is int ? limit['number'] as int : 0;
        if (unit == 3 && number == 5) {
          hour5Pct = pct;
          hour5Reset = reset;
        } else {
          weeklyPct = pct;
          weeklyReset = reset;
        }
      }
    }

    final items = <UsageItem>[
      if (hour5Pct != null)
        UsageItem('token5h', hour5Pct.toDouble(), hour5Reset),
      if (weeklyPct != null)
        UsageItem('tokenWeekly', weeklyPct.toDouble(), weeklyReset),
      if (mcpPct != null) UsageItem('mcpMonthly', mcpPct.toDouble(), mcpReset),
    ];
    if (items.isEmpty) {
      return UsageResult(title, [], 'queryFailed');
    }
    return UsageResult(title, items, null);
  } catch (_) {
    return const UsageResult('智谱', [], 'queryFailed');
  }
}
