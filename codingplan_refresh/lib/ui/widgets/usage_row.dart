import 'package:flutter/material.dart';
import '../../models/usage_info.dart';

/// 单行用量显示：标签 + 重置时间（居中）+ 百分比（右对齐着色）。
///
/// 平移旧 MAUI `MainPage.xaml` 中三行 Token(5H) / Token(周) / MCP(月) 的渲染逻辑，
/// 百分比着色阈值与 MAUI `PctColor` 一致：`>=80` 红 / `>=50` 橙 / 其余蓝。
class UsageRow extends StatelessWidget {
  final String label;
  final LimitInfo? info;
  /// 将重置时刻（Unix 毫秒）转为「重置 HH:mm」/「重置 MM/dd HH:mm」文本。
  /// 由 [MainPage] 注入，避免本组件直接依赖本地化与时间格式化。
  final String Function(int ms) resetText;
  const UsageRow({
    super.key,
    required this.label,
    required this.info,
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
    final pct = info?.percentage;
    return Row(children: [
      SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12))),
      Expanded(
          child: Center(
              // info 可空且 null 分支可达：MCP 行（usage_info.mcp 为 LimitInfo?）在
              // MainPage 中无条件渲染（_usage?.mcp），而 hour5/weekly 才条件渲染。
              child: Text(info == null ? '' : resetText(info!.nextResetTimeMs ?? -1),
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
