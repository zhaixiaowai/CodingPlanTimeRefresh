import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/localization_service.dart';

/// 多组配置面板：ReorderableListView 拖动排序 + 新增/删除(确认)/编辑 + 语言。
/// 拖动用 ReorderableListView 自带拖拽（长按 handle）。
class ConfigPanel extends StatefulWidget {
  final AppConfig initial;
  final LocalizationService l10n;
  final void Function(AppConfig next, bool langChanged) onSave;
  final VoidCallback onCancel;

  /// 内容高度变化回调：放大态下 main_page 据此把窗口收缩到实际内容高，
  /// 消除固定 520 底部空白。每次 build 后 PostFrame 测量 Column 内容高 + padding 回调。
  final void Function(double contentHeight)? onHeightChanged;
  const ConfigPanel({
    super.key,
    required this.initial,
    required this.l10n,
    required this.onSave,
    required this.onCancel,
    this.onHeightChanged,
  });

  @override
  State<ConfigPanel> createState() => _ConfigPanelState();
}

class _ConfigPanelState extends State<ConfigPanel> {
  late List<ProviderConfig> _providers;
  late int _selectedIdx; // 当前编辑的 provider 索引
  late int _langIndex; // 0 auto 1 zh 2 en
  late TextEditingController _name, _url, _key, _model;
  // 触发时刻（整点 0-23）勾选状态：从 initial.triggerHours 初始化，保存时写回。
  late Set<int> _triggerHours;
  int _idCounter = 0;
  // 挂在 SingleChildScrollView 的 child Column 上：该 Column 在无界主轴下
  // size.height = 内容自然高（无 Expanded/Spacer），PostFrame 测量它 + padding
  // 回调 main_page 收缩窗口。撑满 viewport 的是外层 Container，量它拿不到内容高。
  final GlobalKey _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _providers = List.of(widget.initial.providers);
    _selectedIdx = _providers.isEmpty ? -1 : 0;
    _langIndex = (widget.initial.language ?? 'auto') == 'zh'
        ? 1
        : (widget.initial.language == 'en' ? 2 : 0);
    _name = TextEditingController();
    _url = TextEditingController();
    _key = TextEditingController();
    _model = TextEditingController();
    if (_selectedIdx >= 0) _loadFields(_selectedIdx);
    _triggerHours = Set<int>.from(widget.initial.triggerHours);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _loadFields(int idx) {
    final p = _providers[idx];
    _name.text = p.name;
    _url.text = p.apiUrl;
    _key.text = p.apiKey;
    _model.text = p.model;
  }

  void _saveCurrentFields() {
    if (_selectedIdx < 0 || _selectedIdx >= _providers.length) return;
    _providers[_selectedIdx] = _providers[_selectedIdx].copyWith(
      name: _name.text,
      apiUrl: _url.text,
      apiKey: _key.text,
      model: _model.text,
    );
  }

