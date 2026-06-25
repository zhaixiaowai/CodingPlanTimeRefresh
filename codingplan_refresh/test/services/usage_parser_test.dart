import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/usage_parser.dart';

void main() {
  test('归类 TIME_LIMIT→mcp, TOKENS_LIMIT(unit3,number5)→hour5, 其余→weekly', () {
    const body = '''
{
  "data": {
    "level": "vip",
    "limits": [
      {"type":"TIME_LIMIT","percentage":12,"nextResetTime":1717200000000},
      {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":34,"nextResetTime":1717300000000},
      {"type":"TOKENS_LIMIT","unit":1,"number":7,"percentage":56}
    ]
  }
}''';
    final u = parseBigmodelUsage(body)!;
    expect(u.level, 'vip');
    expect(u.mcp!.percentage, 12);
    expect(u.mcp!.nextResetTimeMs, 1717200000000);
    expect(u.hour5!.percentage, 34);
    expect(u.weekly!.percentage, 56);
    expect(u.weekly!.nextResetTimeMs, isNull);
  });

  test('缺 data 返回 null', () {
    expect(parseBigmodelUsage('{"msg":"x"}'), isNull);
  });

  test('坏 JSON 返回 null', () {
    expect(parseBigmodelUsage('{坏'), isNull);
  });

  test('level 缺省为 null', () {
    const body = '{"data":{"limits":[]}}';
    expect(parseBigmodelUsage(body)!.level, isNull);
  });
}
