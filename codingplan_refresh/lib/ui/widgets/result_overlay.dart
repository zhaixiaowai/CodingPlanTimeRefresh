import 'package:flutter/material.dart';
import '../../services/localization_service.dart';

/// 结果浮层：只读流式文本 + 关闭按钮 + 手动触发按钮。
///
/// 平移旧 MAUI `MainPage.xaml` 中 ResultSection 浮层。
/// 文本为空时显示 [placeholder]（灰色），否则显示 [text]（浅灰）。
class ResultOverlay extends StatelessWidget {
  final String header;
  final String text;
  final String placeholder;
  final VoidCallback onClose;
  final VoidCallback onTrigger;
  final LocalizationService l10n;
  const ResultOverlay({
    super.key,
    required this.header,
    required this.text,
    required this.placeholder,
    required this.onClose,
    required this.onTrigger,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  header,
                  style: const TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 11,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: const Text(
                  '✕',
                  style: TextStyle(color: Color(0xFFAAAAAA)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              color: const Color(0xFF1E1E1E),
              padding: const EdgeInsets.all(6),
              child: SingleChildScrollView(
                child: Text(
                  text.isEmpty ? placeholder : text,
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
            onPressed: onTrigger,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007ACC),
            ),
            child: Text(l10n.t('manualTriggerPopup')),
          ),
        ],
      ),
    );
  }
}
