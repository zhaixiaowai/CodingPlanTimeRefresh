import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import '../services/localization_service.dart';
import '../services/log_service.dart';
import '../platform/window_controller.dart';

/// 主界面桩：T1 阶段仅保留类结构与构造签名，让全项目编译通过。
///
/// 背景：旧 `MainPage` 大量引用单组字段（`apiUrl/apiKey/model/lastAutoTriggerKey/
/// isCollapsed`）与旧类型（`UsageInfo`/`LimitInfo`），随 T1 数据模型重构已移除。
/// 真正的 mini 主窗口 + per-provider 用量刷新由 T6（主窗口重构）/ T7（LLM 触发
/// per-provider）重写；本桩仅：
/// - 保留 `MainPage`/构造签名（`config`/`configService`/`llm`/`log`/`l10n`/`window`）
///   供 `main.dart` 与现有 widget 测试引用，避免下游编译断档；
/// - 启动两个空跑定时器（保持「6s 触发 / 60s 用量」骨架结构存在，T6 替换实现）；
/// - `build` 返回最小占位。
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
  // 桩阶段保留 config 引用，T6/T7 重写时使用。
  // ignore: unused_field
  late AppConfig _config;
  Timer? _triggerTimer;
  Timer? _usageTimer;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    // 桩：保留定时器骨架（空跑），T6/T7 接入真实触发与用量刷新。
    _triggerTimer =
        Timer.periodic(const Duration(seconds: 6), (_) => _onTriggerTick());
    _usageTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _queryUsage());
  }

  @override
  void dispose() {
    _triggerTimer?.cancel();
    _usageTimer?.cancel();
    super.dispose();
  }

  /// 桩：6s 触发占位（T7 重写为 per-provider 调度）。
  void _onTriggerTick() {}

  /// 桩：60s 用量查询占位（T2/T6 重写为 per-provider 用量刷新）。
  Future<void> _queryUsage() async {}

  @override
  Widget build(BuildContext context) {
    // 桩：占位 UI，T6 重写为 mini 主窗口（用量框 + ☰ 菜单）。
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: const SizedBox.shrink(),
    );
  }
}
