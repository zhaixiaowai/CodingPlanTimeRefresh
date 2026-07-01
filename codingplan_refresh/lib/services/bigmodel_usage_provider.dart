import 'package:http/http.dart' as http;
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/services/usage_parser.dart';
import 'package:codingplan_refresh/services/usage_provider.dart';

/// 智谱 BigModel 用量 provider：GET quota/limit，调用 [parseBigmodelUsage] 解析为
/// [UsageResult]（vendorTitle 默认「智谱」）。失败/无数据统一返回
/// `UsageResult('智谱', [], 'queryFailed')`，与旧 MAUI `LLMService
/// .QueryBigmodelUsagePercentageAsync` 失败语义对齐。
class BigmodelUsageProvider implements UsageProvider {
  final String apiKey;
  final LogService log;
  BigmodelUsageProvider(this.apiKey, this.log);

  static const _url = 'https://open.bigmodel.cn/api/monitor/usage/quota/limit';

  @override
  Future<UsageResult> query() async {
    if (apiKey.trim().isEmpty) {
      return const UsageResult('智谱', [], 'queryFailed');
    }
    try {
      log.append(
        '========== [Usage Request] ==========\nGET $_url\nAuthorization: ***',
      );
      final response = await http
          .get(Uri.parse(_url), headers: {'Authorization': apiKey})
          .timeout(const Duration(seconds: 120));
      log.append(
        '========== [Usage Response] ${response.statusCode} ==========',
      );
      log.append(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const UsageResult('智谱', [], 'queryFailed');
      }
      return parseBigmodelUsage(response.body);
    } catch (_) {
      return const UsageResult('智谱', [], 'queryFailed');
    }
  }
}
