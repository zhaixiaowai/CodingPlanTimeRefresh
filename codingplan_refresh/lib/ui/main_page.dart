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
    WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
  }

  // ===== LLM 触发（定时遍历所有 providers + per-provider ResultState）=====

  /// 全局触发去重键（沿用单值语义：整点命中后所有 provider 都触发一次）。
  /// 存 `lastTriggerKeys['__global__']`，命中后写入；自动失败时清空允许重试。
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
  /// [manual] = true 表示手动触发（失败不清全局 key，让定时仍可在下个时段重试）；
  /// 自动触发失败时清全局 key 允许下一 tick 立即重试。返回是否成功。
  Future<bool> _callLlmOnce(String providerId, {required bool manual}) async {
    if (providerId.isEmpty) return false;
    final p = _config.providers.firstWhere(
      (e) => e.id == providerId,
      orElse: () => _config.providers.first,
    );
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
      if (!manual) {
        // 自动失败清全局 key，允许下个 tick 重试（与旧 MAUI 一致）。
        _setGlobalTriggerKey('');
        widget.configService.save(_config);
      }
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

  /// 测量内容高度 → setSize（高度自适应，仅超阈值才调避免抖动）。
  ///
  /// 通过 PostFrameCallback 在渲染完成后用 findRenderObject 取实际内容高，
  /// 与上次记录差值 > 2px 才调 setHeight；阈值防抖避免每次 setState 都重设窗口。
  void _resizeToContent() {
    final ctx = context;
    if (!mounted) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final h = box.size.height;
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
    final l = widget.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: Column(children: [
        // 顶部栏：☰ 菜单 + 置顶外露
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu, color: Color(0xFFAAAAAA), size: 20),
              tooltip: '',
              onSelected: (v) async {
                if (v == 'trigger') {
                  // T8 改为真正的窗口放大态；此处先用 Dialog 占位显示 ResultPanel。
                  await showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      child: SizedBox(
                        width: 380,
                        height: 460,
                        child: ResultPanel(
                          providers: _config.providers,
                          getText: (id) => _results[id]?.text ?? '',
                          getHeader: (id) => _results[id]?.header ?? '',
                          onTrigger: (id) =>
                              _callLlmOnce(id, manual: true),
                          l10n: widget.l10n,
                        ),
                      ),
                    ),
                  );
                } else if (v == 'config') {
                  // T8 接入 ConfigPanel 放大态（配合 T5）。
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'config', child: Text(l.t('settings'))),
                PopupMenuItem(
                    value: 'trigger', child: Text(l.t('manualTrigger'))),
              ],
            ),
            const Spacer(),
            Checkbox(
              value: _config.isAlwaysOnTop,
              onChanged: (v) {
                setState(() => _config.isAlwaysOnTop = v ?? false);
                widget.window.setAlwaysOnTop(_config.isAlwaysOnTop);
                widget.configService.save(_config);
              },
            ),
            Text(l.t('pinLabel'),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(width: 4),
          ]),
        ),
        // 用量框列表（每 provider 一个，ScrollView 可滚）
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
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
          ),
        ),
      ]),
    );
  }
}
