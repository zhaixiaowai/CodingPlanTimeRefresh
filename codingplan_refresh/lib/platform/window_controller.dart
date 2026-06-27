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
  ///
  /// 不设 maximumSize——它会把窗口钳在 mini 上限（318），导致 enlarge(420×520)
  /// 被 maximumSize 钳制而放大失败（Critical）。放大/缩回都靠 enlarge/shrinkToContent
  /// 直接 setSize 设定，不受 maximumSize 约束。仅保留 minimumSize=Size(width,80)
  /// 防内容为空时窗口过矮。禁拖拽/最大化由 setResizable(false)+setMaximizable(false)
  /// 实现（双平台，maximumSize 在此冗余且有害）。
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
  }) async {
    await windowManager.ensureInitialized();
    // 不能用 `const WindowOptions(...)`——size/minimumSize 依赖运行时入参
    // width/height，const 上下文会编译失败。这里走普通构造。
    await windowManager.waitUntilReadyToShow(WindowOptions(
      size: Size(width, height),
      minimumSize: Size(width, 80),
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

  /// 取主屏逻辑尺寸（物理像素 / DPR）。
  ///
  /// 用 PlatformDispatcher.displays.first（Display 是显示器，size 为物理像素），
  /// 而非 views.first（窗口视图，其尺寸跟随窗口当前大小，不是屏幕）。enlarge 的
  /// clamp 依此判断窗口放大后是否超出屏幕工作区。多屏时 displays.first = 主屏，
  /// 若窗口不在主屏则定位可能不准——本工具单屏够用，待多屏再补。
  /// displays 在首帧前可能为空，此时 fallback 到 views.first 仅防崩溃。
  Size _screenSize() {
    final displays = WidgetsBinding.instance.platformDispatcher.displays;
    if (displays.isEmpty) {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      return view.physicalSize / view.devicePixelRatio;
    }
    final d = displays.first;
    return d.size / d.devicePixelRatio;
  }

  /// 更新窗口标题（用量百分比 + level）。
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  Future<void> center() => windowManager.center();
}
