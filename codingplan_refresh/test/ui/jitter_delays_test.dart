import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/ui/main_page.dart';

/// jitterDelaysMs 纯函数单测：覆盖 n=0/1/多、范围约束、自定义参数、确定性
/// （seeded Random 可复现）。提取自 _scheduleTriggerAllWithJitter，使延迟逻辑
/// 可单测（修 V9：触发链原零覆盖，至少延迟计算现在有回归守护）。
void main() {
  group('jitterDelaysMs', () {
    test('count=0 → 空列表', () {
      expect(jitterDelaysMs(0, Random()), isEmpty);
    });

    test('count=1 → 仅 0（首个立即发，无 jitter）', () {
      expect(jitterDelaysMs(1, Random()), [0]);
    });

    test('count=3 → 首个 0，其余在 [1000, 5000) 区间', () {
      final delays = jitterDelaysMs(3, Random());
      expect(delays.length, 3);
      expect(delays[0], 0);
      expect(delays[1], greaterThanOrEqualTo(1000));
      expect(delays[1], lessThan(5000));
      expect(delays[2], greaterThanOrEqualTo(1000));
      expect(delays[2], lessThan(5000));
    });

    test('自定义 minMs/rangeMs 生效', () {
      final delays = jitterDelaysMs(2, Random(), minMs: 100, rangeMs: 50);
      expect(delays[0], 0);
      expect(delays[1], greaterThanOrEqualTo(100));
      expect(delays[1], lessThan(150));
    });

    test('seeded Random → 确定性输出（可复现，便于失败排查）', () {
      final r1 = Random(42);
      final r2 = Random(42);
      expect(jitterDelaysMs(5, r1), jitterDelaysMs(5, r2));
    });

    test('rangeMs=0 → 非首项恒为 minMs（边界：无随机区间）', () {
      final delays = jitterDelaysMs(3, Random(), minMs: 2000, rangeMs: 0);
      expect(delays, [0, 2000, 2000]);
    });
  });
}
