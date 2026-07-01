import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';

/// WindowController 现不依赖焦点/透明度（失焦也 1.0），仅保留窗口尺寸/置顶等行为。
/// 失焦半透机制已移除（setOpacity 触发分层窗口致失焦画面合成滞后）。
void main() {
  test('WindowController 可实例化（焦点/透明度机制已移除）', () {
    expect(WindowController(), isNotNull);
  });
}
