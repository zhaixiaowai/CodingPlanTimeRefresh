import 'dart:ui' show Size;
import 'package:window_manager/window_manager.dart';

/// 窗口控制器：封装 `window_manager` 调用。
///
/// 注意：`window_manager` 包内部用到 `Size`（来自 `dart:ui`）但未 re-export，
/// 故本文件显式 `import 'dart:ui' show Size;`，否则引用本类的测试/构建会因
/// `Size` 未定义而编译失败。方法为普通实例方法，便于测试以子类 override 注入。
class WindowController {
  /// 初始化窗口：固定尺寸、居中、不可缩放、禁最大化、置顶。
  /// [maxExpandedHeight] 为窗口最大展开高度（= ConfigService.expandedHeight），
  /// 用作 maximumSize 上限，平移旧 MAUI `MaximumHeight = ExpandedHeight`。
  /// 「禁最大化」由 setResizable(false) + setMaximizable(false) 实现（双平台），
  /// 不引入 macos_window_utils。
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
    required double maxExpandedHeight,
  }) async {
    await windowManager.ensureInitialized();
    // 不能用 `const WindowOptions(...)`——size/minimumSize/maximumSize 依赖
    // 运行时入参 width/height，const 上下文会编译失败。这里走普通构造。
    await windowManager.waitUntilReadyToShow(WindowOptions(
      size: Size(width, height),
      minimumSize: Size(width, 120),
      maximumSize: Size(width, maxExpandedHeight),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    ), () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
      // 平移旧 MAUI `IsMaximizable=false`（禁最大化按钮，亦拦截标题栏双击最大化）。
      await windowManager.setMaximizable(false);
      await windowManager.setAlwaysOnTop(alwaysOnTop);
      await windowManager.setSize(Size(width, height));
    });
  }

  Future<void> setAlwaysOnTop(bool v) => windowManager.setAlwaysOnTop(v);

  /// 设置窗口尺寸。
  ///
  /// 注意：macOS 下 window_manager 的 setSize 设的是 frame 还是 content 不确定。
  /// 旧 MAUI 在 macOS 用 `setContentSize:` 并扣 28 标题栏（MacTitleBarHeight）；
  /// 若 window_manager 设的是 content 尺寸则需在此 -28，若设 frame 则等价。
  /// **待 Mac 实测确认**——当前 Windows 行为正常，保持直接 setSize。
  Future<void> setHeight(double width, double h) =>
      windowManager.setSize(Size(width, h));

  /// 更新窗口标题（用量百分比 + level）。
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  Future<void> center() => windowManager.center();
}
