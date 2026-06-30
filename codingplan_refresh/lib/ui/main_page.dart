import 'dart:async';
import 'package:flutter/material.dart';
// 置顶图标对 push_pin/offline_pin_off 在 Flutter 内置 Icons 类缺失（offline_pin_off
// 不存在），故引 material_symbols_icons 的 Symbols 类提供这两个不同图标互切。
import 'package:material_symbols_icons/material_symbols_icons.dart';
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
import 'widgets/usage_frame.dart';

/// 主窗口：mini 态（顶部 4 按钮 + 各 provider 用量框）与设置态（ConfigPanel）原地切换。
///
/// 设置按钮把主窗口内容从 mini 切到 ConfigPanel 视图（窗口放大到 420×560），
/// 保存→[_applyConfig] 应用新配置 + 切回 mini，取消/X→切回 mini。单窗口机制
/// （window_manager 正式版），无多窗口依赖。
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

  // 当前视图：'mini'（用量框）| 'settings'（ConfigPanel 原地切换）。
  String _view = 'mini';
  // 设置视图客户区尺寸：宽度固定 420；高度初始 560，随后按 ConfigPanel 实际内容高
  // 收缩（_onSettingsHeight），消除固定值的裁剪/空白。
  static const double _settingsW = 420;
  static const double _settingsH = 560;
  double _lastSettingsH = 0; // 设置视图上次 setHeight 高，>2px 阈值防抖

  // 高度自适应测量键：挂在 mini 的整个内容（topBar + 各 UsageFrame + padding）
  // 外层，量其完整渲染高作为窗口内容高。
  final GlobalKey _contentKey = GlobalKey();

  // 下次触发时刻文本（全局触发，所有 provider 共享同一值）。每个 UsageFrame legend 后
  // 显示「<标题> : 下次触发在 HH:mm」。由 _onTriggerTick（6s）定期刷新 setState。
  String _nextTriggerText = '';

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    for (final p in _config.providers) {
      _results[p.id] = ResultState();
    }
    _usageTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _queryAllUsage(),
    );
    _queryAllUsage();
    _updateNextTrigger();
    _triggerTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _onTriggerTick(),
    );
    // 启动不立即 _resizeToContent：首帧时用量数据未到（loading 占位偏小），若此时量高
    // 缩窗会偏小。保持 setup 的启动高 318，等用量数据到达后（_queryAllUsage 末尾
    // PostFrame）量真实内容高再缩。
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

  /// 并行查询所有 provider 用量：每个 provider 起独立 async 查询（智谱 HTTP +
  /// 火山方舟 arkcli 子进程同时进行），先返回的先 setState 显示——总耗时 ≈ 最慢
  /// 的那个，而非串行相加（旧 for+await 是 A 完才 B，两个都几秒时翻倍）。
  /// 全是 async IO（http.get / Process.start），不阻塞主 isolate，UI 不卡。
  /// 全部完成后统一更新窗口标题 + 排高度自适应。
  Future<void> _queryAllUsage() async {
    final futures = <Future<void>>[];
    for (final p in _config.providers) {
      final provider = _providerFor(p);
      if (provider == null) {
        // 未知厂商：同步置错误结果，无需 async。
        _usages[p.id] = const UsageResult(
          '未知厂商',
          [],
          'unknownVendorUnsupported',
        );
        continue;
      }
      // 立即启动（IIFE）并行查询；每个完成即 setState 显示，先到先显。
      futures.add(() async {
        final result = await provider.query();
        if (!mounted) return;
        setState(() => _usages[p.id] = result);
      }());
    }
    await Future.wait(futures);
    if (!mounted) return;
    // 更新窗口标题：每 provider 一组「5h%/周%」，多 provider 用空格连。
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
      // 显示名优先用用户输入的 ProviderConfig.name，但保留 vendorTitle 的套餐部分
      // （「智谱 Pro」的「Pro」）——避免只替换名称时丢套餐。详见 usageDisplayTitle。
      final vendor = usageDisplayTitle(p.name, u.vendorTitle);
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
    // 每次轮询刷新下次触发文本（倒计时秒级变化，6s 粒度足够）。先刷新再判触发，
    // 触发命中后的下一次 tick 文本即跳到「下个时段」。
    _updateNextTrigger();
    final r = SchedulerService.checkTrigger(
      DateTime.now(),
      _globalTriggerKey(),
      _config.triggerHours,
    );
    if (!r.trigger) return;
    _setGlobalTriggerKey(r.key);
    widget.configService.save(_config);
    for (final p in _config.providers) {
      _callLlmWithRetry(p.id);
    }
  }

  /// 算下次全局触发时刻 → 拼成「下次触发在 HH:mm」（无下次则空，不显示）。
  /// 触发是全局时刻（01/07/13/19），所有 provider 共享同一值，故放每个用量框 legend 后。
  void _updateNextTrigger() {
    final now = DateTime.now();
    final next = SchedulerService.nextTrigger(
      now,
      _globalTriggerKey(),
      _config.triggerHours,
    );
    if (next == null) {
      if (_nextTriggerText.isNotEmpty) {
        _nextTriggerText = '';
        if (mounted) setState(() {});
      }
      return;
    }
    // 用本地化键 nextTriggerFormat（zh「下次触发大模型: HH:mm」/en「Next trigger: HH:mm」）：
    // 仅显示时刻，不显示倒计时（曾带「(X分Y秒后)」过长）。
    final text = widget.l10n.t('nextTriggerFormat').fmt([next]);
    if (text != _nextTriggerText) {
      _nextTriggerText = text;
      if (mounted) setState(() {});
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
      orElse: () =>
          ProviderConfig(id: '', name: '', apiUrl: '', apiKey: '', model: ''),
    );
    if (p.id.isEmpty) return false;
    final rs = _results[providerId];
    if (rs == null) return false;
    if (rs.isBusy) return false;
    rs.isBusy = true;
    if (mounted) setState(() {});
    try {
      final model = p.model.isEmpty ? 'glm-5.1' : p.model;
      final prompt =
          '${widget.l10n.t('jokePrompt')}\nseed=${DateTime.now().millisecondsSinceEpoch % 10000}';
      // ResultPanel 已删除：流式 chunk 不再显示，onChunk 仅消费避免 backpressure，
      // 不写 rs.text、不节流 setState（曾每 50ms 全量重建却无 reader，纯浪费）。
      await widget.llm.askStream(
        apiUrl: p.apiUrl,
        apiKey: p.apiKey,
        model: model,
        question: prompt,
        onChunk: (_) {},
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

  /// 应用（设置窗口保存后 reload 来的）新配置：对齐运行时态、语言、triggerHours，
  /// 持久化，setState 重建。
  ///
  /// _results/_usages 按 id 索引——用户在设置窗口增删/重排 providers 后，新增 provider
  /// 无对应条目会显示空、删除 provider 的残留条目会泄漏。这里按「以新 providers 为准」
  /// 对齐：新增 id 加空 ResultState、删除 id 清其 _results/_usages/lastTriggerKeys。
  void _applyConfig(AppConfig next) {
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
    final langChanged = _config.language != next.language;
    setState(() {
      _config = next;
      if (langChanged) widget.l10n.initialize(next.language ?? 'auto');
    });
    widget.configService.save(_config);
    // triggerHours 改动后立即刷新「下次触发」文本，避免滞后到下个 6s tick。
    _updateNextTrigger();
    // 新增/改动的 provider 立即查一次用量，避免空白框等到下个 60s tick。
    _queryAllUsage();
  }

  /// 当前语言下的 mini 窗口宽度（统一英文版宽度 expandedWidth=260）。
  double _miniWidth() => ConfigService.widthForLanguage(widget.l10n.current);

  /// 测量内容高度 → setHeight（高度自适应，仅超阈值才调避免抖动）。
  ///
  /// mini 态把 topBar + 各 UsageFrame 全放进 Column，用 _contentKey 挂在外层
  /// Padding，量其 RenderBox 完整渲染高（含 topBar + 全部框 + padding），一次量全，
  /// 避免分段相加漏算顶部。
  void _resizeToContent() {
    if (!mounted) return;
    final contentBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null) return;
    final h = contentBox.size.height;
    if ((h - _lastContentHeight).abs() > 2) {
      _lastContentHeight = h;
      widget.window.setHeight(_miniWidth(), h);
      // setHeight 可能改变窗口宽度（如设置 420→mini 234），宽度变化致 Text 换行重排、
      // 高度随之变。排下一帧复测按新宽度量准（收敛：宽固定后高稳定，阈值<2 停，不无限）。
      WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
    }
  }

  /// Unix 毫秒 → 本地化重置文本（今天用 HH:mm，其它日期用 MM/dd HH:mm）。
  String _resetText(int? ms) {
    if (ms == null || ms < 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    // 复合格式（resetToday/resetOther）的占位符 {0:HH:mm} / {0:MM/dd HH:mm} 由
    // FmtString.fmt 内部按 DateTime 参数渲染，此处无需单独构造 DateFormat。
    return widget.l10n.t(isToday ? 'resetToday' : 'resetOther').fmt([dt]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: _view == 'settings' ? _buildSettings() : _buildMini(),
    );
  }

  /// 顶部栏：右侧 4 按钮（置顶图标互切 / 设置 / 最小化 / 关闭）。左侧留白兼拖动区。
  /// 整个 mini body 在外层已包 GestureDetector(onPanStart: startDragging)，按钮作为
  /// 子节点 tap 优先命中，留白/用量框区域可拖动窗口。
  ///
  /// 置顶：两个不同图标互切（offline_pin_off 未置顶 / push_pin 已置顶），**都灰色**
  /// 不变色（用户决策：不用高亮蓝区分，避免视觉噪音）。两个图标来自 material_symbols_icons
  /// 的 Symbols 类（Flutter 内置 Icons 无 offline_pin_off）。
  Widget _buildTopBar() {
    final l = widget.l10n;
    final pinned = _config.isAlwaysOnTop;
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 置顶：未置顶用 offline_pin_off，已置顶用 push_pin。颜色恒灰。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            tooltip: l.t('pinLabel'),
            icon: Icon(
              pinned ? Symbols.push_pin : Symbols.offline_pin_off,
              color: const Color(0xFFAAAAAA),
              size: 14,
            ),
            onPressed: () {
              setState(() => _config.isAlwaysOnTop = !pinned);
              widget.window.setAlwaysOnTop(_config.isAlwaysOnTop);
              widget.configService.save(_config);
            },
          ),
          // 设置：原地切到 ConfigPanel 视图（窗口放大到 420×560）。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            tooltip: l.t('settings'),
            icon: const Icon(
              Icons.settings,
              color: Color(0xFFAAAAAA),
              size: 14,
            ),
            onPressed: _openSettings,
          ),
          // 最小化。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            icon: const Icon(
              Icons.horizontal_rule,
              color: Color(0xFFAAAAAA),
              size: 14,
            ),
            onPressed: () => widget.window.minimize(),
          ),
          // 关闭 = 退出应用。
          IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
            icon: const Icon(Icons.close, color: Color(0xFFAAAAAA), size: 14),
            onPressed: () => widget.window.close(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// mini 态：顶部栏（齿轮+置顶）+ 每 provider 一个 UsageFrame。
  /// 不用 ScrollView——窗口高度自适应（setHeight=内容高+补偿），内容永远≤窗口，
  /// 无需滚动。直接 Column，量其完整渲染高作为窗口内容高，避免 ScrollView 的
  /// viewport 约束干扰测量（曾导致量到的 contentH 偏小、却仍出滚动条）。
  Widget _buildMini() {
    final l = widget.l10n;
    return GestureDetector(
      // 整个 mini 界面可拖动窗口；按钮作为子节点 tap 优先命中不影响拖动。
      onPanStart: (_) => widget.window.startDragging(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
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
                    .map(
                      (p) => UsageFrame(
                        result:
                            _usages[p.id] ?? const UsageResult('', [], null),
                        l10n: l,
                        resetText: _resetText,
                        displayName: p.name,
                        // _usages[p.id]==null：从未查到过（首次查询中）→ loading 占位；
                        // 非 null（有旧数据或错误）→ 显示旧内容，刷新查询无感。
                        isLoading: _usages[p.id] == null,
                        // 下次触发提示（全局共享同一值），显示在每个用量框 legend 后。
                        nextTriggerText: _nextTriggerText,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开设置视图：先放大窗口到设置尺寸，再 setState 切视图（避免设置内容在
  /// mini 尺寸窗口渲染一帧被裁）。
  Future<void> _openSettings() async {
    await widget.window.enlarge(_settingsW, _settingsH);
    if (!mounted) return;
    setState(() => _view = 'settings');
  }

  /// 关闭设置视图：切回 mini，重置高度阈值后 PostFrame 重测缩回。
  void _closeSettings() {
    setState(() => _view = 'mini');
    // 重置阈值：切设置期间 _lastContentHeight 未更新（仍为切前 mini 高），切回 mini
    // 后 mini 内容高与之一致 → 差值<2 不触发 setHeight，窗口不会缩回。置 0 强制重设。
    _lastContentHeight = 0;
    _lastSettingsH = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
  }

  /// 设置视图高度自适应：按 ConfigPanel 实际内容高收缩/放大窗口（消除固定 560 的
  /// 裁剪或空白）。>2px 阈值防抖。
  void _onSettingsHeight(double contentH) {
    if (!mounted) return;
    final target = contentH + 22 + 4; // 标题栏 22 + 底部余量
    if ((target - _lastSettingsH).abs() > 2) {
      _lastSettingsH = target;
      widget.window.enlarge(_settingsW, target);
    }
  }

  /// 设置视图：顶部 X 关闭栏 + ConfigPanel。保存→[_applyConfig]+切回；取消/X→切回。
  Widget _buildSettings() {
    return GestureDetector(
      // 设置视图也可拖动（无系统标题栏）。
      onPanStart: (_) => widget.window.startDragging(),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 极简标题栏：仅 X 关闭（=取消切回 mini）。
          SizedBox(
            height: 22,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minHeight: 22,
                    minWidth: 22,
                  ),
                  tooltip: widget.l10n.t('cancel'),
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFFAAAAAA),
                    size: 14,
                  ),
                  onPressed: _closeSettings,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: ConfigPanel(
              initial: _config,
              l10n: widget.l10n,
              onSave: (next, _) {
                _applyConfig(next);
                _closeSettings();
              },
              onCancel: _closeSettings,
              onHeightChanged: _onSettingsHeight,
            ),
          ),
        ],
      ),
    );
  }
}
