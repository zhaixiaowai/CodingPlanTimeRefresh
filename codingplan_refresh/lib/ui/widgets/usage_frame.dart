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
                      // errorMessage 为 l10n key（provider/解析器返回 key），在此翻译；
                      // 原始第三方错误（非 key）l10n.t 未命中返回自身原样显示。
                      result.errorMessage != null
                          ? l10n.t(result.errorMessage!)
                          : (isLoading ? l10n.t('usageLoading') : ''),
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
          // label 固定宽（等宽对齐：每行进度条左端齐）。中文（5H/周/月）短用 22，
          // 英文（Week/Month）用 36。softWrap:false 防换行。窗口宽度不随此变。
          SizedBox(
            width: l10n.current == 'zh' ? 22 : 36,
            child: Text(
              l10n.t(it.labelKey),
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _progressBar(
              pct,
              isMcp: it.labelKey == 'mcpMonthly',
              // label（5H/周/月，本地化）+ 已本地化的重置文本，供 hover Tooltip 拼完整提示。
              label: l10n.t(it.labelKey),
              resetText: reset != null ? resetText(reset) : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 进度条 + 内嵌百分比文字。hover 进度条由 Tooltip 显示完整提示
  /// 「{label}：已使用 {pct}%，重置 {time}」（多语言，[label] 为本地化的 5H/周/月，
  /// [resetText] 为已本地化的「重置 HH:mm」，可空则只显示「已使用 N%」）。
  /// [isMcp] 时进度条不再前缀 (mcp)（与其他行对齐）；mcp 的区分放在 hover Tooltip
  /// （label 用「(MCP)月」前缀）。
  Widget _progressBar(
    double pct, {
    required bool isMcp,
    required String label,
    String? resetText,
  }) {
    final c = pct.clamp(0.0, 100.0);
    final pctText = pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1);
    // 进度条内嵌文字：高用量（pct≥80%）且有重置时，把已本地化的重置文本接在百分比后，
    // 形如「80% (重置 09:05)」（一眼提示即将重置）；否则仅「NN%」。resetText 已含本地化
    // 「重置 HH:mm」/「Reset HH:mm」前缀，直接拼接即可，无需额外本地化。
    final hasReset = resetText != null && resetText.isNotEmpty;
    final showResetInline = c >= 80 && hasReset;
    final barText = showResetInline ? '$pctText% ($resetText)' : '$pctText%';
    final bar = SizedBox(
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
          // 内嵌百分比文字（白色，居中于整条，最后绘制在最上层）。
          Text(
            barText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    // hover 进度条 Tooltip：完整提示「label：已使用 N%[，重置 time]」。
    // 有重置：usageTooltip 三占位（label/pct/重置）；无重置：usageTooltipNoReset 两占位。
    // mcp 行用 (MCP) 前缀的 label（mcpTipLabel），与普通「月」区分。
    final tipLabel = isMcp ? l10n.t('mcpTipLabel') : label;
    final msg = !hasReset
        ? l10n.t('usageTooltipNoReset').fmt([tipLabel, pctText])
        : l10n.t('usageTooltip').fmt([tipLabel, pctText, resetText]);
    return Tooltip(message: msg, child: bar);
  }
}
