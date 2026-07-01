import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/log_service.dart';

void main() {
  late Directory tmpDir;
  late LogService log;
  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('log_test_');
    log = LogService(tmpDir);
  });
  tearDown(() => tmpDir.deleteSync(recursive: true));

  test('append 写入 log.txt 并追加', () {
    log.append('第一行');
    log.append('第二行');
    final content =
        File('${tmpDir.path}${Platform.pathSeparator}log.txt').readAsStringSync();
    expect(content.contains('第一行'), isTrue);
    expect(content.contains('第二行'), isTrue);
  });

  test('每条带时间戳前缀', () {
    log.append('hi');
    final content =
        File('${tmpDir.path}${Platform.pathSeparator}log.txt').readAsStringSync();
    expect(RegExp(r'\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]').hasMatch(content), isTrue);
  });
}
