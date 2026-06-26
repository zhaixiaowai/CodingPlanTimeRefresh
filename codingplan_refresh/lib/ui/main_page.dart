import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
/// 关于本地化占位符：`LocalizationService.fmt` 用正则按出现顺序整体替换
/// `{0}` / `{0:format}`，格式说明符（`:HH:mm` 等）语义被忽略。因此凡用到带格式
/// 占位的字符串（`nextTriggerFormat` / `resetToday` / `resetOther` / `resultTimestamp`），
/// 时间值必须**预先用 `DateFormat` 格式化成最终字符串**再传 `fmt`——绝不能传裸
/// `DateTime` 或 `DateTime.toString()`。
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
      // resultTimestamp 占位 `{0:HH:mm:ss}` 语义被 fmt 忽略，须预先格式化时间值。
      if (mounted) {
        setState(() => _resultHeader = widget.l10n
            .t('resultTimestamp')
            .fmt([DateFormat('HH:mm:ss').format(DateTime.now())]));
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
      setState(() => _resultText = displayText);
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
  Future<void> _callLlmWithRetry() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      if (await _callLlmOnce(manual: false)) break;
      if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
    }
  }

  /// 60s 定时器：轮询 BigModel 用量配额并更新标题/三行用量。
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
    setState(() => _usage = u);
  }

  /// 刷新「下次触发」标签。
  ///
  /// nextTriggerFormat 占位 `{0:HH:mm}` 语义被 fmt 忽略，须预先把 next 用
  /// `DateFormat('HH:mm')` 格式化成字符串——绝不能传 `'$next'`（会得到
  /// `2026-06-26 01:00:00.000` 这样的 ISO 串）。
  void _updateNextTrigger() {
    final next = SchedulerService.nextTrigger(DateTime.now(), _config.lastAutoTriggerKey);
    if (next == null) return;
    final diff = next.difference(DateTime.now());
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    setState(() => _nextTriggerText = widget.l10n
        .t('nextTriggerFormat')
        .fmt([DateFormat('HH:mm').format(next), m, s]));
  }

  /// 重置时刻（Unix 毫秒）→ 「重置 HH:mm」（今天）或「重置 MM/dd HH:mm」（其他天）。
  /// 占位 `{0:HH:mm}` / `{0:MM/dd HH:mm}` 语义被 fmt 忽略，须预先格式化 dt。
  String _resetText(int? ms) {
    if (ms == null || ms < 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final formatted = isToday
        ? DateFormat('HH:mm').format(dt)
        : DateFormat('MM/dd HH:mm').format(dt);
    return widget.l10n.t(isToday ? 'resetToday' : 'resetOther').fmt([formatted]);
  }

  /// 折叠/展开：联动窗口高度（从 ConfigService 取常量）+ 持久化 IsCollapsed。
  void _toggleCollapse() {
    setState(() => _collapsed = !_collapsed);
    _config.isCollapsed = _collapsed;
    widget.configService.save(_config);
    final h = _collapsed
        ? (_usage?.weekly != null
            ? ConfigService.collapsedHeightWithWeekly
            : ConfigService.collapsedHeight)
        : ConfigService.expandedHeight;
    widget.window.setHeight(ConfigService.expandedWidth, h);
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
        // 主内容：下次触发 + 三行用量
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
          child: Column(children: [
            Align(
                alignment: Alignment.centerRight,
                child: Text(_nextTriggerText,
                    style: const TextStyle(
                        color: Color(0xFF666666), fontSize: 10))),
            const Divider(color: Color(0xFF444444), height: 6),
            if (_usage?.hour5 != null)
              UsageRow(label: l.t('token5hLabel'), info: _usage?.hour5, resetText: _resetText),
            if (_usage?.weekly != null)
              UsageRow(label: l.t('tokenWeekLabel'), info: _usage?.weekly, resetText: _resetText),
            UsageRow(label: l.t('mcpMonthLabel'), info: _usage?.mcp, resetText: _resetText),
            const Spacer(),
            // 底部栏：手动触发 + 置顶 + 设置（折叠态隐藏）
            if (!_collapsed)
              Row(children: [
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
          ]),
        ),
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
