class LimitInfo {
  final int percentage;
  final int? nextResetTimeMs; // Unix 毫秒
  const LimitInfo(this.percentage, this.nextResetTimeMs);
}

class UsageInfo {
  final String? level;
  final LimitInfo? mcp;   // TIME_LIMIT（月）
  final LimitInfo? hour5; // TOKENS_LIMIT unit==3 number==5
  final LimitInfo? weekly;
  const UsageInfo(this.level, this.mcp, this.hour5, this.weekly);
}
