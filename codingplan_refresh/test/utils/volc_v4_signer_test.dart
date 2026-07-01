import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:codingplan_refresh/utils/volc_v4_signer.dart';

/// V4 签名正确性的最终验证靠端到端（真实 AK/SK 调通 GetCodingPlanUsage）。
/// 这里覆盖：xDate 格式、签名确定性、Authorization 三段格式、payloadHash
/// 为空串 sha256（已知常量）、signature 为 64 位 hex。
void main() {
  const ak = 'AKTEST';
  const sk = 'SKTEST';
  const host = 'ark.cn-beijing.volcengineapi.com';
  const region = 'cn-beijing';
  const service = 'ark';
  const action = 'GetCodingPlanUsage';
  const version = '2024-01-01';
  const xDate = '20260622T155136Z';

  Map<String, String> build() => buildVolcSignedHeaders(
    ak: ak,
    sk: sk,
    host: host,
    region: region,
    service: service,
    action: action,
    version: version,
    xDate: xDate,
  );

  test('volcXDate: UTC → yyyyMMddTHHmmssZ', () {
    // toUtc 后按位格式化；调用方传本地时间也安全。
    final dt = DateTime.utc(2026, 6, 22, 15, 51, 36);
    expect(volcXDate(dt), '20260622T155136Z');
  });

  test('返回四键 headers（host/x-date/x-content-sha256/authorization）', () {
    final h = build();
    expect(h.keys.toSet(), {'host', 'x-date', 'x-content-sha256', 'authorization'});
    expect(h['host'], host);
    expect(h['x-date'], xDate);
  });

  test('x-content-sha256 = 空串的 sha256 hex（已知常量）', () {
    final emptySha = sha256.convert(utf8.encode('')).toString();
    expect(build()['x-content-sha256'], emptySha);
    expect(emptySha, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('Authorization: 含 Credential/Scope、SignedHeaders 三键、Signature 64hex', () {
    final auth = build()['authorization']!;
    expect(auth, startsWith('HMAC-SHA256 '));
    expect(auth, contains('Credential=$ak/20260622/$region/$service/request'));
    expect(auth, contains('SignedHeaders=host;x-content-sha256;x-date'));
    // Signature= 末段为 64 位小写 hex（sha256 输出）。
    final m = RegExp(r'Signature=([0-9a-f]{64})$').firstMatch(auth);
    expect(m, isNotNull, reason: 'Signature 段应为 64 位 hex: $auth');
  });

  test('确定性：同输入两次签名完全相同', () {
    expect(build(), build());
  });

  test('输入变化 → 签名变化（SK 改动应改 signature）', () {
    final base = build()['authorization']!;
    final other = buildVolcSignedHeaders(
      ak: ak,
      sk: 'OTHER_SK',
      host: host,
      region: region,
      service: service,
      action: action,
      version: version,
      xDate: xDate,
    )['authorization']!;
    expect(other, isNot(equals(base)));
  });
}
