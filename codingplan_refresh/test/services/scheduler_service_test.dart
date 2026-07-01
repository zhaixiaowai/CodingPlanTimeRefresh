import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/scheduler_service.dart';

void main() {
  const def = SchedulerService.defaultTriggerHours;

  test('命中 01:00 且 lastKey 不同 → trigger', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '', def);
    expect(r.trigger, isTrue);
    expect(r.key, '2026-06-25 01:00');
  });

  test('同一 key 已触发过 → 不再触发', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '2026-06-25 01:00', def);
    expect(r.trigger, isFalse);
  });

  test('非触发时段 → 不触发', () {
    final now = DateTime(2026, 6, 25, 2, 30);
    final r = SchedulerService.checkTrigger(now, '', def);
    expect(r.trigger, isFalse);
  });

  test('nextTrigger：当前 00:30 → 当天 01:00', () {
    final now = DateTime(2026, 6, 25, 0, 30);
    final next = SchedulerService.nextTrigger(now, '', def)!;
    expect(next, DateTime(2026, 6, 25, 1, 0));
  });

  test('nextTrigger：当前 23:00 → 次日 01:00', () {
    final now = DateTime(2026, 6, 25, 23, 0);
    final next = SchedulerService.nextTrigger(now, '', def)!;
    expect(next, DateTime(2026, 6, 26, 1, 0));
  });

  test('自定义 hours=[2,14] → 02:00 命中', () {
    final now = DateTime(2026, 6, 25, 2, 0);
    final r = SchedulerService.checkTrigger(now, '', const [2, 14]);
    expect(r.trigger, isTrue);
    expect(r.key, '2026-06-25 02:00');
  });

  test('自定义 hours=[2,14]：当前 01:00 → 当天 02:00', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final next = SchedulerService.nextTrigger(now, '', const [2, 14])!;
    expect(next, DateTime(2026, 6, 25, 2, 0));
  });

  test('空 hours → 永不触发，nextTrigger 为 null', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    expect(SchedulerService.checkTrigger(now, '', const []).trigger, isFalse);
    expect(SchedulerService.nextTrigger(now, '', const []), isNull);
  });

  test('hours 缺省 → 用 defaultTriggerHours（1:00 命中）', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    expect(SchedulerService.checkTrigger(now, '').trigger, isTrue);
  });
}
