import 'dart:io';
import 'package:intl/intl.dart';

/// 本地化服务。
///
/// 键 → {语言: 文案}。文案从旧 MAUI 资源文件原样抄录：
/// - 中文（zh）：CodingPlanTimeRefresh/Resources/Strings/AppResources.resx
/// - 英文（en）：CodingPlanTimeRefresh/Resources/Strings/AppResources.en.resx
///
/// 旧 resx 使用 .NET 复合格式占位符（`{0}`、`{0:HH:mm}` 等），此处保留原样；
/// 占位符替换由 [FmtString.fmt] 真解析（带格式的 `DateTime` 参数用 `DateFormat` 渲染），
/// 与 MAUI 端 `string.Format` 行为一致。
class LocalizationService {
  /// 当前语言代码：`'zh'` 或 `'en'`。
  String current = 'zh';

  static const _table = <String, Map<String, String>>{
    // ManualTriggerButton
    'manualTrigger': {'zh': '手动触发大模型', 'en': 'Trigger LLM'},
    // ManualTriggerPopupButton
    'manualTriggerPopup': {'zh': '手动触发,让模型讲个冷笑话', 'en': 'Trigger a joke'},
    // WaitingPlaceholder
    'waitingPlaceholder': {'zh': '等待触发...', 'en': 'Waiting...'},
    // ResultHeader
    'resultHeader': {'zh': '返回结果', 'en': 'Result'},
    // SaveButton
    'save': {'zh': '保存', 'en': 'Save'},
    // CancelButton
    'cancel': {'zh': '取消', 'en': 'Cancel'},
    // Token5HLabel
    'token5hLabel': {'zh': 'Token(5H)', 'en': 'Token(5H)'},
    // TokenWeekLabel
    'tokenWeekLabel': {'zh': 'Token(周)', 'en': 'Token(Week)'},
    // MCPMonthLabel
    'mcpMonthLabel': {'zh': 'MCP(月)', 'en': 'MCP(Month)'},
    // UsageItem.labelKey 用（无 Label 后缀）：token5h / tokenWeekly / tokenMonthly / mcpMonthly
    'token5h': {'zh': 'Token(5H)', 'en': 'Token(5H)'},
    'tokenWeekly': {'zh': 'Token(周)', 'en': 'Token(Week)'},
    'tokenMonthly': {'zh': 'Token(月)', 'en': 'Token(Month)'},
    'mcpMonthly': {'zh': 'MCP(月)', 'en': 'MCP(Month)'},
    // ☰ 菜单标题
    'settings': {'zh': '设置', 'en': 'Settings'},
    // PinLabel
    'pinLabel': {'zh': '置顶', 'en': 'Pin'},
    // TriggerTimesLabel —— 触发时刻分区标题
    'triggerTimesLabel': {'zh': '触发时刻（整点）', 'en': 'Trigger Hours'},
    // LanguageLabel
    'languageLabel': {'zh': '语言', 'en': 'Language'},
    // LanguageAuto
    'languageAuto': {'zh': '自动', 'en': 'Auto'},
    // LanguageZh
    'languageZh': {'zh': '中文', 'en': 'Chinese'},
    // LanguageEn
    'languageEn': {'zh': 'English', 'en': 'English'},
    // LoadingText
    'loading': {'zh': '调用中...', 'en': 'Calling...'},
    // UsageLoadingText —— 用量查询中（首次无旧数据时用量框占位）
    'usageLoading': {'zh': '用量查询中...', 'en': 'Loading usage...'},
    // ErrorMessageFormat —— 占位 {0}
    'errorMessage': {'zh': '错误，等待重试: {0}', 'en': 'Error, retrying: {0}'},
    // ApiUrlNotConfigured
    'apiUrlNotConfigured': {
      'zh': 'API URL 未配置',
      'en': 'API URL not configured',
    },
    // ApiKeyNotConfigured
    'apiKeyNotConfigured': {
      'zh': 'API Key 未配置',
      'en': 'API Key not configured',
    },
    // ApiCallFailedFormat —— 占位 {0}、{1}
    'apiCallFailed': {
      'zh': 'API 调用失败: {0} - {1}',
      'en': 'API call failed: {0} - {1}',
    },
    // WindowTitleFormat —— 占位 {0}、{1}
    'windowTitle': {
      'zh': '{0}%已使用({1} Coding Plan)',
      'en': '{0}% used ({1} Coding Plan)',
    },
    // NextTriggerFormat —— 占位 {0:HH:mm}、{1}、{2}
    'nextTriggerFormat': {
      'zh': '下次触发大模型: {0:HH:mm} ({1}分{2}秒后)',
      'en': 'Next trigger: {0:HH:mm} ({1}m{2}s)',
    },
    // ResetTextToday —— 占位 {0:HH:mm}
    'resetToday': {'zh': '重置 {0:HH:mm}', 'en': 'Reset {0:HH:mm}'},
    // ResetTextOther —— 占位 {0:MM/dd HH:mm}
    'resetOther': {'zh': '重置 {0:MM/dd HH:mm}', 'en': 'Reset {0:MM/dd HH:mm}'},
    // JokePrompt
    'jokePrompt': {
      'zh': '说一个冷笑话，不要重复常见段子，尽量新颖。',
      'en':
          'Tell a corny joke, avoid repeating common jokes, and try to be original.',
    },
    // ResultTimestampFormat —— 占位 {0:HH:mm:ss}
    'resultTimestamp': {
      'zh': '返回结果(最后调用于 {0:HH:mm:ss})',
      'en': 'Result (last called at {0:HH:mm:ss})',
    },
  };

