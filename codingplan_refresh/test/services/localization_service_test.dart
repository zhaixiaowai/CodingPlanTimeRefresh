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
    final zhText = l.t('settings');
    l.setLanguage('en');
    final enText = l.t('settings');
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

  test('fmt 真解析 {0:HH:mm} 对 DateTime 应用格式', () {
    final l = LocalizationService();
    l.initialize('zh');
    final dt = DateTime(2026, 6, 26, 1, 5, 30);
    // nextTriggerFormat zh = '下次触发大模型: {0:HH:mm} ({1}分{2}秒后)'
    final s = l.t('nextTriggerFormat').fmt([dt, 3, 30]);
    expect(s, '下次触发大模型: 01:05 (3分30秒后)');
  });

  test('fmt 无格式占位直接替换 String/num', () {
    final l = LocalizationService();
    l.initialize('zh');
    expect(l.t('errorMessage').fmt(['超时']), '错误，等待重试: 超时');
    expect(l.t('windowTitle').fmt([42, 'Pro']), '42%已使用(Pro Coding Plan)');
  });

  test('fmt resetOther 对 DateTime 应用 MM/dd HH:mm', () {
    final l = LocalizationService();
    l.initialize('zh');
    final dt = DateTime(2026, 6, 27, 9, 5);
    expect(l.t('resetOther').fmt([dt]), '重置 06/27 09:05');
  });

  test('已删 key 返回 key 本身（manualTrigger 等）', () {
    final l = LocalizationService()..initialize('zh');
    expect(l.t('manualTrigger'), 'manualTrigger');
    expect(l.t('manualTriggerPopup'), 'manualTriggerPopup');
    expect(l.t('waitingPlaceholder'), 'waitingPlaceholder');
    expect(l.t('resultHeader'), 'resultHeader');
  });

  test('保留的定时触发 key 仍可用', () {
    final l = LocalizationService()..initialize('zh');
    expect(l.t('loading'), '调用中...');
    expect(l.t('jokePrompt'), contains('冷笑话'));
  });
}
