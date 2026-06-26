import 'package:window_manager/window_manager.dart';

class WindowController {
  /// 初始化窗口：固定尺寸、居中、不可缩放、置顶。
  /// 「禁最大化」由 setResizable(false) + setMaximumSize 实现（双平台），不引入 macos_window_utils。
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
  }) async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(const WindowOptions(
      size: Size(width, height),
      minimumSize: Size(width, 120),
      maximumSize: Size(width, 350),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    ), () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
      await windowManager.setAlwaysOnTop(alwaysOnTop);
      await windowManager.setSize(Size(width, height));
    });
  }

  Future<void> setAlwaysOnTop(bool v) => windowManager.setAlwaysOnTop(v);

  Future<void> setHeight(double width, double h) =>
      windowManager.setSize(Size(width, h));

  /// 更新窗口标题（用量百分比 + level）。
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  Future<void> center() => windowManager.center();
}
