class SchedulerService {
  static const List<(int, int)> triggerTimes = [(1, 0), (7, 0), (13, 0), (19, 0)];

  static String _key(DateTime d, int h, int m) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// 判断 now 是否命中触发时段且本轮未触发。
  static ({bool trigger, String key}) checkTrigger(
      DateTime now, String lastKey) {
    for (final (h, m) in triggerTimes) {
      if (now.hour == h && now.minute == m) {
        final key = _key(now, h, m);
        if (key != lastKey) return (trigger: true, key: key);
      }
    }
    return (trigger: false, key: lastKey);
  }

  /// 计算下一个触发时刻（考虑当天该时段是否已被 lastKey 标记完成）。
  static DateTime? nextTrigger(DateTime now, String lastKey) {
    DateTime? next;
    for (final (h, m) in triggerTimes) {
      var target = DateTime(now.year, now.month, now.day, h, m);
      final key = _key(now, h, m);
      if (target.isAfter(now) || key != lastKey) {
        if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
        if (next == null || target.isBefore(next)) next = target;
      }
    }
    return next;
  }
}
