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
}
