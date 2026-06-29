import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/platform/settings_window_opener.dart';

/// 测试用 fake：记录 open 调用次数，暴露 simulateClosed 触发已注册回调。
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

void main() {
  test('FakeSettingsWindowOpener: open 计数 + onClosed 回调可触发', () async {
    final op = FakeSettingsWindowOpener();
    bool? received;
    op.onClosed((saved) => received = saved);
    await op.open();
    expect(op.openCalls, 1);
    op.simulateClosed(true);
    expect(received, isTrue);
    op.simulateClosed(false);
    expect(received, isFalse);
  });
}
