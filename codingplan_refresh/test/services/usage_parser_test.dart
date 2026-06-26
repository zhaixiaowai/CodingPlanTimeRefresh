import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/usage_parser.dart';

/// T1 桩化阶段：`parseBigmodelUsage` 返回 null（旧 `UsageInfo`/`LimitInfo`
/// 已移除，归类逻辑由 T2 重写为 `UsageResult`/`UsageItem`）。本文件仅保留
/// 「桩返回 null」断言；T2 会重写为多 provider 用量解析的完整用例。
void main() {
  test('T1 桩：parseBigmodelUsage 返回 null', () {
    expect(parseBigmodelUsage('{"data":{}}'), isNull);
  });

  test('坏 JSON 返回 null', () {
    expect(parseBigmodelUsage('{坏'), isNull);
  });
}
