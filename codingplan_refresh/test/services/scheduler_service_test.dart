import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/scheduler_service.dart';

void main() {
  test('命中 01:00 且 lastKey 不同 → trigger', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '');
    expect(r.trigger, isTrue);
    expect(r.key, '2026-06-25 01:00');
  });

  test('同一 key 已触发过 → 不再触发', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '2026-06-25 01:00');
    expect(r.trigger, isFalse);
  });

  test('非触发时段 → 不触发', () {
    final now = DateTime(2026, 6, 25, 2, 30);
    final r = SchedulerService.checkTrigger(now, '');
    expect(r.trigger, isFalse);
  });

  test('nextTrigger：当前 00:30 → 当天 01:00', () {
    final now = DateTime(2026, 6, 25, 0, 30);
    final next = SchedulerService.nextTrigger(now, '')!;
    expect(next, DateTime(2026, 6, 25, 1, 0));
  });

  test('nextTrigger：当前 23:00 → 次日 01:00', () {
    final now = DateTime(2026, 6, 25, 23, 0);
    final next = SchedulerService.nextTrigger(now, '')!;
    expect(next, DateTime(2026, 6, 26, 1, 0));
  });
}
