import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 设置窗口打开器抽象：隔离多窗口实现（生产用 desktop_multi_window，测试用 fake）。
///
/// 主窗口点「设置」调 [open] 创建独立设置窗口并进入模态；设置窗口关闭时经 [onClosed]
/// 回传「是否有保存」布尔，主窗口据此决定是否 reload 配置。设置窗口本身不持有
/// AppConfig 引用，唯一数据媒介是 config.dat 文件（见设计 spec §3/§5）。
abstract class SettingsWindowOpener {
  /// 创建并显示设置窗口（独立 OS 窗口）。主窗口在调用后自行进入模态遮罩态。
  Future<void> open();

  /// 注册关闭回调。[saved]=true 表示用户在设置窗口点了保存（已写盘）；
  /// false 表示取消/异常关闭。回调在主窗口 engine 触发。
  void onClosed(void Function(bool saved) cb);
}

/// 跨窗口通信通道名：主窗口与设置窗口共用此 [WindowMethodChannel]。
///
/// desktop_multi_window 0.3.0 的 [WindowMethodChannel] 默认
/// [ChannelMode.bidirectional]，正好配主/设置一对 engine（最多 2 个 engine 注册，
/// 仅这对可互调）。通道是 **实例**（非静态），主/设置窗口各 `const channel = ...`。
const settingsChannel = WindowMethodChannel('settings_channel');

/// 关闭事件的方法名：设置窗口 invokeMethod('onClosed', {'saved': bool})，
/// 主窗口 setMethodCallHandler 收到后取出 saved 调注册的回调。
const settingsMethodOnClosed = 'onClosed';

/// 设置窗口 engine 的 arguments 标识：主窗口创建子窗口时传 'settings'，
/// main.dart 据此分发到设置窗口 runApp。
const settingsWindowArguments = 'settings';

/// 生产实现：用 desktop_multi_window 创建独立设置窗口，关闭经 [settingsChannel]
/// 回传主窗口，并以窗口销毁事件兜底（spec §6 destroyed 兜底）。
///
/// 实现要点（基于 desktop_multi_window 0.3.0 真实 API 核对，pub cache 源码确认）：
/// - `WindowMethodChannel` 是 **实例类**，`invokeMethod`/`setMethodCallHandler` 为
///   实例方法（非静态）。
/// - `WindowController.create(WindowConfiguration(arguments:'settings', hiddenAtLaunch:true))`
///   返回子窗口控制器；`controller.show()` 显示。
/// - 子窗口的尺寸/居中/关闭由 **设置窗口 engine 内的 window_manager** 自管（见
///   main.dart 的 `_runSettingsWindow`，用 `waitUntilReadyToShow` 设 420×560/居中/
///   无系统标题栏，onSave/onCancel 调 `notifyClosedAndClose`）。
///   控制器本身无 setSize/center 方法，故主窗口不直接设子窗口大小。
/// - **兜底**：包无「按窗口 id 的 onClose 回调」，仅有全局 [onWindowsChanged]
///   Stream（窗口列表创建/销毁时触发）与 [WindowController.getAll]（同步查全部
///   活跃窗口）。故订阅该 Stream，事件后查 [WindowController.getAll]，若被跟踪的
///   设置窗口 id 已不在列表 → 判定 destroyed，按 saved=false 触发回调（崩溃/异常
///   关闭未发 IPC 时由此兜底，避免主窗口永久卡模态遮罩）。正常关闭时 IPC 先到，
///   `_closed` 标志防止重复触发。
class DesktopMultiWindowSettingsOpener implements SettingsWindowOpener {
  void Function(bool saved)? _cb;
  String? _trackedWindowId;
  bool _closed = false;
  StreamSubscription<void>? _windowChangeSub;

  @override
  Future<void> open() async {
    // 主窗口侧：注册方法处理器，收设置窗口回传的 onClosed。
    await settingsChannel.setMethodCallHandler((call) async {
      if (call.method == settingsMethodOnClosed) {
        final args = call.arguments;
        final saved = args is Map && args['saved'] == true;
        _notify(saved);
      }
      return null;
    });

    // 创建设置窗口（hiddenAtLaunch 先隐藏，由子窗口 engine 内 window_manager
    // 设好尺寸/标题栏后再 show）。
    final controller = await WindowController.create(
      const WindowConfiguration(
        arguments: settingsWindowArguments,
        hiddenAtLaunch: true,
      ),
    );
    _trackedWindowId = controller.windowId;
    await controller.show();

    // destroyed 兜底：订阅窗口列表变更，事件后查设置窗口是否仍存活。
    _windowChangeSub = onWindowsChanged.listen((_) async {
      if (_closed || _trackedWindowId == null) return;
      final alive = await WindowController.getAll();
      final stillExists =
          alive.any((c) => c.windowId == _trackedWindowId);
      if (!stillExists) {
        // 设置窗口已销毁但未发 IPC（异常关闭/崩溃）→ 按 saved=false 兜底。
        _notify(false);
      }
    });
  }

  @override
  void onClosed(void Function(bool saved) cb) {
    _cb = cb;
  }

  /// 统一触发关闭回调，[closed] 标志保证只触发一次（IPC 与 destroyed 兜底互斥）。
  void _notify(bool saved) {
    if (_closed) return;
    _closed = true;
    _windowChangeSub?.cancel();
    _windowChangeSub = null;
    _cb?.call(saved);
  }
}