  /// 初始化语言。`saved` 为持久化的设置：`'zh'`/`'en'`/`'auto'`。
  /// - `null`/空/`'auto'`：按 `Platform.localeName` 判定（英文环境→en，其余→zh）。
  /// - 其它：`'en'` → en，其它一律视为 zh。
  void initialize(String? saved) {
    if (saved == null || saved.isEmpty || saved == 'auto') {
      current = Platform.localeName.toLowerCase().startsWith('en')
          ? 'en'
          : 'zh';
    } else {
      current = saved == 'en' ? 'en' : 'zh';
    }
  }

  /// 切换语言，返回生效后的语言代码。`'auto'` 同 `initialize` 自动判定。
  String setLanguage(String code) {
    if (code == 'auto') {
      current = Platform.localeName.toLowerCase().startsWith('en')
          ? 'en'
          : 'zh';
    } else {
      current = code == 'en' ? 'en' : 'zh';
    }
    return current;
  }

  /// 取文案。未知键返回键本身；当前语言缺失时回退到中文。
  String t(String key) {
    final entry = _table[key];
    if (entry == null) return key;
    return entry[current] ?? entry['zh']!;
  }
}

/// 占位符替换扩展。
///
/// 旧 resx 使用 .NET 复合格式：`{0}`、`{1}`、`{0:HH:mm}`、`{0:MM/dd HH:mm}` 等。
/// `fmt` 真解析该格式：按 **出现顺序** 逐个替换首个 `{N}` / `{N:format}` 占位——
/// 若占位带格式说明符（`:HH:mm` 等）且对应参数为 `DateTime`，则用 `intl` 的
/// `DateFormat` 按该格式渲染；参数为 `String`/`num` 等时忽略格式直接替换。
/// `args` 的顺序必须与 resx 占位符 `{0}`、`{1}`、`{2}` ... 的出现顺序一致。
extension FmtString on String {
  /// 按 args 出现顺序逐个替换首个 `{N}` / `{N:format}` 占位。
  /// 带格式说明符且参数为 DateTime 时，用 intl 的 DateFormat 渲染。
  String fmt(List<Object> args) {
    var s = this;
    final re = RegExp(r'\{(\d+)(?::([^}]*))?\}');
    for (final a in args) {
      s = s.replaceFirstMapped(re, (match) {
        final format = match.group(2);
        final arg = a;
        if (format != null && format.isNotEmpty && arg is DateTime) {
          return DateFormat(format).format(arg);
        }
        return '$arg';
      });
    }
    return s;
  }
}
