import 'dart:ui' show Offset, Size;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:window_manager/window_manager.dart';

/// 窗口控制器：封装 `window_manager` 调用。
///
/// 注意：`window_manager` 包内部用到 `Size`（来自 `dart:ui`）但未 re-export，
/// 故本文件显式 `import 'dart:ui' show Offset, Size;`，否则引用本类的测试/构建会因
/// `Size`/`Offset` 未定义而编译失败。方法为普通实例方法，便于测试以子类 override 注入。
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

  /// 放大到目标尺寸，若超出屏幕工作区则平移窗口留在屏内。
  ///
  /// 算法：取当前位置 + 目标尺寸，若右/下边超出屏幕宽/高，则把 x/y 内移到
  /// `(screen - w/h)`（clamp 到 0..screen 防 w/h 超屏时越界）。先平移再 setSize，
  /// 避免先放大再平移期间短暂溢出闪现。
  Future<void> enlarge({required double w, required double h}) async {
    final pos = await windowManager.getPosition();
    final screen = _screenSize();
    double x = pos.dx;
    double y = pos.dy;
    if (x + w > screen.width) {
      x = (screen.width - w).clamp(0.0, screen.width);
    }
    if (y + h > screen.height) {
      y = (screen.height - h).clamp(0.0, screen.height);
    }
    await windowManager.setPosition(Offset(x, y));
    await windowManager.setSize(Size(w, h));
  }

  /// 缩回 mini（自适应高度，保留当前位置）。
  ///
  /// 放大态关闭后调用：宽度回到 expandedWidth（330），高度由调用方按内容测量传入。
  /// 不改 position——放大时若曾平移到屏内，缩回后仍停在该处（用户视区内，符合预期）。
  Future<void> shrinkToContent(double contentHeight) async {
    await windowManager.setSize(Size(330, contentHeight));
  }

  /// 取主屏逻辑尺寸（physicalSize / devicePixelRatio）。
  ///
  /// window_manager 0.5.x 无直接取屏 API（仅 setBounds/getWindowFrame）；
  /// 用 PlatformDispatcher.views.first 的物理像素 / DPR 得逻辑像素，与
  /// window_manager 内部坐标一致。多屏时 views.first = 主屏，已满足本工具需求。
  /// 同步方法（platformDispatcher.views 在 FrameData 同步可取）。
  Size _screenSize() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  /// 更新窗口标题（用量百分比 + level）。
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  Future<void> center() => windowManager.center();
}
