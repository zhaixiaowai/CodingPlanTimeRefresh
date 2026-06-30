import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/services/usage_provider.dart';
import 'package:codingplan_refresh/utils/volc_v4_signer.dart';

/// 火山方舟用量：用 AK/SK + 火山引擎 OpenAPI V4 签名，直接 GET `GetCodingPlanUsage`
/// 查询（取代旧 arkcli 子进程方案）。AK/SK 为用户在设置面板填写的长效凭证，
/// 无需登录态、无需本地工具。15s 超时。
///
/// 接口常量与 `docs/main.js` 一致：host=`ark.cn-beijing.volcengineapi.com`、
/// region=`cn-beijing`、service=`ark`、action=`GetCodingPlanUsage`、version=`2024-01-01`。
///
/// [client] / [now] 为可注入的测试 seam：生产分别用默认 `http.Client()` 与
/// `DateTime.now`；测试注入 `http.testing.MockClient` 与固定时钟，使签名 xDate
/// 确定可断言。
class VolcArkUsageProvider implements UsageProvider {
  static const _host = 'ark.cn-beijing.volcengineapi.com';
  static const _region = 'cn-beijing';
  static const _service = 'ark';
  static const _action = 'GetCodingPlanUsage';
  static const _version = '2024-01-01';

  /// 鉴权/签名类错误码关键词（大小写不敏感子串匹配）。**不含 `NotFound`**——它太
  /// 宽，会把火山资源/套餐未找到类业务错误（ResourceNotFound/PlanNotFound 等）
  /// 误判为 AK/SK 无效。对比 `docs/main.js` save-creds 的集合去掉了 NotFound。
  static final _authErrorRe = RegExp(
    r'Signature|InvalidAccessKey|AccessDenied|Authentication',
    caseSensitive: false,
  );

  final String accessKey;
  final String secretKey;
  final LogService log;
  final http.Client client;
  final DateTime Function() _now;

  /// 是否由本实例创建（true → query 结束负责 close，避免每分钟轮询泄漏底层
  /// HttpClient 连接池）。测试注入的 client 由测试方管理生命周期，不 close。
  final bool _ownsClient;

  VolcArkUsageProvider(
    this.accessKey,
    this.secretKey,
    this.log, {
    http.Client? client,
    DateTime Function()? now,
  }) : client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now;

  @override
  Future<UsageResult> query() async {
    // 去首尾空白后再判空与签名：避免用户复制 AK/SK 时带入空格/换行导致签名失败、
    // 被误判为「AK/SK 无效」。
    final ak = accessKey.trim();
    final sk = secretKey.trim();
    if (ak.isEmpty || sk.isEmpty) {
      return const UsageResult('火山方舟', [], 'volcAkSkNotConfigured');
    }

    // query 顺序须与签名 canonical query 一致（按 key 字母序：Action < Version），
    // 故字面量拼接 Action 在前，不交给 Uri 重排。
    final url = 'https://$_host/?Action=$_action&Version=$_version';
    final headers = buildVolcSignedHeaders(
      ak: ak,
      sk: sk,
      host: _host,
      region: _region,
      service: _service,
      action: _action,
      version: _version,
      xDate: volcXDate(_now()),
    );

    try {
      log.append(
        '========== [Usage Request] ==========\nGET $url\n'
        'X-Date: ${headers['x-date']}\nAuthorization: ***',
      );
      final response = await client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      log.append(
        '========== [Usage Response] ${response.statusCode} ==========',
      );
      log.append(response.body);
      return _parse(response.statusCode, response.body);
    } on TimeoutException {
      return const UsageResult('火山方舟', [], 'queryTimeout');
    } catch (e) {
      log.append('[VolcArk Usage Error] $e');
      return const UsageResult('火山方舟', [], 'queryFailed');
    } finally {
      // 自创建的 client 用完即关，避免每分钟轮询泄漏底层 HttpClient 连接池/句柄。
      // 注入的 client（测试用）由测试方管理，不在此关闭。
      if (_ownsClient) client.close();
    }
  }

  /// 解析 `GetCodingPlanUsage` 响应 → [UsageResult]。
  ///
  /// 鉴权失败：HTTP 401/403，或 `ResponseMetadata.Error.Code` 命中签名/鉴权类
  /// （Signature|InvalidAccessKey|AccessDenied|Authentication，大小写不敏感）
  /// → `volcAkSkInvalid`。判定集合参考 `docs/main.js` `save-creds`，去掉过宽的
  /// `NotFound`（避免资源/套餐未找到类业务错误被误判为 AK/SK 无效）。
  /// 成功：`Result.QuotaUsage[]` 三档（session/weekly/monthly）映射
  /// token5h/tokenWeekly/tokenMonthly；`ResetTimestamp` 秒级 ×1000→ms。
  /// 空 / 无数据 → `queryFailed`。
  UsageResult _parse(int statusCode, String body) {
    try {
      final doc = jsonDecode(body) as Map<String, dynamic>;

      // 先看响应级错误（鉴权/签名类）。
      final errMeta = doc['ResponseMetadata']?['Error'];
      if (errMeta is Map) {
        final code = (errMeta['Code'] as String?) ?? '';
        if (_isAuthError(code)) {
          // 签名失败除 AK/SK 错外，也可能是本机系统时间偏差过大（X-Date 不在窗口），
          // 记一条排障 hint，避免用户反复重填凭证。
          if (code.toLowerCase().contains('signature')) {
            log.append(
              '[VolcArk] 签名失败($code)：请检查 AK/SK 是否正确，以及本机系统时间'
              '是否准确（偏差过大会导致签名失效）。',
            );
          }
          return const UsageResult('火山方舟', [], 'volcAkSkInvalid');
        }
        // 其它业务错误：无用量数据可显示；记下 Code/Message 便于排障（UI 兜底 queryFailed）。
        log.append(
          '[VolcArk] 业务错误 code=$code message=${errMeta['Message'] ?? ''}',
        );
        return const UsageResult('火山方舟', [], 'queryFailed');
      }
      if (statusCode == 401 || statusCode == 403) {
        return const UsageResult('火山方舟', [], 'volcAkSkInvalid');
      }

      final result = doc['Result'];
      if (result is! Map<String, dynamic>) {
        return const UsageResult('火山方舟', [], 'queryFailed');
      }
      final qu = result['QuotaUsage'];
      if (qu is! List || qu.isEmpty) {
        return const UsageResult('火山方舟', [], 'queryFailed');
      }

      const levelToKey = {
        'session': 'token5h',
        'weekly': 'tokenWeekly',
        'monthly': 'tokenMonthly',
      };
      final items = <UsageItem>[];
      for (final q in qu) {
        if (q is! Map<String, dynamic>) continue;
        final level = q['Level'] as String?;
        final percent = q['Percent'];
        final key = level == null ? null : levelToKey[level];
        if (key == null || percent is! num) continue;
        final resetTs = q['ResetTimestamp'];
        final resetMs = resetTs is num ? resetTs.toInt() * 1000 : null;
        items.add(UsageItem(key, percent.toDouble(), resetMs));
      }
      if (items.isEmpty) {
        return const UsageResult('火山方舟', [], 'queryFailed');
      }
      return UsageResult('火山方舟', items, null);
    } catch (_) {
      return const UsageResult('火山方舟', [], 'queryFailed');
    }
  }

  /// Code 命中签名/鉴权类（大小写不敏感子串）→ 视为 AK/SK 无效或无权限。
  /// 去掉了过宽的 NotFound（会误伤 ResourceNotFound 等业务错误）。
  bool _isAuthError(String code) => _authErrorRe.hasMatch(code);
}
