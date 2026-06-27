import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/utils/sse.dart';

/// 类型化 LLM 异常：携带本地化键 [l10nKey] 与格式参数 [args]，供调用方映射成
/// 用户可见文案；[rawMessage] 保留原始错误详情（写日志用），与旧 MAUI
/// `LLMService` 抛 `Exception(AppResources.XXX)` 的语义对齐——service 层不依赖
/// localization，只把「该用哪个 l10n 键 + 占位参数」告诉调用方。
class LlmException implements Exception {
  final String l10nKey;
  final List<Object> args;
  final String rawMessage;
  LlmException(this.l10nKey, this.rawMessage, [this.args = const []]);
  @override
  String toString() => rawMessage;
}

/// 消费 SSE 行列表，累积返回全文。可单测的纯函数（无 receiver，供测试直接调用）。
String processSseLines(List<String> lines, void Function(String) onChunk) {
  final sb = StringBuffer();
  for (final line in lines) {
    if (SseParser.isDone(line)) break;
    final delta = SseParser.extractDeltaContent(line);
    if (delta != null) {
      sb.write(delta);
      onChunk(delta);
    }
  }
  return sb.toString();
}

class LlmService {
  final LogService log;
  LlmService(this.log);

  /// OpenAI 兼容流式调用。失败抛 [LlmException]（携带 l10nKey 供调用方本地化；
  /// 调用方处理重试与 LastAutoTriggerKey）。
  Future<String> askStream({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String question,
    required void Function(String chunk) onChunk,
  }) async {
    if (apiUrl.trim().isEmpty) {
      throw LlmException('apiUrlNotConfigured', 'API URL 未配置');
    }
    if (apiKey.trim().isEmpty) {
      throw LlmException('apiKeyNotConfigured', 'API Key 未配置');
    }

    final body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': [
        {'role': 'user', 'content': question}
      ],
      'temperature': 0.9,
    });

    final reqLog = StringBuffer()
      ..writeln('========== [Request] ==========')
      ..writeln('POST $apiUrl')
      ..writeln('Authorization: Bearer ***')
      ..writeln('Content-Type: application/json')
      ..writeln()
      ..writeln(_prettyJson(body));
    log.append(reqLog.toString());

    final request = http.Request('POST', Uri.parse(apiUrl));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Content-Type'] = 'application/json';
    request.body = body;

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 120),
      );

      final respLog = StringBuffer()
        ..writeln('========== [Response] ${response.statusCode} ==========');
      log.append(respLog.toString());

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errBody = await response.stream.bytesToString();
        log.append(errBody);
        // apiCallFailed 占位 {0}=statusCode、{1}=errBody（见 AppResources.resx
        // ApiCallFailedFormat）；args 顺序与 resx 占位符出现顺序一致。
        throw LlmException(
          'apiCallFailed',
          'API 调用失败: ${response.statusCode} $errBody',
          [response.statusCode, errBody],
        );
      }

      final full = StringBuffer();
      // 给流式消费加总超时 120s（与首字节 send 一致，覆盖 stall）。超时向 sink 注入
      // TimeoutException 并关闭流，被下方 await for 抛出，最终由 _callLlmOnce catch
      // 兜底为 errorMessage。长输出场景 120s 总时长一般足够；若需更长可调。
      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 120), onTimeout: (sink) {
        sink.addError(TimeoutException('SSE 流式响应超时（120s）'));
        sink.close();
      });
      await for (final line in lineStream) {
        if (SseParser.isDone(line)) break;
        final delta = SseParser.extractDeltaContent(line);
        if (delta != null) {
          full.write(delta);
          onChunk(delta);
        }
      }
      log.append(_prettyJson(full.toString()));
      return full.toString();
    } finally {
      client.close();
    }
  }

  String _prettyJson(String raw) {
    try {
      final obj = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return raw;
    }
  }
}
