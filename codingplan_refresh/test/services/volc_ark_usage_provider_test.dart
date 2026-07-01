import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/services/volc_ark_usage_provider.dart';

/// 注入 [MockClient] + 固定 now（xDate 确定可断言），不发真实网络。
/// 成功用例的响应体取自 spec 2026-06-22 的真实示例（session/weekly/monthly 三档）。
void main() {
  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('volc_'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  // 固定 UTC 时钟 → xDate = 20260622T155136Z（签名确定性，便于排障）。
  DateTime fixedNow() => DateTime.utc(2026, 6, 22, 15, 51, 36);

  const okBody = '''
{"ResponseMetadata":{"RequestId":"x","Action":"GetCodingPlanUsage","Version":"2024-01-01","Service":"ark","Region":"cn-beijing"},
 "Result":{"Status":"Running","UpdateTimestamp":1782114696,"QuotaUsage":[
   {"Level":"session","Percent":2.4590175,"ResetTimestamp":1782130855},
   {"Level":"weekly","Percent":1.4308822,"ResetTimestamp":1782662400},
   {"Level":"monthly","Percent":16.025877866666665,"ResetTimestamp":1784303999}
 ]}}''';

  VolcArkUsageProvider providerWith(http.Client client) =>
      VolcArkUsageProvider('AK', 'SK', LogService(tmpDir),
          client: client, now: fixedNow);

  test('成功 → 三行 token5h/weekly/monthly，标题「火山方舟」，ResetTimestamp×1000', () async {
    Uri? captured;
    final client = MockClient((req) async {
      captured = req.url;
      return http.Response(okBody, 200);
    });
    final r = await providerWith(client).query();

    expect(r.errorMessage, isNull);
    expect(r.vendorTitle, '火山方舟');
    expect(r.items.map((i) => i.labelKey).toList(),
        ['token5h', 'tokenWeekly', 'tokenMonthly']);
    expect(r.items[0].percentage, closeTo(2.4590175, 1e-9));
    expect(r.items[0].resetAtMs, 1782130855 * 1000); // 秒 → 毫秒
    expect(r.items[1].labelKey, 'tokenWeekly');
    expect(r.items[1].resetAtMs, 1782662400 * 1000);
    expect(r.items[2].labelKey, 'tokenMonthly');
    expect(r.items[2].resetAtMs, 1784303999 * 1000);
    // 请求 URL/query 顺序与签名一致。
    expect(captured!.toString(),
        'https://ark.cn-beijing.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01');
  });

  test('成功响应携带 V4 签名头（authorization / x-date / host）', () async {
    Map<String, String>? capturedHeaders;
    final client = MockClient((req) async {
      capturedHeaders = req.headers;
      return http.Response(okBody, 200);
    });
    await providerWith(client).query();
    expect(capturedHeaders, isNotNull);
    expect(capturedHeaders!.containsKey('authorization'), isTrue);
    expect(capturedHeaders!['x-date'], '20260622T155136Z');
    expect(capturedHeaders!['authorization'], startsWith('HMAC-SHA256 '));
  });

  test('AK/SK 空 → volcAkSkNotConfigured（不发请求）', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('', 200);
    });
    final provider = VolcArkUsageProvider('', '', LogService(tmpDir),
        client: client, now: fixedNow);
    final r = await provider.query();
    expect(r.errorMessage, 'volcAkSkNotConfigured');
    expect(r.items, isEmpty);
    expect(called, isFalse);
  });

  test('ResponseMetadata.Error.Code=SignatureDoesNotMatch → volcAkSkInvalid', () async {
    final client = MockClient((_) async => http.Response(
        '{"ResponseMetadata":{"Error":{"Code":"SignatureDoesNotMatch","Message":"x"}}}',
        403));
    final r = await providerWith(client).query();
    expect(r.errorMessage, 'volcAkSkInvalid');
  });

  test('HTTP 403（无 Error 体）→ volcAkSkInvalid', () async {
    final client = MockClient(
        (_) async => http.Response('{"ResponseMetadata":{"RequestId":"x"}}', 403));
    final r = await providerWith(client).query();
    expect(r.errorMessage, 'volcAkSkInvalid');
  });

  test('空 QuotaUsage → queryFailed', () async {
    final client = MockClient((_) async => http.Response(
        '{"ResponseMetadata":{},"Result":{"QuotaUsage":[]}}', 200));
    final r = await providerWith(client).query();
    expect(r.errorMessage, 'queryFailed');
    expect(r.items, isEmpty);
  });

  test('InvalidAccessKey 错误码 → volcAkSkInvalid', () async {
    final client = MockClient((_) async => http.Response(
        '{"ResponseMetadata":{"Error":{"Code":"InvalidAccessKey"}}}', 200));
    final r = await providerWith(client).query();
    expect(r.errorMessage, 'volcAkSkInvalid');
  });

  test('非鉴权 NotFound 系错误码（ResourceNotFound）→ queryFailed 而非误判 AK/SK', () async {
    // 去掉过宽的 NotFound 后，资源/套餐未找到类业务错误不再误判为 volcAkSkInvalid。
    final client = MockClient((_) async => http.Response(
        '{"ResponseMetadata":{"Error":{"Code":"ResourceNotFound","Message":"plan not found"}}}',
        200));
    final r = await providerWith(client).query();
    expect(r.errorMessage, 'queryFailed');
  });

  test('AK/SK 含首尾空格 → trim 后正常查询（不被误判未配置）', () async {
    final client = MockClient((_) async => http.Response(okBody, 200));
    final provider = VolcArkUsageProvider('  AK  ', '\n SK \t', LogService(tmpDir),
        client: client, now: fixedNow);
    final r = await provider.query();
    expect(r.errorMessage, isNull);
    expect(r.items.length, 3);
    expect(r.items[0].labelKey, 'token5h');
  });

  test('注入的 client 不被 close：同一 client 可重复 query（_ownsClient=false）', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(okBody, 200);
    });
    final provider = VolcArkUsageProvider('AK', 'SK', LogService(tmpDir),
        client: client, now: fixedNow);
    await provider.query();
    await provider.query(); // 注入 client 不应被 finally close，第二次仍可用
    expect(calls, 2);
  });
}
