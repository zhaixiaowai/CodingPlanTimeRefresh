import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/localization_service.dart';

/// 手动触发面板：下拉选 provider + 结果区显示该 provider 当前 ResultState。
///
/// 面板内只持有「当前选中 provider.id」与「触发按钮 busy 态」两类本地状态，
/// 结果文本/标题由调用方通过 [getText]/[getHeader] 闭包实时回读——这样定时触发
/// 与手动触发共享同一份 ResultState（外部 setState 即可让本面板刷新）。
///
/// 触发动作通过 [onTrigger] 回调上抛；放大态由 T8 接入，本面板先在 Dialog 占位。
class ResultPanel extends StatefulWidget {
  /// 可选 providers 列表（用于下拉项）。
  final List<ProviderConfig> providers;
  /// 取该 provider 当前 resultText（空则显示 waitingPlaceholder）。
  final String Function(String providerId) getText;
  /// 取该 provider 当前 header（结果时间戳/失败提示等）。
  final String Function(String providerId) getHeader;
  /// 触发该 provider（手动）；返回是否成功（调用方用于决定是否关闭面板等）。
  final Future<bool> Function(String providerId) onTrigger;
  final LocalizationService l10n;

  const ResultPanel({
    super.key,
    required this.providers,
    required this.getText,
    required this.getHeader,
    required this.onTrigger,
    required this.l10n,
  });

  @override
  State<ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends State<ResultPanel> {
  late String _selectedId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.providers.isEmpty ? '' : widget.providers.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    if (widget.providers.isEmpty) {
      return Center(
        child: Text('未配置任何模型',
            style: const TextStyle(color: Color(0xFF999999))),
      );
    }
    final selected = widget.providers.firstWhere(
      (p) => p.id == _selectedId,
      orElse: () => widget.providers.first,
    );
    _selectedId = selected.id;
    final text = widget.getText(_selectedId);
    final header = widget.getHeader(_selectedId);
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            DropdownButton<String>(
              value: _selectedId,
              dropdownColor: const Color(0xFF2D2D30),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: widget.providers
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name.isEmpty ? p.id : p.name),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedId = v);
              },
            ),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, size: 16, color: Color(0xFFAAAAAA)),
              tooltip: '',
            ),
          ]),
          Text(header,
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              color: const Color(0xFF1E1E1E),
              padding: const EdgeInsets.all(6),
              child: SingleChildScrollView(
                child: Text(
                  text.isEmpty ? l.t('waitingPlaceholder') : text,
                  style: TextStyle(
                    color: text.isEmpty
                        ? const Color(0xFF555555)
                        : const Color(0xFFCCCCCC),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await widget.onTrigger(_selectedId);
                    if (mounted) setState(() => _busy = false);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007ACC),
            ),
            child: Text(l.t('manualTriggerPopup')),
          ),
        ],
      ),
    );
  }
}
