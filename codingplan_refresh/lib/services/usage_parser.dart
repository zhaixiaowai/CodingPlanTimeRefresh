import 'dart:convert';
import 'package:codingplan_refresh/models/usage_info.dart';

/// 解析 BigModel 配额 API 响应。复刻旧版 QueryBigmodelUsagePercentageAsync 的归类逻辑。
UsageInfo? parseBigmodelUsage(String jsonBody) {
  try {
    final doc = jsonDecode(jsonBody) as Map<String, dynamic>;
    final data = doc['data'];
    if (data is! Map<String, dynamic>) return null;
    final limits = data['limits'];
    if (limits is! List) return null;

    final level = data['level'] as String?;
    LimitInfo? mcp, hour5, weekly;

    for (final limit in limits) {
      if (limit is! Map<String, dynamic>) continue;
      final pct = limit['percentage'];
      if (pct is! int) continue;
      final nrt = limit['nextResetTime'];
      final nextReset = nrt is int ? nrt : null;
      final info = LimitInfo(pct, nextReset);

      final type = limit['type'] as String?;
      if (type == 'TIME_LIMIT') {
        mcp = info;
      } else if (type == 'TOKENS_LIMIT') {
        final unit = limit['unit'] is int ? limit['unit'] as int : 0;
        final number = limit['number'] is int ? limit['number'] as int : 0;
        if (unit == 3 && number == 5) {
          hour5 = info;
        } else {
          weekly = info;
        }
      }
    }
    return UsageInfo(level, mcp, hour5, weekly);
  } catch (_) {
    return null;
  }
}
