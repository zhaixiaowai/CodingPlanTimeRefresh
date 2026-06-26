import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/localization_service.dart';

/// 配置浮层桩：旧单组字段（apiUrl/apiKey/model/isCollapsed）已移除，
/// 多组配置 UI 由 T5 的 ConfigPanel 取代。
///
/// T1 桩化：仅保留类结构与构造签名，读写首个 provider 作为占位，
/// 让全项目编译通过；真正的多组编辑逻辑在 T5 重写。
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
    final p = widget.initial.providers.isEmpty
        ? null
        : widget.initial.providers.first;
    url = TextEditingController(text: p?.apiUrl ?? '');
    key = TextEditingController(text: p?.apiKey ?? '');
    model = TextEditingController(text: p?.model ?? 'glm-5.1');
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
    // 桩：保存时把首个 provider 替换为新输入（保留其余 provider 与 id）。
    void onSave() {
      final next = AppConfig(
        providers: List<ProviderConfig>.from(widget.initial.providers),
        isAlwaysOnTop: widget.initial.isAlwaysOnTop,
        language:
            langIndex == 1 ? 'zh' : (langIndex == 2 ? 'en' : 'auto'),
        lastTriggerKeys: Map<String, String>.from(widget.initial.lastTriggerKeys),
      );
      if (next.providers.isNotEmpty) {
        final p = next.providers.first;
        next.providers[0] = p.copyWith(
          apiUrl: url.text,
          apiKey: key.text,
          model: model.text,
        );
      } else {
        next.providers.add(ProviderConfig(
          id: 'legacy',
          apiUrl: url.text,
          apiKey: key.text,
          model: model.text,
        ));
      }
      widget.onSave(next, next.language != (widget.initial.language ?? 'auto'));
    }

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
                  onPressed: onSave, child: Text(l.t('save')))),
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
