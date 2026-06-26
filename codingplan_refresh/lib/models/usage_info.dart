/// 单条用量项（一行）。labelKey 为本地化键（见 LocalizationService._table，
/// 取值如 'token5h' / 'tokenWeekly' / 'tokenMonthly' / 'mcpMonthly'）。
class UsageItem {
  final String labelKey;
  final double percentage;
  final int? resetAtMs; // Unix 毫秒，可空
  const UsageItem(this.labelKey, this.percentage, this.resetAtMs);
}

/// 单个 provider 的用量查询结果。
/// - 成功：items 非空、errorMessage == null
/// - 失败/无数据：items 空、errorMessage = 具体描述（框内显示）
class UsageResult {
  final String vendorTitle; // 框标题，如「智谱 Pro」「火山方舟 Personal」
  final List<UsageItem> items;
  final String? errorMessage;
  const UsageResult(this.vendorTitle, this.items, this.errorMessage);
}
