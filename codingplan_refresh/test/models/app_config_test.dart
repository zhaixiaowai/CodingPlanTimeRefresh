import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';

void main() {
  test('新格式多组往返', () {
    final c = AppConfig(
      providers: [
        ProviderConfig(
          id: 'a',
          name: '智谱',
          apiUrl: 'https://x',
          apiKey: 'k',
          model: 'glm-5.1',
        ),
        ProviderConfig(
          id: 'b',
          name: '火山',
          apiUrl: 'https://ark',
          apiKey: 'k2',
          model: 'ep-1',
        ),
      ],
      isAlwaysOnTop: true,
      language: 'zh',
      lastTriggerKeys: {'a': '2026-06-27 01:00'},
    );
    final json = c.toJson();
    expect(json['Providers'], isA<List>());
    final loaded = AppConfig.fromJson(json);
    expect(loaded.providers.length, 2);
    expect(loaded.providers[0].id, 'a');
    expect(loaded.providers[1].name, '火山');
    expect(loaded.lastTriggerKeys['a'], '2026-06-27 01:00');
  });

  test('旧单组格式迁移为 providers[0]', () {
    final legacy = <String, dynamic>{
      'IsAlwaysOnTop': false,
      'ApiUrl': 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      'ApiKey': 'sk-x',
      'Model': 'glm-5.1',
      'LastAutoTriggerKey': '2026-06-27 01:00',
      'IsCollapsed': true, // 应被丢弃（新模型无此字段）
      'Language': 'zh',
    };
    final c = AppConfig.fromJson(legacy);
    expect(c.providers.length, 1);
    expect(c.providers[0].apiUrl, contains('bigmodel.cn'));
    expect(c.lastTriggerKeys[c.providers[0].id], '2026-06-27 01:00');
    // IsCollapsed 无对应字段，已丢弃（无 isCollapsed 属性可验）
  });

  test('ProviderConfig.copyWith 保留 id', () {
    final p = ProviderConfig(id: 'x', name: 'a');
    final p2 = p.copyWith(name: 'b');
    expect(p2.id, 'x');
    expect(p2.name, 'b');
  });

  test('triggerHours 默认 [1,7,13,19]', () {
    final c = AppConfig(providers: []);
    expect(c.triggerHours, [1, 7, 13, 19]);
  });

  test('triggerHours 序列化往返', () {
    final c = AppConfig(
      providers: [ProviderConfig(id: 'a', name: 'x')],
      triggerHours: [2, 8, 14, 20],
    );
    final loaded = AppConfig.fromJson(c.toJson());
    expect(loaded.triggerHours, [2, 8, 14, 20]);
  });

  test('新格式 JSON 无 TriggerHours → 默认', () {
    final json = <String, dynamic>{
      'Providers': [
        {
          'Id': 'a',
          'Name': 'x',
          'ApiUrl': '',
          'ApiKey': '',
          'Model': 'glm-5.1',
        },
      ],
      'IsAlwaysOnTop': false,
    };
    final c = AppConfig.fromJson(json);
    expect(c.triggerHours, [1, 7, 13, 19]);
  });

  test('旧单组格式迁移 → triggerHours 默认', () {
    final legacy = <String, dynamic>{
      'ApiUrl': 'https://x',
      'ApiKey': 'k',
      'Model': 'glm-5.1',
    };
    final c = AppConfig.fromJson(legacy);
    expect(c.triggerHours, [1, 7, 13, 19]);
  });
}
