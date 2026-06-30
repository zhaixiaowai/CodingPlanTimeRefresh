import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// 不触达 window_manager 通道：override applyOpacity 记录最终透明度，
/// override isFocusedNow 固定返回失焦，直接调 onWindowFocus/onWindowBlur 验证路由。
/// 观测「最终透明度」而非「中间 focused 参数」。
class _FakeCtrl extends WindowController {
  double? lastOpacity;
  @override
  Future<void> applyOpacity(double opacity) async {
    lastOpacity = opacity;
  }

  @override
  Future<bool> isFocusedNow() async => false; // 测试默认失焦态
}

void main() {
  test('onWindowFocus → 透明度 1.0', () {
    final c = _FakeCtrl();
    c.onWindowFocus();
    expect(c.lastOpacity, WindowController.activeOpacity);
  });

  test('onWindowBlur → 透明度 0.95', () {
    final c = _FakeCtrl();
    c.onWindowBlur();
    expect(c.lastOpacity, WindowController.inactiveOpacity);
  });

  test('透明度常量：inactive 0.95 / active 1.0', () {
    expect(WindowController.inactiveOpacity, 0.95);
    expect(WindowController.activeOpacity, 1.0);
  });

  test('opacityFor 纯函数：focused true→1.0，false→0.95', () {
    expect(
      WindowController.opacityFor(focused: true),
      WindowController.activeOpacity,
    );
    expect(
      WindowController.opacityFor(focused: false),
      WindowController.inactiveOpacity,
    );
  });
}
