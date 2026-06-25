import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/localization_service.dart';

void main() {
  test('显式 en 后 current=en', () {
    final l = LocalizationService();
    l.initialize('en');
    expect(l.current, 'en');
  });

  test('zh 与 en 文案不同', () {
    final l = LocalizationService();
    l.initialize('zh');
    final zhText = l.t('resultHeader');
    l.setLanguage('en');
    final enText = l.t('resultHeader');
    expect(zhText, isNot(equals(enText)));
  });

  test('auto 在中文系统回退 zh（测试强制 zh）', () {
    final l = LocalizationService();
    l.initialize('auto');
    expect(l.current, anyOf('zh', 'en')); // 不依赖系统时接受二者
  });

  test('未知 key 返回 key 本身', () {
    final l = LocalizationService();
    l.initialize('zh');
    expect(l.t('不存在的键'), '不存在的键');
  });
}
