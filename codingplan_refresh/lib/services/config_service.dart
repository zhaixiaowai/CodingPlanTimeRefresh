import 'dart:convert';
import 'dart:io';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/utils/aes.dart';

class ConfigService {
  /// 窗口尺寸常量（与旧版 ConfigService.cs 一致）。
  static const double expandedWidth = 260;
  static const double expandedHeight = 318;

  /// 按语言返回 mini 窗口宽度。中文 label/reset 文本短（5H/周/月、重置 06/27 09:05），
  /// 可更窄；英文 Week/Month、Reset MM/dd HH:mm 较长需更宽。语言切换后窗口宽度随之变。
  /// [lang] 为 'zh'/'en'，其它（auto 解析前）回退 expandedWidth。
  static double widthForLanguage(String? lang) {
    return lang == 'zh' ? 230 : expandedWidth;
  }
  static const double collapsedHeight = 120;
  static const double collapsedHeightWithWeekly = 142;

  final Directory dataDir;
  ConfigService(this.dataDir);

  File get _configFile =>
      File('${dataDir.path}${Platform.pathSeparator}config.dat');
  File get _legacyJsonFile =>
      File('${dataDir.path}${Platform.pathSeparator}config.json');

  /// 加载配置，按迁移链路：旧路径 config.dat → 当前 config.dat(加密) → 旧明文 config.json → 默认。
  AppConfig load() {
    _migrateFromOldPath();
    if (_configFile.existsSync()) {
      try {
        final bytes = _configFile.readAsBytesSync();
        final json = Aes256Cbc.decrypt(bytes);
        return AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (_) {
        return _tryLoadLegacyJson();
      }
    }
    return _tryLoadLegacyJson();
  }

  void save(AppConfig config) {
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
    final cipher = Aes256Cbc.encrypt(config.toJsonString());
    _configFile.writeAsBytesSync(cipher);
  }

  /// 旧明文 config.json：读取后转存加密格式并删除明文。
  AppConfig _tryLoadLegacyJson() {
    if (!_legacyJsonFile.existsSync()) return AppConfig();
    try {
      final json = _legacyJsonFile.readAsStringSync();
      final config =
          AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      save(config);
      _legacyJsonFile.deleteSync();
      return config;
    } catch (_) {
      return AppConfig();
    }
  }

  /// 从程序运行目录下的 data/config.dat 迁移到当前 dataDir（复刻旧版 MigrateFromOldPath）。
  void _migrateFromOldPath() {
    if (_configFile.existsSync()) return;
    // 用 exe 所在目录定位（打包后 Directory.current 不可靠；旧版用 AppDomain.BaseDirectory）。
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final oldPath =
        '$exeDir${Platform.pathSeparator}data${Platform.pathSeparator}config.dat';
    final oldFile = File(oldPath);
    if (!oldFile.existsSync()) return;
    try {
      if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
      oldFile.copySync(_configFile.path);
    } catch (_) {/* 迁移失败不影响启动 */}
  }
}
