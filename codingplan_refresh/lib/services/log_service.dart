import 'dart:io';

class LogService {
  final Directory dataDir;
  LogService(this.dataDir);

  File get _logFile =>
      File('${dataDir.path}${Platform.pathSeparator}log.txt');

  void append(String message) {
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
    final now = DateTime.now();
    final stamp =
        '[${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}]';
    final line = '$stamp $message\n';
    _logFile.writeAsStringSync(line, mode: FileMode.append, flush: true);
  }

  /// 请求日志：统一信封 + 自动脱敏 Authorization 类头（修 V13，三处日志漂移）。
  /// [label] 如 'LLM'/'Usage'，自动拼成 '[label Request]'。
  void appendRequestLog(
    String label,
    String method,
    String url,
    Map<String, String> headers, {
    String? body,
  }) {
    final sb = StringBuffer()
      ..writeln('========== [$label Request] ==========')
      ..writeln('$method $url');
    headers.forEach((k, v) {
      sb.writeln('$k: ${k.toLowerCase().contains('auth') ? '***' : v}');
    });
    if (body != null) sb..writeln()..writeln(body);
    append(sb.toString());
  }

  /// 响应日志：统一信封（修 V13）。
  void appendResponseLog(String label, int statusCode, [String? body]) {
    append('========== [$label Response] $statusCode ==========' +
        (body == null ? '' : '\n$body'));
  }
}
