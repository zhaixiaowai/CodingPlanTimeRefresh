import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/usage_info.dart';
import '../services/bigmodel_usage_provider.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import '../services/localization_service.dart';
import '../services/log_service.dart';
import '../services/usage_provider.dart';
import '../services/scheduler_service.dart';
import '../services/volc_ark_usage_provider.dart';
import '../platform/window_controller.dart';
import 'widgets/config_panel.dart';
import 'widgets/result_panel.dart';
import 'widgets/usage_frame.dart';

/// 主窗口（mini 态）：顶部 ☰ 菜单 + 置顶外露 + 每 provider 一个 UsageFrame 垂直排列。
///
/// 旧 MAUI 单组 / 折叠三角 / 单一用量区在本设计中已废弃：mini 态固定显示所有
/// provider 的用量框（ScrollView 可滚），LLL 触发与放大态由 T7/T8 接入。
class MainPage extends StatefulWidget {
  final AppConfig config;
  final ConfigService configService;
  final LlmService llm;
  final LogService log;
  final LocalizationService l10n;
  final WindowController window;
  const MainPage({
    super.key,
    required this.config,
    required this.configService,
    required this.llm,
    required this.log,
    required this.l10n,
    required this.window,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

/// 单个 provider 的运行时结果状态（定时与手动触发共享）。
///
/// - text: 流式回填的冷笑话文本（节流 50ms）。
/// - header: 结果时间戳（resultTimestamp）或失败/无结果时为空。
/// - isBusy: 该 provider 单次调用进行中（防同一 provider 重复调用）。
/// - isRetrying: 该 provider 处于「重试循环」中（防定时与手动同时进入重试）。
class ResultState {
  String text = '';
  String header = '';
  bool isBusy = false;
  bool isRetrying = false;
}

class _MainPageState extends State<MainPage> {
  late AppConfig _config;
  // key = provider.id
  final Map<String, UsageResult> _usages = {};
  final Map<String, ResultState> _results = {};
  Timer? _usageTimer;
  Timer? _triggerTimer;
  double _lastContentHeight = 0;

  // 高度自适应测量键：挂在 mini 的整个内容（topBar + 各 UsageFrame + padding）
  // 外层（SingleChildScrollView 的 child），量其完整渲染高作为窗口内容高。
  final GlobalKey _contentKey = GlobalKey();

  // 放大态：true 时窗口为 420×520，_enlargedMode 决定放大区显示哪个面板。
  // 'config' → ConfigPanel（设置）；'trigger' → ResultPanel（手动触发，替代 T7 Dialog）。
  bool _enlarged = false;
  String? _enlargedMode;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    for (final p in _config.providers) {
      _results[p.id] = ResultState();
    }
    _usageTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _queryAllUsage());
    _queryAllUsage();
    _triggerTimer =
        Timer.periodic(const Duration(seconds: 6), (_) => _onTriggerTick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
  }

  @override
  void dispose() {
    _triggerTimer?.cancel();
    _usageTimer?.cancel();
    super.dispose();
  }

  /// 厂商识别 → 返回该 provider 的 UsageProvider（未知返回 null）。
  ///
  /// 按 apiUrl 域名匹配：`bigmodel.cn` → 智谱，`ark.cn-beijing.volces.com` → 火山方舟。
  /// 未识别的厂商返回 null，调用方显示「未知厂商」。
  UsageProvider? _providerFor(ProviderConfig p) {
    final url = p.apiUrl;
    if (url.contains('bigmodel.cn')) {
      return BigmodelUsageProvider(p.apiKey, widget.log);
    }
    if (url.contains('ark.cn-beijing.volces.com')) {
      return VolcArkUsageProvider();
    }
    return null;
  }

  Future<void> _queryAllUsage() async {
    for (final p in _config.providers) {
      final provider = _providerFor(p);
      if (provider == null) {
        _usages[p.id] =
            const UsageResult('未知厂商', [], '未知厂商，不支持用量查询');
        continue;
      }
      final result = await provider.query();
      if (!mounted) return;
      setState(() => _usages[p.id] = result);
    }
    if (!mounted) return;
    // 更新窗口标题：每 provider 一组「5h%/周%」，多 provider 用 | 连接。
    await widget.window.setTitle(_buildWindowTitle());
    WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
  }

  /// 拼接窗口标题：按 _config.providers 顺序，每个 provider 一组
  /// `{厂商}:{5h}/{周}`，多 provider 用空格连。
  /// - 厂商名从 vendorTitle 取空格前部分（如「智谱 Pro」→「智谱」）。
  /// - 有 5h+周：`0/100`；只有 5h：`0`；只周：`100`。
  /// 百分比四舍五入为整数；失败的 provider（errorMessage 非 null）跳过。
  /// 全部无用量时返回应用名兜底。
  String _buildWindowTitle() {
    final groups = <String>[];
    for (final p in _config.providers) {
      final u = _usages[p.id];
      if (u == null || u.errorMessage != null) continue;
      int? h5 = _pctOf(u, 'token5h');
      int? weekly = _pctOf(u, 'tokenWeekly');
      if (h5 == null && weekly == null) continue;
      final parts = <String>[];
      if (h5 != null) parts.add('$h5');
      if (weekly != null) parts.add('$weekly');
      if (parts.isEmpty) continue;
      final vendor = u.vendorTitle.split(' ').first;
      groups.add('$vendor：${parts.join('/')}');
    }
    return groups.isEmpty ? 'Coding Plan Time Refresh' : groups.join(' ');
  }

  /// 从 UsageResult 取指定 labelKey 的百分比（四舍五入整数），无则 null。
  int? _pctOf(UsageResult u, String labelKey) {
    for (final it in u.items) {
      if (it.labelKey == labelKey) return it.percentage.round();
    }
    return null;
  }

  // ===== LLM 触发（定时遍历所有 providers + per-provider ResultState）=====

  /// 全局触发时刻去重键：触发是全局时刻（01/07/13/19 点整），所有 provider 共享
  /// 同一触发时刻，故用一个 `__global__` key 判定「该整点是否已触发过」即可。
  /// 命中后写入；**失败不清 key**——自动失败的「立即重试」由 _callLlmWithRetry
  /// 的 3 次循环负责（isRetrying 防并发），下个触发时刻才整点再触发所有 provider。
  /// 这样 A 成功 B 失败时 B 走重试循环、A 不会被重复触发（旧 MAUI 清单值 key 会导致
  /// A 被重复打）；A 在下个整点多调一次可接受（与旧 MAUI 一致）。
  String _globalTriggerKey() => _config.lastTriggerKeys['__global__'] ?? '';
  void _setGlobalTriggerKey(String k) =>
      _config.lastTriggerKeys['__global__'] = k;

  /// 6 秒轮询：命中触发时段（01/07/13/19 点整）且本轮未触发 → 遍历所有
  /// providers 各自调用（per-provider 重试，互不阻塞）。
  void _onTriggerTick() {
    final r = SchedulerService.checkTrigger(DateTime.now(), _globalTriggerKey());
    if (!r.trigger) return;
    _setGlobalTriggerKey(r.key);
    widget.configService.save(_config);
    for (final p in _config.providers) {
      _callLlmWithRetry(p.id);
    }
  }

  /// per-provider 单次调用（节流 50ms 更新该 provider ResultState.text）。
  ///
  /// [manual] = true 表示手动触发（直接调一次，不进入重试循环）；自动触发由
  /// _callLlmWithRetry 包裹（3 次重试）。失败**不清全局触发键**——自动失败的
  /// 「立即重试」由重试循环负责（isRetrying 防并发），下个整点才再触发（见
  /// _globalTriggerKey 说明，避免 A 成功 B 失败时 A 被重复打）。返回是否成功。
  Future<bool> _callLlmOnce(String providerId, {required bool manual}) async {
    if (providerId.isEmpty) return false;
    // firstWhere 用空对象 orElse：provider 已删（不在列表）时返回 id='' 占位，由
    // p.id.isEmpty 判定 return false——不抛 StateError（空列表 .first 抛）、不用错
    // provider（原 orElse 回退到 first 会拿错配置调 LLM）调 LLM。
    final p = _config.providers.firstWhere(
      (e) => e.id == providerId,
      orElse: () => ProviderConfig(
          id: '', name: '', apiUrl: '', apiKey: '', model: ''),
    );
    if (p.id.isEmpty) return false;
    final rs = _results[providerId];
    if (rs == null) return false;
    if (rs.isBusy) return false;
    rs.isBusy = true;
    rs.text = widget.l10n.t('loading');
    if (mounted) setState(() {});
    final buf = StringBuffer();
    Timer? flushTimer;
    try {
      final model = p.model.isEmpty ? 'glm-5.1' : p.model;
      final prompt =
          '${widget.l10n.t('jokePrompt')}\nseed=${DateTime.now().millisecondsSinceEpoch % 10000}';
      await widget.llm.askStream(
        apiUrl: p.apiUrl,
        apiKey: p.apiKey,
        model: model,
        question: prompt,
        onChunk: (c) {
          if (buf.isEmpty) rs.text = '';
          buf.write(c);
          rs.text = buf.toString();
          flushTimer ??= Timer(const Duration(milliseconds: 50), () {
            flushTimer = null;
            if (mounted) setState(() {});
          });
        },
      );
      if (mounted) {
        rs.header = widget.l10n.t('resultTimestamp').fmt([DateTime.now()]);
        setState(() {});
      }
      return true;
    } catch (e) {
      // 失败不清全局触发键：自动失败的「立即重试」由 _callLlmWithRetry 的 3 次循环
      // 负责（isRetrying 防并发），下个整点才再触发（避免 A 成功 B 失败时 A 被重复打）。
      // [manual] 在此无副作用，仅作语义标记（手动不进重试循环，由调用方控制）。
      rs.text = e is LlmException
          ? widget.l10n.t(e.l10nKey).fmt(e.args)
          : widget.l10n.t('errorMessage').fmt(['$e']);
      rs.header = '';
      widget.log.append('[Error] $e');
      if (mounted) setState(() {});
      return false;
    } finally {
      rs.isBusy = false;
      if (mounted) setState(() {});
    }
  }

  /// per-provider 重试循环：3 次×5s 间隔，用 rs.isRetrying 防并发。
  Future<void> _callLlmWithRetry(String providerId) async {
    final rs = _results[providerId];
    if (rs == null) return;
    if (rs.isRetrying) return;
    rs.isRetrying = true;
    try {
      for (int attempt = 1; attempt <= 3; attempt++) {
        if (await _callLlmOnce(providerId, manual: false)) break;
        if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
      }
    } finally {
      rs.isRetrying = false;
    }
  }

  // ===== 放大态（T8）=====

  /// 打开放大态：切到 [mode]（'config' / 'trigger'）并放大窗口到 420×520。
  ///
  /// 先 await enlarge（窗口先放大），再 setState 切放大态布局——避免放大态布局在
  /// 旧 mini 尺寸窗口渲染一帧被裁剪。enlarge 内会先平移到屏内再 setSize。
  Future<void> _openEnlarged(String mode) async {
    await widget.window.enlarge(w: 420, h: 520);
    if (!mounted) return;
    setState(() {
      _enlarged = true;
      _enlargedMode = mode;
    });
  }

  /// 关闭放大态：缩回 mini（保留当前位置），由放大区面板的保存/取消/关闭触发。
  ///
  /// 先 setState 切回 mini 布局（比放大态被裁好），再用旧高 shrinkToContent 缩回，
  /// 最后排 PostFrame 重测到新内容高（修注释承诺的"修正"——配置增删 provider 后
  /// 缩回会立即重测）。_resizeToContent 内 `if (_enlarged) return` 不影响（此处已置 false）。
  Future<void> _closeEnlarged() async {
    setState(() {
      _enlarged = false;
      _enlargedMode = null;
    });
    await widget.window.shrinkToContent(_lastContentHeight);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
    }
  }

  /// ConfigPanel 保存回调：写回 _config、持久化，并同步 _results/_usages（增删 provider）。
  ///
  /// 平移 T7 concern 收尾：用户在 ConfigPanel 增删/重排 providers 后，mini 态的
  /// UsageFrame 列表与 ResultPanel 的下拉项都依赖 `_config.providers`（已随 setState
  /// 更新），但运行时态 `_results`/`_usages` 是按 id 索引的 Map——新增 provider 没
  /// 有对应条目会显示空、删除 provider 的残留条目会泄漏。这里按「以新 providers 为准」
  /// 对齐：新增 id 加空 ResultState、删除 id 清其 _results/_usages/lastTriggerKeys。
  void _onConfigSaved(AppConfig next, bool langChanged) {
    final oldIds = _config.providers.map((p) => p.id).toSet();
    final newIds = next.providers.map((p) => p.id).toSet();
    // 删除：旧有新无 → 清运行时态 + 触发键。
    for (final id in oldIds.difference(newIds)) {
      _results.remove(id);
      _usages.remove(id);
      _config.lastTriggerKeys.remove(id);
    }
    // 新增：新有旧无 → 加空 ResultState（_usages 会在下个 _queryAllUsage 周期填充）。
    for (final id in newIds.difference(oldIds)) {
      _results[id] = ResultState();
    }
    setState(() {
      _config = next;
      if (langChanged) {
        widget.l10n.initialize(next.language ?? 'auto');
      }
    });
    widget.configService.save(_config);
    _closeEnlarged();
    // 新增/改动的 provider 立即查一次用量，避免空白框等到下个 60s tick。
    // （_closeEnlarged 已切回 mini 并排了 PostFrame 重测高度；这里异步查用量，
    // 查完 setState 各框填充 + 再排一次 PostFrame 修正高度。）
    _queryAllUsage();
  }

  /// 测量内容高度 → setHeight（高度自适应，仅超阈值才调避免抖动）。
  ///
  /// mini 态把 topBar + 各 UsageFrame 全放进 SingleChildScrollView 的 child，
  /// 用 _contentKey 挂在该 child，量其 RenderBox 完整渲染高（含 topBar + 全部
  /// 框 + padding），一次量全，避免分段相加漏算顶部。放大态不参与自适应
  /// （窗口固定 420×520），直接 return，否则会用 520 污染 _lastContentHeight，
  /// 导致缩回 mini 时 shrinkToContent(520)。
  void _resizeToContent() {
    if (_enlarged) return;
    if (!mounted) return;
    final contentBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null) return;
    final h = contentBox.size.height;
    if ((h - _lastContentHeight).abs() > 2) {
      _lastContentHeight = h;
      widget.window.setHeight(ConfigService.expandedWidth, h);
    }
  }

