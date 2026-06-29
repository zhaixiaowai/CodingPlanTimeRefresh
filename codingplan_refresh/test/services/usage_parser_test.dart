import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/usage_parser.dart';

/// `parseBigmodelUsage` 解析 BigModel 配额响应 → `UsageResult`：
/// vendorTitle/items/labelKey/percentage；缺 data → errorMessage。
void main() {
  // 构造一份覆盖三类限制（token5h / tokenWeekly / mcpMonthly）的样本，
  // 与真实接口结构一致：data.level 决定标题后缀，limits[] 内每条带
  // type/unit/number/percentage/nextResetTime。
  const body = r'''{
    "success": true,
    "data": {
      "level": "vip",
      "limits": [
        {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 34, "nextResetTime": 1700000000000},
        {"type": "TOKENS_LIMIT", "unit": 2, "number": 7, "percentage": 56, "nextResetTime": 1700000000001},
        {"type": "TIME_LIMIT", "percentage": 78, "nextResetTime": 1700000000002}
      ]
    }
  }''';

  test('解析成功：vendorTitle 含 level 首字母大写，items 三项归类正确', () {
    final r = parseBigmodelUsage(body);
    expect(r.errorMessage, isNull);
    expect(r.vendorTitle, '智谱 Vip');
    expect(r.items.length, 3);

    expect(r.items[0].labelKey, 'token5h');
    expect(r.items[0].percentage, 34);
    expect(r.items[0].resetAtMs, 1700000000000);

    expect(r.items[1].labelKey, 'tokenWeekly');
    expect(r.items[1].percentage, 56);

    expect(r.items[2].labelKey, 'mcpMonthly');
    expect(r.items[2].percentage, 78);
  });

  test('缺 data → errorMessage，items 为空', () {
    final r = parseBigmodelUsage('{"msg":"x"}');
    expect(r.errorMessage, 'queryFailed');
    expect(r.items, isEmpty);
    expect(r.vendorTitle, '智谱');
  });

  test('data.limits 非列表 → errorMessage', () {
    final r = parseBigmodelUsage('{"data":{"level":"vip","limits":{}}}');
    expect(r.errorMessage, 'queryFailed');
    expect(r.items, isEmpty);
  });

  test('limits 为空列表 → 无可用项 → errorMessage', () {
    final r = parseBigmodelUsage('{"data":{"level":"vip","limits":[]}}');
    expect(r.errorMessage, 'queryFailed');
    expect(r.items, isEmpty);
  });

  test('level 缺失时 vendorTitle 仅默认「智谱」', () {
    const b = r'''{"data":{"limits":[
      {"type":"TIME_LIMIT","percentage":10}
    ]}}''';
    final r = parseBigmodelUsage(b);
    expect(r.errorMessage, isNull);
    expect(r.vendorTitle, '智谱');
    expect(r.items.single.labelKey, 'mcpMonthly');
  });

  test('坏 JSON → errorMessage（不抛异常）', () {
    final r = parseBigmodelUsage('{坏');
    expect(r.errorMessage, 'queryFailed');
    expect(r.items, isEmpty);
  });
}
