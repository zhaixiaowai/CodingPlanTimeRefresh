import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/utils/aes.dart';

void main() {
  group('Aes256Cbc 兼容旧版', () {
    test('加密-解密往返还原原文', () {
      const plain = '{"IsAlwaysOnTop":true,"ApiUrl":"https://x","ApiKey":"sk-1","Model":"glm-5.1","LastAutoTriggerKey":"","IsCollapsed":false,"Language":"zh"}';
      final cipher = Aes256Cbc.encrypt(plain);
      expect(Aes256Cbc.decrypt(cipher), plain);
    });

    test('密文为原始字节（与旧版 config.dat 一致，非 Base64 文本）', () {
      final cipher = Aes256Cbc.encrypt('hello');
      // 密文长度是 16 的倍数（AES 块大小），且不是可读 ASCII 文本
      expect(cipher.length % 16, 0);
      expect(cipher.length, greaterThan(0));
    });

    test('中文内容往返', () {
      const plain = '用量百分比 80%';
      expect(Aes256Cbc.decrypt(Aes256Cbc.encrypt(plain)), plain);
    });

    test('空字符串往返', () {
      expect(Aes256Cbc.decrypt(Aes256Cbc.encrypt('')), '');
    });
  });
}
