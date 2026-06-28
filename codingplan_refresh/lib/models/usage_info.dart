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

/// 组装用量框/窗口标题的显示名：优先用用户输入的 [name]，**保留** [vendorTitle]
/// 中的套餐部分（第一个空格之后，如「智谱 Pro」的「Pro」），避免只替换名称时丢套餐。
///
/// vendorTitle 格式统一为「{厂商名} {套餐}」（智谱/火山方舟的 query 拼装），
/// 无套餐时仅厂商名。故按首个空格切分：前=厂商名、后=套餐。
/// - name 非空 → 用 name 作厂商名前缀，套餐照接（name='我的'+ '智谱 Pro' → '我的 Pro'）
/// - name 空 → 用 vendorTitle 厂商名前缀 + 套餐（与原 vendorTitle 等价）
/// - 无套餐 → 仅 name（或厂商名）
String usageDisplayTitle(String name, String vendorTitle) {
  final sp = vendorTitle.indexOf(' ');
  final tier = sp >= 0 ? vendorTitle.substring(sp + 1).trim() : '';
  final vendor = sp >= 0 ? vendorTitle.substring(0, sp).trim() : vendorTitle;
  final base = name.isNotEmpty ? name : vendor;
  return tier.isEmpty ? base : '$base $tier';
}
