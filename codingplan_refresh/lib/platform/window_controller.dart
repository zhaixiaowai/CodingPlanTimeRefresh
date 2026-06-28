import 'dart:io';
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
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(width, height),
        minimumSize: Size(width, 80),
        center: true,
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setResizable(false);
        // 平移旧 MAUI `IsMaximizable=false`（禁最大化按钮，亦拦截标题栏双击最大化）。
        await windowManager.setMaximizable(false);
        await windowManager.setAlwaysOnTop(alwaysOnTop);
        await windowManager.setSize(Size(width, height));
      },
    );
  }

  Future<void> setAlwaysOnTop(bool v) => windowManager.setAlwaysOnTop(v);

  /// 设置窗口尺寸。
  ///
  /// **Windows 标题栏+边框补偿**：`window_manager.setSize` 走 `SetWindowPos` 设的是
  /// 窗口**外框**尺寸（含标题栏+边框），但传入的 h 是客户区**内容高**（Flutter 渲染
  /// 的 Scaffold.body）。若直接 setSize(330, 内容高)，客户区 = 内容高 - 标题栏(~32)
  /// - 边框(~8) ≈ 内容高-40，内容被裁、出现滚动条。故 Windows 上用 AdjustWindowRectEx
  /// 按「内容高=客户区」算出对应外框高再 setSize（DPI 安全，非硬编码 40）。
  ///
  /// macOS：window_manager 的 setSize 设 frame 还是 content 待实测（旧 MAUI 用
  /// setContentSize 扣 28）。当前保持直接 setSize，待 Mac 实测后按需补偿。
  Future<void> setHeight(double width, double h) async {
    final frame = await _frameRectForClient(width, h);
    await windowManager.setSize(Size(width, frame.height));
  }

  /// 缩回 mini（自适应高度，保留当前位置）。
  Future<void> shrinkToContent(double contentHeight) async {
    final frame = await _frameRectForClient(330, contentHeight);
    await windowManager.setSize(Size(330, frame.height));
  }

  /// 按「客户区尺寸=传入的 w/h」反推窗口外框尺寸（含标题栏+边框补偿）。
  ///
  /// 零依赖方案（不调 win32 AdjustWindowRectEx，避免 API 版本差异）：用
  /// `windowManager.getSize()`（外框逻辑像素）与 `platformDispatcher.views.first`
  /// 的物理视图尺寸/dpr（客户区渲染面逻辑像素）反推差值 = 标题栏+边框补偿。
  /// 差值按宽/高分别缓存（窗口 style 不变，标题栏+边框固定）。首次调用时
  /// 测量并缓存；macOS setSize 设 frame 还是 content 待实测，暂用同补偿。
  Size? _cachedFrameOffset;

  Future<Size> _frameRectForClient(double clientW, double clientH) async {
    final offset = await _frameOffset();
    return Size(clientW + offset.width, clientH + offset.height);
  }

  Future<Size> _frameOffset() async {
    // 不缓存：每次重新测量（窗口 style 不变，但首帧测量可能因 setSize 未同步而偏小，
    // 不缓存可让后续测量自校正）。测到异常（负值/过大）用缓存或退化值。
    try {
      final frame = await windowManager.getSize(); // 外框逻辑像素
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final client = view.physicalSize / view.devicePixelRatio; // 客户区逻辑像素
      final dx = frame.width - client.width;
      final dy = frame.height - client.height;
      // dx/dy 应 ≥0（标题栏+边框）。若负值（同步异常），用上次缓存或退化。
      if (dx < 0 || dy < 0) {
        return _cachedFrameOffset ?? const Size(16, 40);
      }
      _cachedFrameOffset = Size(dx, dy);
      return _cachedFrameOffset!;
    } catch (_) {
      return _cachedFrameOffset ?? const Size(16, 40);
    }
  }

  /// 放大到目标尺寸，若超出屏幕工作区则平移窗口留在屏内。
  ///
  /// 算法：取当前位置 + 目标尺寸，若右/下边超出屏幕宽/高，则把 x/y 内移到
  /// `(screen - w/h)`（clamp 到 0..screen 防 w/h 超屏时越界）。先平移再 setSize，
  /// 避免先放大再平移期间短暂溢出闪现。
  /// 放大到目标**客户区**尺寸，若超出屏幕工作区则平移窗口留在屏内。
  /// 内部按客户区算外框（含标题栏+边框补偿）后 setSize，与 setHeight 一致。
  Future<void> enlarge({required double w, required double h}) async {
    final frame = await _frameRectForClient(w, h);
    final pos = await windowManager.getPosition();
    final screen = _screenSize();
    double x = pos.dx;
    double y = pos.dy;
    if (x + frame.width > screen.width) {
      x = (screen.width - frame.width).clamp(0.0, screen.width);
    }
    if (y + frame.height > screen.height) {
      y = (screen.height - frame.height).clamp(0.0, screen.height);
    }
    await windowManager.setPosition(Offset(x, y));
    await windowManager.setSize(Size(frame.width, frame.height));
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
