import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/usage_info.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import '../services/localization_service.dart';
import '../services/log_service.dart';
import '../services/scheduler_service.dart';
import '../platform/window_controller.dart';
import 'widgets/usage_row.dart';
import 'widgets/config_overlay.dart';
import 'widgets/result_overlay.dart';

/// 主界面：平移旧 MAUI `MainPage`（`MainPage.xaml` + `MainPage.xaml.cs`）的全部交互。
///
/// - 两个 `Timer.periodic`：6s 检查触发时段 / 60s 轮询 BigModel 用量。
/// - 命中 01/07/13/19 点流式调用 LLM，失败自动重试 3 次（每次间隔 5s）。
/// - 用量三行（Token(5H) / Token(周) / MCP(月)），百分比着色 `>=80` 红 / `>=50` 橙 / 其余蓝。
/// - 折叠/展开（联动窗口高度 + 持久化 `IsCollapsed`）、置顶、配置浮层、结果浮层。
/// - 流式输出节流：累积到 `StringBuffer`，每 50ms 最多 setState 一次。
///
/// 关于本地化占位符：`LocalizationService.fmt` 真解析 .NET 复合格式
/// （`{0}` / `{0:format}`）。带格式说明符的占位（`:HH:mm` 等）若对应参数为
/// `DateTime`，则用 `intl` 的 `DateFormat` 按该格式渲染；参数为 `String`/`num`
/// 等时忽略格式直接替换。因此调用方可直接传 `DateTime`（如 `resultTimestamp`
/// 的 `{0:HH:mm:ss}`），无需预先格式化。`args` 顺序须与占位符出现顺序一致。
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

