import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/utils/sse.dart';
import 'package:codingplan_refresh/utils/user_agent.dart';

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
    String? sessionId,
    int retryCount = 0,
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

    // sessionId 由调用方传入（重试时复用同值，修 V1），null 则本次随机生成。
    final claudeHeaders = claudeCliHeaders(
      sessionId: sessionId ?? randomUuid(),
      retryCount: retryCount,
    );
    log.appendRequestLog(
      'LLM',
      'POST',
      apiUrl,
      {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'User-Agent': kLlmUserAgent,
        ...claudeHeaders,
      },
      body: _prettyJson(body),
    );

    final request = http.Request('POST', Uri.parse(apiUrl));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Content-Type'] = 'application/json';
    request.headers['User-Agent'] = kLlmUserAgent;
    // claude-cli 伪装专用头（Session-Id 随机 UUID），让网络层判定为 claude-cli 流量。
    claudeHeaders.forEach((k, v) => request.headers[k] = v);
    request.body = body;

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 120),
      );

      log.appendResponseLog('LLM', response.statusCode);
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
      // 给流式消费加空闲超时 120s（Stream.timeout 是间隔超时：每收到一行重置计时，
      // 覆盖「服务端发头后挂住、长时间无新行」的 stall，不是总时长上限——活跃流
      // 按 <120s 间隔持续输出可超过 120s）。超时向 sink 注入 TimeoutException 并关闭流，
      // 被下方 await for 抛出，最终由 _callLlmOnce catch 兜底为 errorMessage。
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
