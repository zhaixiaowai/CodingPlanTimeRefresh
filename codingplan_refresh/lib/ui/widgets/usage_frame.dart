import 'package:flutter/material.dart';
import '../../models/usage_info.dart';
import '../../services/localization_service.dart';

/// 单个 provider 的用量框：fieldset legend 风格，标题压在上边线。
/// 成功显示 items 各行（label + 重置 + 百分比着色）；失败/无数据显示 errorMessage。
/// 最小高度 = 一行（items 空也不塌陷）。
class UsageFrame extends StatelessWidget {
  final UsageResult result;
  final LocalizationService l10n;
  final String Function(int? resetAtMs) resetText; // 由 main_page 注入（含本地化 + DateFormat）

  const UsageFrame({
    super.key,
    required this.result,
    required this.l10n,
    required this.resetText,
  });

  static Color pctColor(double p) {
    if (p >= 80) return const Color(0xFFFF0000);
    if (p >= 50) return const Color(0xFFFF8C00);
    return const Color(0xFF007ACC);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      // 框（带边框 + 最小高度）
      Container(
        constraints: const BoxConstraints(minHeight: 28),
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF555555)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: result.items.isEmpty
            ? Center(
                child: Text(result.errorMessage ?? '',
                    style: const TextStyle(color: Color(0xFF999999), fontSize: 11)))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: result.items.map((it) => _row(it)).toList(),
              ),
      ),
      // legend 标题（压在上边线）
      Positioned(
        left: 10,
        top: 0,
        child: Container(
          color: const Color(0xFF2D2D30), // 遮住边框，形成 legend 缺口
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(result.vendorTitle,
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
        ),
      ),
    ]);
  }

  Widget _row(UsageItem it) {
    final pct = it.percentage;
    final reset = it.resetAtMs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Text(l10n.t(it.labelKey),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12))),
        Expanded(
            child: Center(
                child: Text(reset == null ? '' : resetText(reset),
                    style: const TextStyle(color: Color(0xFF999999), fontSize: 11)))),
        SizedBox(
            width: 50,
            child: Text('${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(color: pctColor(pct), fontSize: 16, fontWeight: FontWeight.bold))),
      ]),
    );
  }
}
