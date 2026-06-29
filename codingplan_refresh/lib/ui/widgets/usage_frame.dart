import 'package:flutter/material.dart';
import '../../models/usage_info.dart';
import '../../services/localization_service.dart';

/// 单个 provider 的用量框：fieldset legend 风格，标题压在上边线。
/// 成功显示 items 各行（label + 重置 + 百分比着色）；失败/无数据显示 errorMessage。
/// 最小高度 = 一行（items 空也不塌陷）。
class UsageFrame extends StatelessWidget {
  final UsageResult result;
  final LocalizationService l10n;
  final String Function(int? resetAtMs)
  resetText; // 由 main_page 注入（含本地化 + DateFormat）
  /// 优先显示的标题（用户在配置里输入的 ProviderConfig.name）；为空则 fallback
  /// result.vendorTitle（查询返回的「智谱 Pro」等）。
  final String? displayName;

  /// 是否首次查询中（无旧数据）。为 true 且 items 空、无错误时显示「用量查询中...」；
  /// 有旧数据（items 非空或有 errorMessage）时正常显示旧内容（无感刷新）。
  final bool isLoading;

  /// 下次触发提示文本（全局触发，所有 provider 共享同一值）。非空时显示在 legend 标题后，
  /// 形如「智谱 Pro : 下次触发在 19:00」；空则不显示。
  final String nextTriggerText;

  const UsageFrame({
    super.key,
    required this.result,
    required this.l10n,
    required this.resetText,
    this.displayName,
    this.isLoading = false,
    this.nextTriggerText = '',
  });

  static Color pctColor(double p) {
    if (p >= 80) return const Color(0xFFFF0000);
    if (p >= 50) return const Color(0xFFFF8C00);
    return const Color(0xFF007ACC);
  }

  @override
  Widget build(BuildContext context) {
    // legend 标题压在框上边线：用 Padding(top) 给 legend 让出空间（参与 size 计算，
    // 避免 Positioned 溢出 Stack 导致父级量高漏算 legend 区→滚动条）。
    // legend 用 Transform.translate 上移压在框上边线，视觉同 fieldset legend。
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 框（带边框 + 最小高度）
          Container(
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF555555)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: result.items.isEmpty
                ? Center(
                    child: Text(
                      // 优先错误信息；无错误且首次查询中 → loading 占位；
                      // 否则空（边缘：非 loading 且无 items 无错误）。
                      result.errorMessage ??
                          (isLoading ? l10n.t('usageLoading') : ''),
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 11,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: result.items.map((it) => _row(it)).toList(),
                  ),
          ),
          // legend 标题：translate 上移压在框上边线（不溢出 Stack 的 size 计算外，
          // 因 Padding top 已预留其高度）
          Positioned(
            left: 10,
            top: 0,
            child: Transform.translate(
              offset: const Offset(0, -7),
              child: Container(
                color: const Color(0xFF2D2D30), // 遮住边框，形成 legend 缺口
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text.rich(
                  // 标题优先用户输入的 displayName，但保留 vendorTitle 套餐部分（「Pro」）。
                  // nextTriggerText 非空时以「 : 」分隔接在标题后，形如
                  // 「智谱 Pro : 下次触发在 19:00」（全局触发，所有框同一时刻）。
                  TextSpan(
                    children: [
                      TextSpan(
                        text: usageDisplayTitle(
                          displayName ?? '',
                          result.vendorTitle,
                        ),
                      ),
                      if (nextTriggerText.isNotEmpty) ...[
                        const TextSpan(
                          text: ' : ',
                          style: TextStyle(color: Color(0xFF666666)),
                        ),
                        TextSpan(
                          text: nextTriggerText,
                          style: const TextStyle(color: Color(0xFF888888)),
                        ),
                      ],
                    ],
                  ),
                  style: const TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(UsageItem it) {
    final pct = it.percentage;
    final reset = it.resetAtMs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // label 固定宽（等宽对齐：每行进度条左端齐），softWrap:false 防英文「Week」换行。
          SizedBox(
            width: 36,
            child: Text(
              l10n.t(it.labelKey),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: _progressBar(pct)),
          const SizedBox(width: 6),
          // 重置时间：null 不显示（不占位）。去掉 ⟳ 图标，保留「重置」文字。
          // mcpMonthly 行的 (MCP) 标注放重置文本最前（避免 label 变长导致英文换行）。
          if (reset != null)
            Text(
              "${it.labelKey == 'mcpMonthly' ? '(MCP) ' : ''}${resetText(reset)}",
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: Color(0xFF999999), fontSize: 10),
            ),
        ],
      ),
    );
  }

  /// 进度条 + 内嵌百分比文字（Stack：灰底条 + pct 着色填充 + 居中百分比）。
  Widget _progressBar(double pct) {
    final c = pct.clamp(0.0, 100.0);
    return SizedBox(
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 底层灰条。
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF3F3F46),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // 上层 pct 着色填充（按比例宽度）。
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: c / 100.0,
              child: Container(
                decoration: BoxDecoration(
                  color: pctColor(c),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          // 内嵌百分比文字（白色，居中于整条）。
          Text(
            '${c.toStringAsFixed(c == c.roundToDouble() ? 0 : 1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
