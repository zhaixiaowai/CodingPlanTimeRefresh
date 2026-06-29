import '../models/app_config.dart';

class SchedulerService {
  /// 默认触发时刻（整点）。复用 AppConfig.defaultTriggerHours 单一来源，避免默认值
  /// 散落分叉。AppConfig.triggerHours 缺失时用此作 fallback。
  static const List<int> defaultTriggerHours = AppConfig.defaultTriggerHours;

  static String _key(DateTime d, int h, int m) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// 判断 now 是否命中触发时段且本轮未触发。hours 为触发整点列表（0-23），
  /// 缺省用 [defaultTriggerHours]。空 hours 永不触发。
  static ({bool trigger, String key}) checkTrigger(
    DateTime now,
    String lastKey, [
    List<int>? hours,
  ]) {
    final times = hours ?? defaultTriggerHours;
    for (final h in times) {
      if (now.hour == h && now.minute == 0) {
        final key = _key(now, h, 0);
        if (key != lastKey) return (trigger: true, key: key);
      }
    }
    return (trigger: false, key: lastKey);
  }

  /// 计算下一个触发时刻。空 hours → null。缺省用 [defaultTriggerHours]。
  static DateTime? nextTrigger(
    DateTime now,
    String lastKey, [
    List<int>? hours,
  ]) {
    final times = hours ?? defaultTriggerHours;
    if (times.isEmpty) return null;
    DateTime? next;
    for (final h in times) {
      var target = DateTime(now.year, now.month, now.day, h, 0);
      final key = _key(now, h, 0);
      if (target.isAfter(now) || key != lastKey) {
        if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
        if (next == null || target.isBefore(next)) next = target;
      }
    }
    return next;
  }
}