class _MainPageState extends State<MainPage> {
  late AppConfig _config;
  bool _collapsed = false;
  bool _isBusy = false;
  // 重试循环重入守卫：与 _isBusy 分工——_isBusy 管单次尝试（防手动+自动并发），
  // _isRetrying 管整个重试循环（防多次自动触发并发进入 _callLlmWithRetry）。
  bool _isRetrying = false;
  bool _showConfig = false;
  bool _showResult = false;
  String _resultText = '';
  String _resultHeader = '';
  String _nextTriggerText = '';
  UsageInfo? _usage;
  Timer? _triggerTimer;
  Timer? _usageTimer;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _collapsed = _config.isCollapsed;
    _resultHeader = widget.l10n.t('resultHeader');
    if (_config.apiUrl.isEmpty || _config.apiKey.isEmpty) _showConfig = true;
    _triggerTimer = Timer.periodic(const Duration(seconds: 6), (_) => _onTriggerTick());
    _usageTimer = Timer.periodic(const Duration(seconds: 60), (_) => _queryUsage());
    _queryUsage();
    _updateNextTrigger();
  }

  @override
  void dispose() {
    _triggerTimer?.cancel();
    _usageTimer?.cancel();
    super.dispose();
  }

  /// 6s 定时器：刷新下次触发标签，并检查是否命中触发时段。
  void _onTriggerTick() {
    _updateNextTrigger();
    final r = SchedulerService.checkTrigger(DateTime.now(), _config.lastAutoTriggerKey);
    if (!r.trigger) return;
    _config.lastAutoTriggerKey = r.key;
    widget.configService.save(_config);
    _callLlmWithRetry();
  }

  /// 单次流式调用 LLM。
  ///
  /// - [manual]：是否手动触发（手动触发失败不清空 `lastAutoTriggerKey`）。
  /// 返回是否成功（true=成功）。每次调用结束（finally）复位 `_isBusy`，
  /// 使重试循环下次进入时 `_isBusy=false` 能正常执行——平移旧 MAUI
  /// `CallLLMAsync` 的「单次尝试 + finally 复位 + 调用方循环重试」结构。
  /// 流式输出节流：`onChunk` 累积到 `buf` + `flushTimer` 50ms flush，
  /// 避免逐 chunk 高频 setState 卡顿；流结束后 `flush()` 确保完整文本落盘。
  Future<bool> _callLlmOnce({required bool manual}) async {
    if (_isBusy) return false;
    setState(() {
      _isBusy = true;
      _resultText = widget.l10n.t('loading');
      _showResult = true;
    });
    final buf = StringBuffer();
    Timer? flushTimer;
    void flush() {
      flushTimer = null;
      if (mounted) setState(() => _resultText = buf.toString());
    }
    try {
      final model = _config.model.isEmpty ? 'glm-5.1' : _config.model;
      final prompt =
          '${widget.l10n.t('jokePrompt')}\nseed=${DateTime.now().millisecondsSinceEpoch % 10000}';
      await widget.llm.askStream(
        apiUrl: _config.apiUrl,
        apiKey: _config.apiKey,
        model: model,
        question: prompt,
        onChunk: (c) {
          if (buf.isEmpty) setState(() => _resultText = ''); // 清掉 loading 占位
          buf.write(c);
          flushTimer ??= Timer(const Duration(milliseconds: 50), flush);
        },
      );
      flush(); // 流结束后确保完整文本落盘
      // 平移旧 MAUI：成功后表头改为「返回结果(最后调用于 HH:mm:ss)」。
      // resultTimestamp 占位 `{0:HH:mm:ss}` 由 fmt 真解析，直接传 DateTime。
      if (mounted) {
        setState(() => _resultHeader =
            widget.l10n.t('resultTimestamp').fmt([DateTime.now()]));
      }
      return true;
    } catch (e) {
      if (!manual) {
        _config.lastAutoTriggerKey = '';
        widget.configService.save(_config);
      }
      // LlmException 走 l10n 键映射（与旧 MAUI 抛 AppResources.XXX 一致）；
      // 其它异常（超时/网络等）兜底用 errorMessage。
      final displayText = e is LlmException
          ? widget.l10n.t(e.l10nKey).fmt(e.args)
          : widget.l10n.t('errorMessage').fmt(['$e']);
      if (mounted) setState(() => _resultText = displayText);
      widget.log.append('[Error] $e');
      return false;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// 自动触发的重试循环（平移旧 MAUI `OnTimerTick` 的 `for attempt 1..3`）。
  ///
  /// 最多尝试 3 次，每次间隔 5s；某次成功即跳出。`_callLlmOnce` 每次 finally
  /// 复位 `_isBusy`，故下次循环进入时 `_isBusy=false` 能正常执行（修复了旧实现
  /// 递归重试时 `_isBusy` 仍为 true、导致重试永不执行的死代码）。
  ///
  /// 重入守卫 `_isRetrying`：自动触发失败时 `_callLlmOnce` 会清空
  /// `lastAutoTriggerKey`（catch 里），6s 后的 `_onTriggerTick` 会重新命中
  /// `checkTrigger` 并启动第二个并发的 `_callLlmWithRetry`——此处直接 return 挡掉。
  /// 注意 `_isRetrying` 与 `_isBusy` 是两个不同标志：`_isRetrying` 锁整个重试循环，
  /// `_isBusy` 锁单次尝试；手动触发的 `_callLlmOnce(manual:true)` 不受 `_isRetrying`
  /// 影响（但受 `_isBusy` 影响）。
  Future<void> _callLlmWithRetry() async {
    if (_isRetrying) return;
    _isRetrying = true;
    try {
      for (int attempt = 1; attempt <= 3; attempt++) {
        if (await _callLlmOnce(manual: false)) break;
        if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
      }
    } finally {
      _isRetrying = false;
    }
  }

  /// 60s 定时器：轮询 BigModel 用量配额并更新标题/三行用量。
  ///
  /// 用量更新后若处于折叠态，按 weekly 数据有无重算窗口高度（平移旧 MAUI
  /// `UpdateLimitRow` 中 `if (_collapsed) ResizeCollapsed()` 的联动）。
  Future<void> _queryUsage() async {
    if (_config.apiUrl.isEmpty || _config.apiKey.isEmpty) return;
    if (!_config.apiUrl.contains('bigmodel.cn')) return;
    final u = await widget.llm.queryBigmodelUsage(_config.apiKey);
    if (u == null) return;
    final primary = u.hour5?.percentage ?? u.mcp?.percentage ?? 0;
    final level = (u.level == null || u.level!.isEmpty)
        ? ''
        : ' ${u.level![0].toUpperCase()}${u.level!.substring(1)}';
    await widget.window
        .setTitle(widget.l10n.t('windowTitle').fmt([primary, level.trim()]));
    if (mounted) {
      setState(() => _usage = u);
      // weekly 显隐变化（null↔非 null）时折叠态高度 120↔142 联动。
      if (_collapsed) _applyCollapsedHeight();
    }
  }

  /// 刷新「下次触发」标签。
  ///
  /// nextTriggerFormat 占位 `{0:HH:mm}` 由 fmt 真解析，直接传 DateTime（next）；
  /// 后两个占位 `{1}`/`{2}` 为分/秒（int，无格式）。
  void _updateNextTrigger() {
    final next = SchedulerService.nextTrigger(DateTime.now(), _config.lastAutoTriggerKey);
    if (next == null) return;
    final diff = next.difference(DateTime.now());
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    setState(() => _nextTriggerText =
        widget.l10n.t('nextTriggerFormat').fmt([next, m, s]));
  }

  /// 重置时刻（Unix 毫秒）→ 「重置 HH:mm」（今天）或「重置 MM/dd HH:mm」（其他天）。
  /// 占位 `{0:HH:mm}` / `{0:MM/dd HH:mm}` 由 fmt 真解析，直接传 DateTime。
  String _resetText(int? ms) {
    if (ms == null || ms < 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    return widget.l10n.t(isToday ? 'resetToday' : 'resetOther').fmt([dt]);
  }

  /// 折叠态根据 weekly 是否存在重算窗口高度（平移旧 MAUI `ResizeCollapsed` +
  /// `UpdateLimitRow` 的 `if (_collapsed) ResizeCollapsed`）。展开态不适用。
  void _applyCollapsedHeight() {
    if (!_collapsed) return;
    final h = _usage?.weekly != null
        ? ConfigService.collapsedHeightWithWeekly
        : ConfigService.collapsedHeight;
    widget.window.setHeight(ConfigService.expandedWidth, h);
  }

  /// 折叠/展开：联动窗口高度（折叠走 _applyCollapsedHeight，展开用 expandedHeight）
  /// + 持久化 IsCollapsed。
  void _toggleCollapse() {
    setState(() => _collapsed = !_collapsed);
    _config.isCollapsed = _collapsed;
    widget.configService.save(_config);
    if (_collapsed) {
      _applyCollapsedHeight();
    } else {
      widget.window.setHeight(ConfigService.expandedWidth, ConfigService.expandedHeight);
    }
  }

  /// 翻转置顶状态（平移旧 MAUI：点 pinLabel 文字 ↔ checkbox 同一逻辑）。
  /// 旧 MAUI `OnTopMostLabelTapped` 仅翻转 checkbox，由 `CheckedChanged` 触发
  /// 实际逻辑；Flutter 此处直接翻转并落盘，checkbox `onChanged` 与 label
  /// `onTap` 共用本方法。
  void _toggleAlwaysOnTop() {
    setState(() => _config.isAlwaysOnTop = !_config.isAlwaysOnTop);
    widget.window.setAlwaysOnTop(_config.isAlwaysOnTop);
    widget.configService.save(_config);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: Stack(children: [
        // 主内容：下次触发 + 三行用量（ScrollView 内可滚，平移旧 MAUI <ScrollView>）。
        // 折叠态窗口矮时内容可滚而非硬裁剪；bottom bar 固定在 ScrollView 外。
        Column(children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                child: Column(children: [
                  Align(
                      alignment: Alignment.centerRight,
                      child: Text(_nextTriggerText,
                          style: const TextStyle(
                              color: Color(0xFF666666), fontSize: 10))),
                  const Divider(color: Color(0xFF444444), height: 5),
                  // 三行始终占位（平移旧 MAUI 三行 Grid 始终在 InfoSection，
                  // 空 Label 占行高），info 为 null 时 UsageRow 内部已处理空显示。
                  UsageRow(label: l.t('token5hLabel'), info: _usage?.hour5, resetText: _resetText),
                  UsageRow(label: l.t('tokenWeekLabel'), info: _usage?.weekly, resetText: _resetText),
                  UsageRow(label: l.t('mcpMonthLabel'), info: _usage?.mcp, resetText: _resetText),
                ]),
              ),
            ),
          ),
          // 底部栏：手动触发 + 置顶 + 设置（折叠态隐藏；固定在 ScrollView 外）
          if (!_collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Row(children: [
                ElevatedButton(
                    onPressed: _isBusy
                        ? null
                        : () => setState(() => _showResult = true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007ACC)),
                    child: Text(l.t('manualTrigger'))),
                const Spacer(),
                Row(children: [
                  Checkbox(
                      value: _config.isAlwaysOnTop,
                      onChanged: (_) => _toggleAlwaysOnTop()),
                  GestureDetector(
                      onTap: _toggleAlwaysOnTop,
                      child: Text(l.t('pinLabel'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12))),
                  IconButton(
                      onPressed: () => setState(() => _showConfig = true),
                      icon: const Icon(Icons.settings,
                          color: Color(0xFFAAAAAA), size: 18)),
                ]),
              ]),
            ),
        ]),
        // 折叠三角（左上）
        Positioned(
            left: 4,
            top: 4,
            child: GestureDetector(
              onTap: _toggleCollapse,
              child: Icon(
                  _collapsed
                      ? Icons.arrow_drop_down
                      : Icons.arrow_drop_up,
                  color: const Color(0xFF888888)),
            )),
        if (_showResult)
          ResultOverlay(
              header: _resultHeader,
              text: _resultText,
              placeholder: l.t('waitingPlaceholder'),
              onClose: () => setState(() => _showResult = false),
              onTrigger: () => _callLlmOnce(manual: true),
              l10n: l),
        if (_showConfig)
          ConfigOverlay(
              initial: _config,
              l10n: l,
              onSave: (next, langChanged) {
                final urlChanged = next.apiUrl != _config.apiUrl ||
                    next.apiKey != _config.apiKey;
                setState(() {
                  _config = next;
                  _showConfig = false;
                });
                widget.configService.save(_config);
                if (langChanged) {
                  widget.l10n.setLanguage(next.language ?? 'auto');
                  // 语言切换后重置表头为「返回结果」（不带时间戳），与旧 MAUI RefreshUI 一致。
                  setState(() => _resultHeader = widget.l10n.t('resultHeader'));
                  _updateNextTrigger();
                  _queryUsage();
                }
                if (urlChanged) _queryUsage();
              },
              onCancel: () => setState(() => _showConfig = false)),
      ]),
    );
  }
}
