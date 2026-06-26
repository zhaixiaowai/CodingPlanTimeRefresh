import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/utils/aes.dart';

void main() {
  late Directory tmpDir;
  late ConfigService svc;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('cfg_test_');
    svc = ConfigService(tmpDir);
  });
  tearDown(() => tmpDir.deleteSync(recursive: true));

  test('无配置文件返回默认值', () {
    final c = svc.load();
    expect(c.isAlwaysOnTop, false);
    expect(c.model, 'glm-5.1');
    expect(c.language, isNull);
  });

  test('save 后 load 往返还原', () {
    final c = AppConfig(
      isAlwaysOnTop: true,
      apiUrl: 'https://x',
      apiKey: 'sk-1',
      model: 'glm-5.1',
      lastAutoTriggerKey: '2026-06-25 01:00',
      isCollapsed: true,
      language: 'zh',
    );
    svc.save(c);
    final loaded = svc.load();
    expect(loaded.apiUrl, 'https://x');
    expect(loaded.isAlwaysOnTop, true);
    expect(loaded.lastAutoTriggerKey, '2026-06-25 01:00');
    expect(loaded.language, 'zh');
  });

  test('保存的 config.dat 为加密字节（不可读明文）', () {
    svc.save(AppConfig(apiKey: 'sk-secret'));
    final bytes = File('${tmpDir.path}${Platform.pathSeparator}config.dat').readAsBytesSync();
    final raw = String.fromCharCodes(bytes);
    expect(raw.contains('sk-secret'), isFalse); // 明文不应出现
  });

  test('旧明文 config.json 被迁移为加密格式并删除', () {
    const legacyJson = '{"IsAlwaysOnTop":false,"ApiUrl":"https://y","ApiKey":"sk-2","Model":"glm-5.1","LastAutoTriggerKey":"","IsCollapsed":false}';
    File('${tmpDir.path}${Platform.pathSeparator}config.json')
        .writeAsStringSync(legacyJson);
    final loaded = svc.load();
    expect(loaded.apiUrl, 'https://y');
    expect(loaded.apiKey, 'sk-2');
    // 明文文件应已删除
    expect(File('${tmpDir.path}${Platform.pathSeparator}config.json').existsSync(), isFalse);
    // 加密文件应已生成
    expect(File('${tmpDir.path}${Platform.pathSeparator}config.dat').existsSync(), isTrue);
  });

  test('JSON 字段为 PascalCase（与旧 MAUI 兼容）', () {
    svc.save(AppConfig(apiKey: 'sk-x'));
    // 解密 config.dat 后直接断言序列化出的 JSON key 为 PascalCase，
    // 防止误改为 camelCase 导致旧 MAUI config.dat 无法被读取（迁移兼容性回归守卫）。
    final bytes = File('${tmpDir.path}${Platform.pathSeparator}config.dat').readAsBytesSync();
    final json = Aes256Cbc.decrypt(bytes);
    final map = jsonDecode(json) as Map<String, dynamic>;
    expect(map.containsKey('IsAlwaysOnTop'), isTrue);
    expect(map.containsKey('ApiUrl'), isTrue);
    expect(map.containsKey('ApiKey'), isTrue);
    expect(map.containsKey('Model'), isTrue);
    expect(map.containsKey('LastAutoTriggerKey'), isTrue);
    expect(map.containsKey('IsCollapsed'), isTrue);
    // camelCase 不应出现
    expect(map.containsKey('isAlwaysOnTop'), isFalse);
    expect(map.containsKey('apiKey'), isFalse);
  });
}