  String _newId() =>
      'cfg_${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}';

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    // 每次 build（含内部 setState 触发的 rebuild，如选中 provider/增删/语言切换）
    // 排一次 PostFrame 测量内容高度 → 回调 main_page 收缩窗口到实际内容高。
    // setHeight 在 main_page 有 >2px 阈值判断防抖动；窗口尺寸变化不触发本 build
    // （ConfigPanel 未监听 MediaQuery/LayoutBuilder），故无测量-收缩循环。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeight());
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      // 整面板包 SingleChildScrollView：内容超高（多 provider + 表单 + 语言）时可滚
      // 到底部保存/取消按钮。注意 ScrollView 内 Column 不能用 Spacer/Expanded（主轴
      // 无界），故删 Spacer；ReorderableListView 用 shrinkWrap + maxHeight(140) 自适应。
      child: SingleChildScrollView(
        child: Column(
          key: _contentKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 语言切换放最上面（与模型配置无关，全局设置）。
            Text(
              l.t('languageLabel'),
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _langBtn(0, l.t('languageAuto')),
                _langBtn(1, l.t('languageZh')),
                _langBtn(2, l.t('languageEn')),
              ],
            ),
            const Divider(color: Color(0xFF555555), height: 16),
            // 触发时刻（整点）网格勾选：24 个小时按钮，选中高亮。
            Text(
              l.t('triggerTimesLabel'),
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (int h = 0; h < 24; h++) _hourToggle(h)],
            ),
            const Divider(color: Color(0xFF555555), height: 16),
            // provider 列表（可拖动）：shrinkWrap 按实际内容高，ConstrainedBox
            // maxHeight=140（≈2.5 个 item）限高——provider 少时紧凑不留空白，超过
            // 2.5 个时按现有行为走滚动条。
            Text(
              l.t('configListLabel'),
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                onReorder: (oldI, newI) {
                  setState(() {
                    _saveCurrentFields();
                    // 拖动前记选中 id，重排后重新定位（避免选中跳到被拖动项）
                    final selId = _selectedIdx >= 0
                        ? _providers[_selectedIdx].id
                        : null;
                    if (newI > oldI) newI -= 1;
                    final p = _providers.removeAt(oldI);
                    _providers.insert(newI, p);
                    _selectedIdx = selId == null
                        ? -1
                        : _providers.indexWhere((e) => e.id == selId);
                    if (_selectedIdx >= 0) _loadFields(_selectedIdx);
                  });
                },
                children: [
                  for (int i = 0; i < _providers.length; i++)
                    // ReorderableListView 在子节点外会包一层 ColoredBox（拖拽底色），
                    // 直接放 ListTile 会触发 "background color may be invisible" 断言。
                    // 用透明 Material 隔离，使 ListTile 的 ink/选中色作用于自己的 Material。
                    Material(
                      key: ValueKey(_providers[i].id),
                      type: MaterialType.transparency,
                      child: ListTile(
                        dense: true,
                        selected: i == _selectedIdx,
                        selectedTileColor: const Color(
                          0xFF007ACC,
                        ).withValues(alpha: 0.3),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(
                            Icons.drag_handle,
                            color: Color(0xFF888888),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          '${_providers[i].name} (${_vendorOf(_providers[i].apiUrl)})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        trailing: TextButton.icon(
                          icon: const Icon(
                            Icons.delete,
                            size: 16,
                            color: Color(0xFFAAAAAA),
                          ),
                          label: Text(
                            l.t('deleteButton'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFAAAAAA),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _confirmDelete(i),
                        ),
                        onTap: () {
                          _saveCurrentFields();
                          setState(() {
                            _selectedIdx = i;
                            _loadFields(i);
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                _saveCurrentFields();
                setState(() {
                  final p = ProviderConfig(id: _newId(), name: l.t('newConfigName'));
                  _providers.add(p);
                  _selectedIdx = _providers.length - 1;
                  _loadFields(_selectedIdx);
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: Text(l.t('addButton'), style: const TextStyle(fontSize: 12)),
            ),
            const Divider(color: Color(0xFF555555), height: 12),
            // 编辑表单
            if (_selectedIdx >= 0) ...[
              _field(l.t('fieldName'), _name),
              _field(
                'API URL',
                _url,
                hint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
              ),
              _field('API Key', _key, hint: 'sk-xxx', obscure: true),
              _field('Model', _model, hint: 'glm-5.1 / ep-xxx'),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _onSave,
                    child: Text(l.t('save')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onCancel,
                    child: Text(l.t('cancel')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// PostFrame 测量 Column 内容高（SingleChildScrollView 无界主轴下 = 内容自然高，
  /// 与 viewport 高无关），+24（Container padding all(12) 上下）= ConfigPanel 完整内容高，
  /// 回调 main_page 据此收缩窗口。mounted 判定防 dispose 后回调。
  void _measureHeight() {
    if (!mounted) return;
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.onHeightChanged?.call(box.size.height + 24);
  }

  void _onSave() {
    _saveCurrentFields();
    final lang = _langIndex == 1 ? 'zh' : (_langIndex == 2 ? 'en' : 'auto');
    final next = AppConfig(
      providers: _providers,
      isAlwaysOnTop: widget.initial.isAlwaysOnTop,
      language: lang,
      lastTriggerKeys: widget.initial.lastTriggerKeys,
      triggerHours: _triggerHours.toList()..sort(),
    );
    widget.onSave(next, lang != (widget.initial.language ?? 'auto'));
  }

  /// 单个小时勾选按钮：GestureDetector + 固定尺寸 Container，选中蓝(0xFF007ACC)/
  /// 未选深灰(0xFF3C3C3C)，居中显示该小时数字。
  Widget _hourToggle(int h) {
    final sel = _triggerHours.contains(h);
    return GestureDetector(
      onTap: () => setState(() {
        if (sel) {
          _triggerHours.remove(h);
        } else {
          _triggerHours.add(h);
        }
      }),
      child: Container(
        width: 28,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF007ACC) : const Color(0xFF3C3C3C),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          '$h',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    );
  }

  void _confirmDelete(int idx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l10n.t('confirmDeleteTitle'),
            style: const TextStyle(fontSize: 14)),
        content: Text(
          widget.l10n.t('confirmDeleteContent').fmt([_providers[idx].name]),
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                // 删前先保存当前选中项的未提交编辑，避免被后续 _loadFields 覆盖丢失。
                _saveCurrentFields();
                _providers.removeAt(idx);
                if (idx == _selectedIdx) {
                  // 删的是选中项：调整到合法位置并加载新选中项字段。
                  if (_selectedIdx >= _providers.length) {
                    _selectedIdx = _providers.length - 1;
                  }
                  if (_selectedIdx >= 0) _loadFields(_selectedIdx);
                } else if (idx < _selectedIdx) {
                  // 删在选中项之前：选中项整体前移一位，仍指向同一 provider
                  // （控制器值已由上方 _saveCurrentFields 保存，无需 _loadFields 覆盖）。
                  _selectedIdx -= 1;
                }
                // idx > _selectedIdx：删在选中项之后，_selectedIdx 与控制器均不变。
              });
            },
            child: Text(widget.l10n.t('confirmButton')),
          ),
        ],
      ),
    );
  }

  String _vendorOf(String url) {
    final l = widget.l10n;
    if (url.contains('bigmodel.cn')) return l.t('zhipu');
    if (url.contains('ark.cn-beijing.volces.com')) return l.t('volc');
    return l.t('vendorUnknown');
  }

  Widget _field(
    String label,
    TextEditingController c, {
    String? hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
        ),
        const SizedBox(height: 4),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            border: InputBorder.none,
          ),
        ),
      ],
    );
  }

  Widget _langBtn(int idx, String text) {
    final sel = _langIndex == idx;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: sel
                ? const Color(0xFF007ACC)
                : const Color(0xFF3C3C3C),
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
          ),
          onPressed: () => setState(() => _langIndex = idx),
          child: Text(text, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
