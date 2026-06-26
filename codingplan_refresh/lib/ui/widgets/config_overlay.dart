import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/localization_service.dart';

/// 配置浮层：API URL / Key / Model / 语言三选（自动·中文·English）。
///
/// 平移旧 MAUI `MainPage.xaml` 中 ConfigSection 浮层。
/// `onSave(next, langChanged)`：`langChanged` 为新语言代码相对旧值是否变更。
class ConfigOverlay extends StatefulWidget {
  final AppConfig initial;
  final LocalizationService l10n;
  final void Function(AppConfig next, bool langChanged) onSave;
  final VoidCallback onCancel;
  const ConfigOverlay({
    super.key,
    required this.initial,
    required this.l10n,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<ConfigOverlay> createState() => _ConfigOverlayState();
}

class _ConfigOverlayState extends State<ConfigOverlay> {
  late final TextEditingController url, key, model;
  late int langIndex; // 0 auto 1 zh 2 en

  @override
  void initState() {
    super.initState();
    url = TextEditingController(text: widget.initial.apiUrl);
    key = TextEditingController(text: widget.initial.apiKey);
    model = TextEditingController(text: widget.initial.model);
    langIndex = (widget.initial.language ?? 'auto') == 'zh'
        ? 1
        : (widget.initial.language == 'en' ? 2 : 0);
  }

  @override
  void dispose() {
    url.dispose();
    key.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Expanded(child: ListView(children: [
          _field('API URL', url, 'https://api.openai.com/v1/chat/completions'),
          _field('API Key', key, 'sk-xxx', obscure: true),
          _field('Model', model, 'glm-5.1'),
          const SizedBox(height: 6),
          Text(l.t('languageLabel'),
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
          Row(children: [
            _langBtn(0, l.t('languageAuto')),
            _langBtn(1, l.t('languageZh')),
            _langBtn(2, l.t('languageEn')),
          ]),
        ])),
        Row(children: [
          Expanded(
              child: ElevatedButton(
                  onPressed: () {
                    final next = AppConfig(
                      isAlwaysOnTop: widget.initial.isAlwaysOnTop,
                      apiUrl: url.text,
                      apiKey: key.text,
                      model: model.text,
                      lastAutoTriggerKey: widget.initial.lastAutoTriggerKey,
                      isCollapsed: widget.initial.isCollapsed,
                      language: langIndex == 1
                          ? 'zh'
                          : (langIndex == 2 ? 'en' : 'auto'),
                    );
                    widget.onSave(
                        next,
                        next.language !=
                            (widget.initial.language ?? 'auto'));
                  },
                  child: Text(l.t('save')))),
          const SizedBox(width: 8),
          Expanded(
              child: ElevatedButton(
                  onPressed: widget.onCancel, child: Text(l.t('cancel')))),
        ]),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
      {bool obscure = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 6),
      Text(label,
          style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
      TextField(
          controller: c,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF3C3C3C),
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF666666)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: InputBorder.none)),
    ]);
  }

  Widget _langBtn(int idx, String text) {
    final selected = langIndex == idx;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor:
                  selected ? const Color(0xFF007ACC) : const Color(0xFF3C3C3C),
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero),
          onPressed: () => setState(() => langIndex = idx),
          child: Text(text, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
