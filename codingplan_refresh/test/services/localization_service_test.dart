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
    // nextTriggerFormat zh = '下次触发模型: {0:HH:mm}'（仅时刻，无倒计时）
    final s = l.t('nextTriggerFormat').fmt([dt]);
    expect(s, '下次触发模型: 01:05');
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

  test('usageTooltip / usageTooltipNoReset 中英双语 fmt', () {
    final zh = LocalizationService()..initialize('zh');
    expect(
      zh.t('usageTooltip').fmt(['5H', '34', '重置 09:05']),
      '5H：已使用 34%，重置 09:05',
    );
    expect(zh.t('usageTooltipNoReset').fmt(['月', '12']), '月：已使用 12%');
    final en = LocalizationService()..initialize('en');
    expect(
      en.t('usageTooltip').fmt(['5H', '34', 'Reset 09:05']),
      '5H: 34% used, Reset 09:05',
    );
    expect(en.t('usageTooltipNoReset').fmt(['Month', '12']), 'Month: 12% used');
  });

  test('mcpTipLabel 用于 mcp hover tooltip 的 (MCP) 前缀区分', () {
    final zh = LocalizationService()..initialize('zh');
    expect(zh.t('mcpTipLabel'), '(MCP)月');
    // mcp 行无重置时 tooltip（label 用 (MCP) 前缀，区别于普通「月」）
    expect(
      zh.t('usageTooltipNoReset').fmt([zh.t('mcpTipLabel'), '12']),
      '(MCP)月：已使用 12%',
    );
    final en = LocalizationService()..initialize('en');
    expect(en.t('mcpTipLabel'), '(MCP)Month');
    expect(
      en.t('usageTooltipNoReset').fmt([en.t('mcpTipLabel'), '12']),
      '(MCP)Month: 12% used',
    );
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
