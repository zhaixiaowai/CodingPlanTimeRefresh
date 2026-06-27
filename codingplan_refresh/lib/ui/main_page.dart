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
import '../services/volc_ark_usage_provider.dart';
import '../platform/window_controller.dart';
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
/// 本任务（T6）只填充 [_usages]（用量查询结果），[_results] 字段保留结构供 T7
/// LLM 触发回填 text/header/isBusy/isRetrying 使用。
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
  }

  @override
  void dispose() {
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
              onSelected: (v) {
                // T7/T8 接入：'config' → 打开配置放大态；'trigger' → 打开手动触发放大态。
                // 本任务留空回调。
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
