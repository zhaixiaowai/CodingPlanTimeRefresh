import 'dart:convert';

/// OpenAI 兼容 SSE 单行解析。复刻旧版 AskStreamAsync 的逐行处理。
class SseParser {
  static const _prefix = 'data: ';

  static bool isDone(String line) => line == 'data: [DONE]';

  /// 返回该行的 delta.content；无内容、坏 chunk、非 data 行均返回 null。
  static String? extractDeltaContent(String line) {
    if (line.isEmpty || isDone(line)) return null;
    if (!line.startsWith(_prefix)) return null;
    final data = line.substring(_prefix.length);
    try {
      final doc = jsonDecode(data) as Map<String, dynamic>;
      final choices = doc['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices[0];
      if (first is! Map<String, dynamic>) return null;
      final delta = first['delta'];
      if (delta is! Map<String, dynamic>) return null;
      final content = delta['content'];
      return content is String ? content : null;
    } catch (_) {
      return null; // 坏 chunk 跳过
    }
  }
}