  /// Unix 毫秒 → 本地化重置文本（今天用 HH:mm，其它日期用 MM/dd HH:mm）。
  String _resetText(int? ms) {
    if (ms == null || ms < 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    // 复合格式（resetToday/resetOther）的占位符 {0:HH:mm} / {0:MM/dd HH:mm} 由
    // FmtString.fmt 内部按 DateTime 参数渲染，此处无需单独构造 DateFormat。
    return widget.l10n.t(isToday ? 'resetToday' : 'resetOther').fmt([dt]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: _enlarged ? _buildEnlarged() : _buildMini(),
    );
  }

  /// 顶部栏：☰ 菜单 + 置顶外露（mini 态用；放大态覆盖顶部栏，不渲染此）。
  /// 控件强制小尺寸：icon 14、Checkbox scale 缩放、整体 SizedBox(height:20) 锁行高
  /// （约 24 含 padding），避免 Material 默认触摸目标撑高行。
  Widget _buildTopBar() {
    final l = widget.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: SizedBox(
        height: 20,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PopupMenuButton<String>(
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minHeight: 20, minWidth: 20),
              tooltip: '',
              icon: const Icon(Icons.menu, color: Color(0xFFAAAAAA), size: 14),
              onSelected: (v) {
                if (v == 'config') {
                  _openEnlarged('config');
                } else if (v == 'trigger') {
                  _openEnlarged('trigger');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'config', child: Text(l.t('settings'))),
                PopupMenuItem(
                    value: 'trigger', child: Text(l.t('manualTrigger'))),
              ],
            ),
            const Spacer(),
            Transform.scale(
              scale: 0.7,
              child: Checkbox(
                value: _config.isAlwaysOnTop,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  setState(() => _config.isAlwaysOnTop = v ?? false);
                  widget.window.setAlwaysOnTop(_config.isAlwaysOnTop);
                  widget.configService.save(_config);
                },
              ),
            ),
            Text(l.t('pinLabel'),
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// mini 态：顶部栏（☰+置顶）+ 每 provider 一个 UsageFrame。
  /// 不用 ScrollView——窗口高度自适应（setHeight=内容高+补偿），内容永远≤窗口，
  /// 无需滚动。直接 Column，量其完整渲染高作为窗口内容高，避免 ScrollView 的
  /// viewport 约束干扰测量（曾导致量到的 contentH 偏小、却仍出滚动条）。
  Widget _buildMini() {
    final l = widget.l10n;
    return Padding(
      key: _contentKey,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _config.providers
                  .map((p) => UsageFrame(
                        result: _usages[p.id] ??
                            const UsageResult('', [], null),
                        l10n: l,
                        resetText: _resetText,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 放大态：整个窗口铺满 ConfigPanel/ResultPanel，**覆盖顶部 ☰+置顶行**
  /// （面板自带取消/✕ 关闭，不再外露顶部栏）。mini 态才显示 ☰+置顶。
  Widget _buildEnlarged() {
    return _enlargedMode == 'config'
        ? ConfigPanel(
            initial: _config,
            l10n: widget.l10n,
            onSave: _onConfigSaved,
            onCancel: _closeEnlarged,
          )
        : ResultPanel(
            providers: _config.providers,
            getText: (id) => _results[id]?.text ?? '',
            getHeader: (id) => _results[id]?.header ?? '',
            onTrigger: (id) => _callLlmOnce(id, manual: true),
            onClose: _closeEnlarged,
            l10n: widget.l10n,
          );
  }
}
