import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_settings_window_opener.dart';

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
