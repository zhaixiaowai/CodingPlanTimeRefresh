import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// 不触达 window_manager 通道：override applyOpacity 记录最终透明度，
/// override isFocusedNow 固定返回失焦，直接调 onWindowFocus/onWindowBlur 验证路由。
/// 观测「最终透明度」而非「中间 focused 参数」，真正验证 _forcedActive 覆盖逻辑。
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

  test('onWindowBlur → 透明度 0.9', () {
    final c = _FakeCtrl();
    c.onWindowBlur();
    expect(c.lastOpacity, WindowController.inactiveOpacity);
  });

  test('setOpacityForcedActive(true) → 强制全显，即使 onWindowBlur 后仍 1.0', () async {
    final c = _FakeCtrl();
    await c.setOpacityForcedActive(true);
    expect(c.lastOpacity, WindowController.activeOpacity);
    c.onWindowBlur(); // 失焦但放大态强制全显
    expect(c.lastOpacity, WindowController.activeOpacity);
  });

  test('setOpacityForcedActive(false) 后 onWindowBlur → 恢复 0.9', () async {
    final c = _FakeCtrl();
    await c.setOpacityForcedActive(true);
    await c.setOpacityForcedActive(false); // isFocusedNow=false → 恢复按失焦
    expect(c.lastOpacity, WindowController.inactiveOpacity);
    c.onWindowBlur();
    expect(c.lastOpacity, WindowController.inactiveOpacity);
  });

  test('透明度常量：inactive 0.9 / active 1.0', () {
    expect(WindowController.inactiveOpacity, 0.9);
    expect(WindowController.activeOpacity, 1.0);
  });

  test('opacityFor 纯函数：focused 优先，forcedActive 覆盖失焦', () {
    expect(
      WindowController.opacityFor(focused: true, forcedActive: false),
      WindowController.activeOpacity,
    );
    expect(
      WindowController.opacityFor(focused: false, forcedActive: false),
      WindowController.inactiveOpacity,
    );
    expect(
      WindowController.opacityFor(focused: false, forcedActive: true),
      WindowController.activeOpacity,
    );
    expect(
      WindowController.opacityFor(focused: true, forcedActive: true),
      WindowController.activeOpacity,
    );
  });
}
