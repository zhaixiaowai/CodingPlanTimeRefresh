import 'dart:ui' show Size;
import 'package:window_manager/window_manager.dart';

/// 窗口控制器：封装 `window_manager` 调用。
///
/// 注意：`window_manager` 包内部用到 `Size`（来自 `dart:ui`）但未 re-export，
/// 故本文件显式 `import 'dart:ui' show Size;`，否则引用本类的测试/构建会因
/// `Size` 未定义而编译失败。方法为普通实例方法，便于测试以子类 override 注入。
class WindowController {
  /// 初始化窗口：固定尺寸、居中、不可缩放、置顶。
  /// 「禁最大化」由 setResizable(false) + setMaximumSize 实现（双平台），不引入 macos_window_utils。
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
  }) async {
    await windowManager.ensureInitialized();
    // 不能用 `const WindowOptions(...)`——size/minimumSize/maximumSize 依赖
    // 运行时入参 width/height，const 上下文会编译失败。这里走普通构造。
    await windowManager.waitUntilReadyToShow(WindowOptions(
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
