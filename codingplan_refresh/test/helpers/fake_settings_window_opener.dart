import 'package:codingplan_refresh/platform/settings_window_opener.dart';

/// 测试用 fake：记录 open 调用次数，暴露 simulateClosed 触发已注册回调。
///
/// 共享 fake：被 settings_window_opener_test 与 main_page_test 同时引用，
/// 避免在两处重复定义同一种 fake。
class FakeSettingsWindowOpener implements SettingsWindowOpener {
  int openCalls = 0;
  void Function(bool saved)? _cb;

  @override
  Future<void> open() async {
    openCalls++;
  }

  @override
  void onClosed(void Function(bool saved) cb) {
    _cb = cb;
  }

  /// 模拟设置窗口关闭（测试驱动主窗口 reload/移遮罩逻辑）。
  void simulateClosed(bool saved) => _cb?.call(saved);
}
