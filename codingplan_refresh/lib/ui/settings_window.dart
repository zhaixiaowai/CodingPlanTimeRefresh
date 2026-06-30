import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../services/config_service.dart';
import '../services/localization_service.dart';
import '../platform/window_controller.dart' show WindowController;
import 'widgets/config_panel.dart';

/// 设置窗口（独立 OS 窗口内的 widget tree）。
///
/// 自绘极简标题栏（仅 X 关闭=取消）+ 复用 [ConfigPanel]。数据自包含：
/// [configService] 读 config.dat 作为初始编辑态，保存时写盘。不接收主窗口的
/// AppConfig 引用——唯一与主窗口的交互是 [onSave]/[onCancel] 回调（由上层 opener
/// 经 IPC 通知主窗口）。
///
/// [windowController] 用于设置窗口自身隐藏标题栏后的拖动（onPanStart → startDragging）。
class SettingsApp extends StatelessWidget {
  final ConfigService configService;
  final LocalizationService l10n;
  final WindowController windowController;
  final void Function(AppConfig next) onSave;
  final VoidCallback onCancel;

  const SettingsApp({
    super.key,
    required this.configService,
    required this.l10n,
    required this.windowController,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    // load 在 build 期同步读（ConfigService.load 是同步的）；config.dat 已由主窗口
    // 启动时迁移/创建，设置窗口打开时必然存在。
    final initial = configService.load();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF2D2D30),
      ),
      home: Scaffold(
        body: Column(
          children: [
            // 仅标题栏作为拖动区（像标准无标题栏窗口的 caption 区）。
            // 不能包整个 body：ConfigPanel 内的 ReorderableListView 长按-拖动也是
            // pan 手势，若外层 onPanStart 抢先胜出会触发 startDragging 移动整个窗口，
            // 导致 provider 排序失效。
            _buildTitleBar(),
            Expanded(
              child: ConfigPanel(
                initial: initial,
                l10n: l10n,
                onSave: (next, _) {
                  configService.save(next);
                  onSave(next);
                },
                onCancel: onCancel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 极简标题栏：拖动区 + 仅一个 X 关闭按钮（=取消不保存）。
  ///
  /// 拖动手势仅在此处生效（onPanStart → startDragging 移动窗口），X 按钮自带
  /// GestureDetector 会优先命中其命中区，不触发拖动。
  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowController.startDragging(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
              icon: const Icon(Icons.close, color: Color(0xFFAAAAAA), size: 14),
              onPressed: onCancel,
              tooltip: l10n.t('cancel'),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
