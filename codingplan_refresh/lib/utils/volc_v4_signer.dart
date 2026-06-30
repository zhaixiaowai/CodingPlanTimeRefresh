import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 火山引擎 OpenAPI V4 签名工具（GET、无 body）。
///
/// 忠实翻译 `docs/main.js` 的 `signedGet`：把 AK/SK 签成可直接发出的 HTTP
/// header 集合。抽成纯函数便于单测、与 HTTP 调用解耦（provider 负责发请求 +
/// 解析，本函数只管签名）。
///
/// 调用方负责用 [volcXDate] 生成 `xDate`（[DateTime] 注入，便于测试固定时间），
/// 再连同 host/region/service/action/version 一起传入。

/// GET 无 body，payload 恒为空串的 sha256（固定常量，预计算避免每次签名重算）。
const _emptyPayloadHash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// 生成 X-Date 头值：UTC `yyyyMMddTHHmmssZ`（与 node `new Date().toISOString()`
/// 去掉 `-`/`:`/毫秒后等价）。[when] 会先 `.toUtc()`，调用方可传本地时间。
String volcXDate(DateTime when) {
  final u = when.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final y = u.year.toString();
  return '$y${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// 构造 V4 签名所需的 headers（小写键）：`host` / `x-date` / `x-content-sha256`
/// / `authorization`。返回值可直接作为 HTTP 请求头发出（HTTP 头大小写不敏感，
/// 服务端按小写名匹配 canonical headers）。
Map<String, String> buildVolcSignedHeaders({
  required String ak,
  required String sk,
  required String host,
  required String region,
  required String service,
  required String action,
  required String version,
  required String xDate,
}) {
  final ds = xDate.substring(0, 8); // yyyyMMdd

  // canonical query string：参数按 key 字母序，key/value 各自 encode。
  // Uri.encodeQueryComponent 对 Action/Version/GetCodingPlanUsage/2024-01-01 的
  // 结果与 JS encodeURIComponent 完全一致（无空格差异）。
  final params = {'Action': action, 'Version': version};
  final cq = (params.keys.toList()..sort())
      .map(
        (k) =>
            '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(params[k]!)}',
      )
      .join('&');

  final payloadHash = _emptyPayloadHash;

  // 进签名的 header（key 统一小写），按 key 排序构造 canonical headers /
  // signed headers。
  final headers = <String, String>{
    'host': host,
    'x-date': xDate,
    'x-content-sha256': payloadHash,
  };
  final sortedKeys = headers.keys.toList()..sort();
  final canonHeaders = sortedKeys.map((k) => '$k:${headers[k]}\n').join('');
  final signedHeaders = sortedKeys.join(';');

  final canonReq = [
    'GET',
    '/',
    cq,
    canonHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');
  final scope = '$ds/$region/$service/request';
  final sts = [
    'HMAC-SHA256',
    xDate,
    scope,
    sha256.convert(utf8.encode(canonReq)).toString(),
  ].join('\n');

  // 派生签名密钥链：sk → ds → region → service → 'request'。
  // 第一层 key 为 SK 的 utf8 字节；后续每层 key 为上一层 HMAC 的输出字节。
  List<int> hmacBytes(List<int> key, String msg) =>
      Hmac(sha256, key).convert(utf8.encode(msg)).bytes;
  final kDate = hmacBytes(utf8.encode(sk), ds);
  final kRegion = hmacBytes(kDate, region);
  final kService = hmacBytes(kRegion, service);
  final kSigning = hmacBytes(kService, 'request');
  final sig = Hmac(sha256, kSigning).convert(utf8.encode(sts)).toString();

  // Authorization：逗号后留一空格（与 main.js 模板字符串逐字一致）。
  final auth = 'HMAC-SHA256 '
      'Credential=$ak/$scope, '
      'SignedHeaders=$signedHeaders, '
      'Signature=$sig';

  return {
    'host': host,
    'x-date': xDate,
    'x-content-sha256': payloadHash,
    'authorization': auth,
  };
}
