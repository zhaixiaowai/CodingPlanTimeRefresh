import 'package:flutter/material.dart';

/// 单行用量显示桩：旧 `LimitInfo` 类型已移除（统一为 `UsageItem`/`UsageResult`）。
///
/// T1 桩化：直接以 `percentage` / `resetMs` 作为可选入参（旧行为最小映射），
/// 保留类结构供 T6/T9 重写或删除。着色阈值与旧版一致：`>=80` 红 / `>=50` 橙 / 其余蓝。
class UsageRow extends StatelessWidget {
  final String label;
  final int? percentage;
  final int? resetMs;
  /// 将重置时刻（Unix 毫秒）转为「重置 HH:mm」/「重置 MM/dd HH:mm」文本。
  /// 由调用方注入，避免本组件直接依赖本地化与时间格式化。
  final String Function(int ms) resetText;
  const UsageRow({
    super.key,
    required this.label,
    this.percentage,
    this.resetMs,
    required this.resetText,
  });

  /// 百分比着色（与旧 MAUI `PctColor` 一致）。
  static Color pctColor(int p) {
    if (p >= 80) return const Color(0xFFFF0000);
    if (p >= 50) return const Color(0xFFFF8C00);
    return const Color(0xFF007ACC);
  }

  @override
  Widget build(BuildContext context) {
    final pct = percentage;
    return Row(children: [
      SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12))),
      Expanded(
          child: Center(
              child: Text(resetMs == null ? '' : resetText(resetMs!),
                  style: const TextStyle(color: Color(0xFF999999), fontSize: 11)))),
      SizedBox(
          width: 50,
          child: Text(pct == null ? '' : '$pct%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: pct == null ? const Color(0xFF007ACC) : pctColor(pct),
                  fontSize: 16,
                  fontWeight: FontWeight.bold))),
    ]);
  }
}
