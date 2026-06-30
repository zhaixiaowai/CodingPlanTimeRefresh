import 'dart:convert';

/// 单个厂商配置。id 在创建时生成（稳定标识），拖动排序不变；
/// 用于运行时状态（ResultState/UsageResult/lastTriggerKeys）按键关联。
///
/// [accessKey] / [secretKey] 仅火山方舟用量查询使用（OpenAPI V4 签名 AK/SK），
/// 智谱等其它厂商留空；旧配置无这两个字段时默认空字符串（向后兼容）。
class ProviderConfig {
  final String id;
  String name;
  String apiUrl;
  String apiKey;
  String model;
  String accessKey;
  String secretKey;

  ProviderConfig({
    required this.id,
    this.name = '',
    this.apiUrl = '',
    this.apiKey = '',
    this.model = 'glm-5.1',
    this.accessKey = '',
    this.secretKey = '',
  });

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
    apiUrl: json['ApiUrl'] as String? ?? '',
    apiKey: json['ApiKey'] as String? ?? '',
    model: json['Model'] as String? ?? 'glm-5.1',
    accessKey: json['AccessKey'] as String? ?? '',
    secretKey: json['SecretKey'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'Id': id,
    'Name': name,
    'ApiUrl': apiUrl,
    'ApiKey': apiKey,
    'Model': model,
    'AccessKey': accessKey,
    'SecretKey': secretKey,
  };

  ProviderConfig copyWith({
    String? name,
    String? apiUrl,
    String? apiKey,
    String? model,
    String? accessKey,
    String? secretKey,
  }) => ProviderConfig(
    id: id,
    name: name ?? this.name,
    apiUrl: apiUrl ?? this.apiUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    accessKey: accessKey ?? this.accessKey,
    secretKey: secretKey ?? this.secretKey,
  );
}

/// 应用配置（多组 provider）。
///
/// JSON 字段命名与旧 MAUI 版（PascalCase）保持风格一致：`Providers` /
/// `IsAlwaysOnTop` / `Language` / `LastTriggerKeys`。旧单组格式
/// （`ApiUrl`/`ApiKey`/`Model`/`IsCollapsed`/`LastAutoTriggerKey`）由
/// [AppConfig.fromJson] 自动迁移为 `providers[0]`，原 `IsCollapsed` 字段丢弃
/// （新设计无此字段；折叠态由窗口尺寸决定，不再持久化）。
class AppConfig {
  List<ProviderConfig> providers;
  bool isAlwaysOnTop;
  String? language;

  /// key = provider.id → 该 provider 的 LastAutoTriggerKey（定时去重，每个 provider 独立）。
  Map<String, String> lastTriggerKeys;

  /// 定时触发时刻默认值（整点 0-23）。AppConfig 缺省与 SchedulerService fallback
  /// 共用此单一来源，避免散落字面量分叉。
  static const List<int> defaultTriggerHours = [1, 7, 13, 19];

  /// 定时触发时刻（整点 0-23）。默认 [defaultTriggerHours]；空列表 = 关闭定时保活。
  List<int> triggerHours;

  AppConfig({
    List<ProviderConfig>? providers,
    this.isAlwaysOnTop = false,
    this.language,
    Map<String, String>? lastTriggerKeys,
    List<int>? triggerHours,
  }) : providers = providers ?? [],
       lastTriggerKeys = lastTriggerKeys ?? {},
       triggerHours = triggerHours ?? defaultTriggerHours;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    // 新格式：Providers 数组
    if (json['Providers'] is List) {
      final providers = (json['Providers'] as List)
          .map((e) => ProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();
      final ltk = <String, String>{};
      final rawLtk = json['LastTriggerKeys'];
      if (rawLtk is Map) {
        rawLtk.forEach((k, v) => ltk[k.toString()] = v.toString());
      }
      return AppConfig(
        providers: providers,
        isAlwaysOnTop: json['IsAlwaysOnTop'] as bool? ?? false,
        language: json['Language'] as String?,
        lastTriggerKeys: ltk,
        triggerHours:
            ((json['TriggerHours'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                // 过滤越界小时（0-23）：防配置被篡改/异常时 nextTrigger 靠 DateTime
                // 规范化显示「01:00」但 checkTrigger 的 now.hour==h 永不命中、
                // 保活静默失效。
                .where((h) => h >= 0 && h < 24)
                .toList()) ??
            defaultTriggerHours,
      );
    }
    // 旧格式（单组 ApiUrl/ApiKey/Model/...）→ 迁移为 providers[0]。
    // id 固定用 'legacy'：单次迁移只产生一个 providers[0]，运行时只读不依 id
    // 全局唯一跨实例，故固定值即可（无需计数器避免 _legacyIdCounter 未定义）。
    const id = 'legacy';
    return AppConfig(
      providers: [
        ProviderConfig(
          id: id,
          name: '默认',
          apiUrl: json['ApiUrl'] as String? ?? '',
          apiKey: json['ApiKey'] as String? ?? '',
          model: json['Model'] as String? ?? 'glm-5.1',
        ),
      ],
      isAlwaysOnTop: json['IsAlwaysOnTop'] as bool? ?? false,
      language: json['Language'] as String?,
      lastTriggerKeys: {id: json['LastAutoTriggerKey'] as String? ?? ''},
      triggerHours: defaultTriggerHours,
    );
  }

  Map<String, dynamic> toJson() => {
    'Providers': providers.map((p) => p.toJson()).toList(),
    'IsAlwaysOnTop': isAlwaysOnTop,
    if (language != null) 'Language': language,
    'LastTriggerKeys': lastTriggerKeys,
    'TriggerHours': triggerHours,
  };

  String toJsonString() => jsonEncode(toJson());
}
