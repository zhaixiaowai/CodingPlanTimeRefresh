import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

/// 复刻旧 MAUI 版 ConfigService 的 AES-256-CBC + PKCS7。
/// key/IV 与旧版完全一致，保证能解密旧 config.dat。
class Aes256Cbc {
  static final Key _key =
      Key.fromBase64('Y2RmN2g5azNxUDZ5V0JuTG1SNXZpM3hYN2tybEk4SFg=');
  static final IV _iv = IV.fromBase64('UGs0dTl2T3dxWjRuY2xmSA==');

  static Encrypter get _encrypter =>
      Encrypter(AES(_key, mode: AESMode.cbc, padding: 'PKCS7'));

  /// 加密为原始密文字节（与旧版 File.WriteAllBytes 对应）。
  static List<int> encrypt(String plain) {
    if (plain.isEmpty) return [];
    return _encrypter.encrypt(plain, iv: _iv).bytes;
  }

  /// 解密原始密文字节（与旧版 File.ReadAllBytes 对应）。
  static String decrypt(List<int> cipherBytes) {
    if (cipherBytes.isEmpty) return '';
    final encrypted = Encrypted(Uint8List.fromList(cipherBytes));
    return _encrypter.decrypt(encrypted, iv: _iv);
  }
}
