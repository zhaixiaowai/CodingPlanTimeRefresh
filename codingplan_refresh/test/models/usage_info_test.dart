import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/usage_info.dart';

void main() {
  group('usageDisplayTitle name 优先 + 保留套餐', () {
    test('name 非空 → 用 name 前缀 + vendorTitle 套餐', () {
      // name='我的智谱' + '智谱 Pro' → '我的智谱 Pro'（套餐保留）
      expect(usageDisplayTitle('我的智谱', '智谱 Pro'), '我的智谱 Pro');
    });

    test('name 空 → 用 vendorTitle 厂商名 + 套餐（等价原 vendorTitle）', () {
      expect(usageDisplayTitle('', '智谱 Pro'), '智谱 Pro');
      expect(usageDisplayTitle('', '火山方舟 Personal'), '火山方舟 Personal');
    });

    test('vendorTitle 无套餐（无空格）→ 仅 name 或厂商名', () {
      expect(usageDisplayTitle('', '智谱'), '智谱');
      expect(usageDisplayTitle('我的', '智谱'), '我的');
    });

    test('name 非空且 vendorTitle 无套餐 → 仅 name', () {
      expect(usageDisplayTitle('我的智谱', '智谱'), '我的智谱');
    });

    test('套餐为多段时整体保留（sublist join）', () {
      // 假想「火山方舟 Enterprise Pro」→ 套餐='Enterprise Pro'
      expect(
        usageDisplayTitle('', '火山方舟 Enterprise Pro'),
        '火山方舟 Enterprise Pro',
      );
      expect(
        usageDisplayTitle('我的方舟', '火山方舟 Enterprise Pro'),
        '我的方舟 Enterprise Pro',
      );
    });
  });
}
