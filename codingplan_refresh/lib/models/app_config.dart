import 'dart:convert';

/// 配置模型，JSON 字段名与旧 MAUI 版（PascalCase）完全一致。
class AppConfig {
  bool isAlwaysOnTop;
  String apiUrl;
  String apiKey;
  String model;
  String lastAutoTriggerKey;
  bool isCollapsed;
  String? language;

  AppConfig({
    this.isAlwaysOnTop = false,
    this.apiUrl = '',
    this.apiKey = '',
    this.model = 'glm-5.1',
    this.lastAutoTriggerKey = '',
    this.isCollapsed = false,
    this.language,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        isAlwaysOnTop: json['IsAlwaysOnTop'] as bool? ?? false,
        apiUrl: json['ApiUrl'] as String? ?? '',
        apiKey: json['ApiKey'] as String? ?? '',
        model: json['Model'] as String? ?? 'glm-5.1',
        lastAutoTriggerKey: json['LastAutoTriggerKey'] as String? ?? '',
        isCollapsed: json['IsCollapsed'] as bool? ?? false,
        language: json['Language'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'IsAlwaysOnTop': isAlwaysOnTop,
        'ApiUrl': apiUrl,
        'ApiKey': apiKey,
        'Model': model,
        'LastAutoTriggerKey': lastAutoTriggerKey,
        'IsCollapsed': isCollapsed,
        if (language != null) 'Language': language,
      };

  String toJsonString() => jsonEncode(toJson());
}
