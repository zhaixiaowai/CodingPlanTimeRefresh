import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/volc_ark_usage_provider.dart';

void main() {
  test('成功解析 periods → token5h/weekly/monthly', () async {
    const stdout = '''
{
  "viewer": {"user_name": "x"},
  "items": [{"product": "coding-plan", "edition": "personal", "subscribed": true,
    "periods": [
      {"label": "session", "percent": 18.2, "reset_at": 1782478364000},
      {"label": "weekly", "percent": 49.7, "reset_at": 1782662400000},
      {"label": "monthly", "percent": 40.1, "reset_at": 1784303999000}
    ], "updated_at": 1782464268}]
}''';
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async => stdout);
    final r = await provider.query();
    expect(r.errorMessage, isNull);
    expect(r.vendorTitle, '火山方舟 Personal');
    expect(r.items.map((i) => i.labelKey).toList(), ['token5h', 'tokenWeekly', 'tokenMonthly']);
    expect(r.items[0].percentage, closeTo(18.2, 0.01));
  });

  test('arkcli 返回 ok:false → 显示 error.message', () async {
    const stdout = '{"ok":false,"error":{"type":"error","message":"please run arkcli auth login"}}';
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async => stdout);
    final r = await provider.query();
    expect(r.items, isEmpty);
    expect(r.errorMessage, 'please run arkcli auth login');
  });

  test('arkcli 未安装（ProcessException）→ 提示未安装', () async {
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async {
      throw ProcessException('arkcli', args, '命令不存在');
    });
    final r = await provider.query();
    expect(r.errorMessage, contains('arkcli 未安装'));
  });

  test('超时 → 提示查询超时', () async {
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async {
      throw TimeoutException('timed out', timeout);
    });
    final r = await provider.query();
    expect(r.errorMessage, '查询超时');
  });
}
