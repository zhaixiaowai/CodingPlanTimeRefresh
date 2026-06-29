import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/volc_ark_usage_provider.dart';

/// runner 按 args 返回不同 stdout（模拟 arkcli usage plan / plans get 两条命令）。
String _runnerReturn(List<String> args) {
  if (args.contains('plans')) {
    // plans get
    return '''
{
  "plans": [
    {"key": "coding-plan", "name": "Coding Plan", "scope": "personal", "tier": "pro", "status": "Running"}
  ]
}''';
  }
  // usage plan
  return '''
{
  "viewer": {"user_name": "x"},
  "items": [{"product": "coding-plan", "edition": "personal", "subscribed": true,
    "periods": [
      {"label": "session", "percent": 18.2, "reset_at": 1782478364000},
      {"label": "weekly", "percent": 49.7, "reset_at": 1782662400000},
      {"label": "monthly", "percent": 40.1, "reset_at": 1784303999000}
    ], "updated_at": 1782464268}]
}''';
}

void main() {
  test(
    'tier 来自 plans get 的 scope==edition(personal) → 火山方舟 Pro（覆盖 edition Personal）',
    () async {
      final provider = VolcArkUsageProvider(
        runner:
            ({required List<String> args, required Duration timeout}) async =>
                _runnerReturn(args),
      );
      final r = await provider.query();
      expect(r.errorMessage, isNull);
      // usage plan edition=personal → plans get 找 scope=personal 的 plan，tier=pro
      // 覆盖 edition 标题 → 「火山方舟 Pro」
      expect(r.vendorTitle, '火山方舟 Pro');
      expect(r.items.map((i) => i.labelKey).toList(), [
        'token5h',
        'tokenWeekly',
        'tokenMonthly',
      ]);
      expect(r.items[0].percentage, closeTo(18.2, 0.01));
    },
  );

  test('plans get 无 scope==edition 的 plan → fallback 用 edition', () async {
    final provider = VolcArkUsageProvider(
      runner: ({required List<String> args, required Duration timeout}) async {
        if (args.contains('plans')) {
          // 没有 scope=personal 的 plan（只有 team）
          return '{"plans":[{"key":"other","scope":"team","tier":"enterprise"}]}';
        }
        return _runnerReturn(args);
      },
    );
    final r = await provider.query();
    expect(r.vendorTitle, '火山方舟 Personal'); // edition=personal 兜底
  });

  test('plans get 失败/格式不符 → fallback edition', () async {
    final provider = VolcArkUsageProvider(
      runner: ({required List<String> args, required Duration timeout}) async {
        if (args.contains('plans')) {
          return 'not json';
        }
        return _runnerReturn(args);
      },
    );
    final r = await provider.query();
    expect(r.vendorTitle, '火山方舟 Personal');
  });

  test('arkcli 返回 ok:false → 显示 error.message', () async {
    const stdout =
        '{"ok":false,"error":{"type":"error","message":"please run arkcli auth login"}}';
    final provider = VolcArkUsageProvider(
      runner: ({required List<String> args, required Duration timeout}) async =>
          stdout,
    );
    final r = await provider.query();
    expect(r.items, isEmpty);
    expect(r.errorMessage, 'please run arkcli auth login');
  });

  test('arkcli 未安装（ProcessException）→ 提示未安装', () async {
    final provider = VolcArkUsageProvider(
      runner: ({required List<String> args, required Duration timeout}) async {
        throw ProcessException('arkcli', args, '命令不存在');
      },
    );
    final r = await provider.query();
    expect(r.errorMessage, contains('arkcli 未安装'));
  });

  test('超时 → 提示查询超时', () async {
    final provider = VolcArkUsageProvider(
      runner: ({required List<String> args, required Duration timeout}) async {
        throw TimeoutException('timed out', timeout);
      },
    );
    final r = await provider.query();
    expect(r.errorMessage, '查询超时');
  });

  test('refresh_token invalid → 提示重新登录（不重试，usage 仅调用一次）', () async {
    var usageCallCount = 0;
    final provider = VolcArkUsageProvider(
      runner: ({required List<String> args, required Duration timeout}) async {
        // usage plan 始终返回 refresh_token invalid（模拟登录凭证已过期）
        if (args.contains('usage')) {
          usageCallCount++;
          return '{"ok":false,"error":{"type":"error","message":"The request parameter refresh_token is invalid"}}';
        }
        return _runnerReturn(args); // plans get
      },
    );
    final r = await provider.query();
    expect(r.errorMessage, '登录凭证已过期，请重新执行 arkcli auth login');
    expect(r.items, isEmpty);
    // 不再自动重试：usage plan 只调用一次（旧版会延迟1s重试，callCount==2）
    expect(usageCallCount, 1);
  });
}
