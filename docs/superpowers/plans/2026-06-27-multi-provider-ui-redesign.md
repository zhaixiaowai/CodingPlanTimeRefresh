# 多厂商接入 + 主窗口 UI 重构 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已迁移的 Flutter 版上接入多厂商（智谱 + 火山方舟 arkcli）用量、主界面改为多用量框 + ☰ 下拉菜单 + 高度自适应、设置/结果改放大态（420×520）+ 屏幕边缘兼容。

**Architecture:** 配置改多组 `ProviderConfig`（稳定 id），用量查询抽象 `UsageProvider`（智谱 HTTP / 火山 arkcli cmd），主界面每个 provider 一个 legend `UsageFrame` 上下排列，结果 per-provider `ResultState`（定时遍历所有/手动下拉选一个），放大态动态尺寸 + 边缘平移。

**Tech Stack:** Flutter (Dart) 桌面；`window_manager`、`http`、`encrypt`、`path_provider`、`intl`、`dart:io` Process（arkcli）；测试 `flutter_test`。

## Global Constraints

- **分支**：`feature/flutter-migration`（HEAD `899865f`，未 push）。所有任务在此分支，**中文 commit，绝不 push**。
- **厂商 URL 推断**：`apiUrl` 含 `bigmodel.cn` → 智谱；含 `ark.cn-beijing.volces.com/api/` → 火山方舟；其他 → 未知。
- **用量行**：智谱 `token5h`(5H) / `tokenWeekly`(周) / `mcpMonthly`(MCP 月)；火山方舟 `token5h`(session) / `tokenWeekly`(weekly) / `tokenMonthly`(月 Token，**无 MCP**)。
- **框标题**：智谱 = `智谱` + `level` 首字母大写（level 缺省只显「智谱」）；火山方舟 = `火山方舟` + `edition` 首字母大写。
- **火山 arkcli**：`Process.start('arkcli', ['usage', 'plan'])`（Windows 走 `arkcli.cmd`），**10s 超时 `process.kill()`**；失败细化：未装(`ProcessException`)→「arkcli 未安装，参考 README」、`ok:false`→`error.message`、超时→「查询超时」、解析异常→「查询失败，未找到数据」。
- **配置多组**：`ProviderConfig` 含稳定 `id`（创建时生成）；`ReorderableListView` 拖动排序（无上移/下移按钮）；新增/删除(确认对话框)/编辑。
- **AES 不变**：沿用现有 `Aes256Cbc`（key/IV 不改）。旧单组 `config.dat` 迁移为 `providers[0]`（生成 id），`LastAutoTriggerKey`(单值) → `lastTriggerKeys[providers[0].id]`，`IsCollapsed` 丢弃。
- **mini 宽 330**（`ConfigService.expandedWidth`），高度自适应；**放大态 420×520**。
- **定时触发**：6s 轮询命中 01/07/13:00 → 遍历所有 providers 各自调用（per-provider `isBusy`/`isRetrying`/重试 3 次×5s），更新各自 `ResultState` + `lastTriggerKeys[id]`，不弹结果区。
- **手动触发面板**：下拉选 provider → 结果区显示该 provider `ResultState`；触发该 provider 实时流式（节流 50ms）；定时与手动共享同一 provider 的 `ResultState`。
- **flutter 路径**：`D:\Program Files\flutter_sdk\bin`（在 PATH；若 Bash 报 command not found，先 `export PATH="/d/Program Files/flutter_sdk/bin:$PATH"`）。
- **旧字段引用注意**：现有代码多处引用 `_config.apiUrl/apiKey/model/lastAutoTriggerKey/isCollapsed` 和 `UsageInfo/LimitInfo`，改造时要全部更新（编译器会报错定位）。

---

### Task 1: 数据模型 + 迁移（多组配置 + 统一用量模型）

**Files:**
- Modify: `codingplan_refresh/lib/models/app_config.dart`（改多组 + ProviderConfig）
- Modify: `codingplan_refresh/lib/models/usage_info.dart`（改 UsageResult/UsageItem）
- Test: `codingplan_refresh/test/models/app_config_test.dart`（新建）
- Test: `codingplan_refresh/test/services/config_service_test.dart`（修改：适配多组 + 迁移）

**Interfaces:**
- Consumes: `Aes256Cbc`（现有）
- Produces: `ProviderConfig{id,name,apiUrl,apiKey,model}`、`AppConfig{providers,isAlwaysOnTop,language,lastTriggerKeys}`、`UsageItem{labelKey,percentage,resetAtMs}`、`UsageResult{vendorTitle,items,errorMessage}`

- [ ] **Step 1: 改 `app_config.dart` 为多组**

完整替换 `lib/models/app_config.dart`：

```dart
import 'dart:convert';

/// 单个厂商配置。id 在创建时生成（稳定标识），拖动排序不变；
/// 用于运行时状态（ResultState/UsageResult/lastTriggerKeys）按键关联。
class ProviderConfig {
  final String id;
  String name;
  String apiUrl;
  String apiKey;
  String model;

  ProviderConfig({
    required this.id,
    this.name = '',
    this.apiUrl = '',
    this.apiKey = '',
    this.model = 'glm-5.1',
  });

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        apiUrl: json['ApiUrl'] as String? ?? '',
        apiKey: json['ApiKey'] as String? ?? '',
        model: json['Model'] as String? ?? 'glm-5.1',
      );

  Map<String, dynamic> toJson() => {
        'Id': id,
        'Name': name,
        'ApiUrl': apiUrl,
        'ApiKey': apiKey,
        'Model': model,
      };

  ProviderConfig copyWith({String? name, String? apiUrl, String? apiKey, String? model}) =>
      ProviderConfig(
        id: id,
        name: name ?? this.name,
        apiUrl: apiUrl ?? this.apiUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}

class AppConfig {
  List<ProviderConfig> providers;
  bool isAlwaysOnTop;
  String? language;
  // key = provider.id → 该 provider 的 LastAutoTriggerKey（定时去重，独立）
  Map<String, String> lastTriggerKeys;

  AppConfig({
    List<ProviderConfig>? providers,
    this.isAlwaysOnTop = false,
    this.language,
    Map<String, String>? lastTriggerKeys,
  })  : providers = providers ?? [],
        lastTriggerKeys = lastTriggerKeys ?? {};

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
      );
    }
    // 旧格式（单组 ApiUrl/ApiKey/Model/...）→ 迁移为 providers[0]
    final id = _legacyId;
    _legacyId = '${_legacyId}x'; // 多次解析递增避免碰撞（仅迁移兜底路径）
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
      lastTriggerKeys: {
        id: json['LastAutoTriggerKey'] as String? ?? '',
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'Providers': providers.map((p) => p.toJson()).toList(),
        'IsAlwaysOnTop': isAlwaysOnTop,
        if (language != null) 'Language': language,
        'LastTriggerKeys': lastTriggerKeys,
      };

  String toJsonString() => jsonEncode(toJson());
}

// 旧格式迁移用的临时 id 生成（DateTime 不可用，用静态计数）。
// 注：正常流程每次启动 fromJson 只走一次；此计数器仅兜底。
int _legacyIdCounter = 0;
String get _legacyId => 'legacy_${_legacyIdCounter}';
```

> 注意：上面 `_legacyId` 用计数器；`_legacyIdCounter` 未定义——改用更简单的方式：旧格式迁移时 id 用固定 `'legacy'`（单次迁移只会产生一个 providers[0]，id 重复无影响，因为运行时只读不依 id 全局唯一跨实例）。**修正**：删掉计数器逻辑，旧格式迁移 id 直接用 `'legacy'`：

```dart
    // 旧格式迁移
    const id = 'legacy';
    return AppConfig(
      providers: [
        ProviderConfig(id: id, name: '默认',
          apiUrl: json['ApiUrl'] as String? ?? '',
          apiKey: json['ApiKey'] as String? ?? '',
          model: json['Model'] as String? ?? 'glm-5.1'),
      ],
      isAlwaysOnTop: json['IsAlwaysOnTop'] as bool? ?? false,
      language: json['Language'] as String?,
      lastTriggerKeys: {id: json['LastAutoTriggerKey'] as String? ?? ''},
    );
```
（实现时直接用这个简化版，删掉计数器相关代码。）

- [ ] **Step 2: 改 `usage_info.dart` 为统一用量模型**

完整替换 `lib/models/usage_info.dart`：

```dart
/// 单条用量项（一行）。labelKey 为本地化键（见 LocalizationService._table）。
class UsageItem {
  final String labelKey; // 'token5h' / 'tokenWeekly' / 'tokenMonthly' / 'mcpMonthly'
  final double percentage;
  final int? resetAtMs; // Unix 毫秒，可空
  const UsageItem(this.labelKey, this.percentage, this.resetAtMs);
}

/// 单个 provider 的用量查询结果。
/// - 成功：items 非空、errorMessage == null
/// - 失败/无数据：items 空、errorMessage = 具体描述（框内显示）
class UsageResult {
  final String vendorTitle; // 框标题，如「智谱 Pro」「火山方舟 Personal」
  final List<UsageItem> items;
  final String? errorMessage;
  const UsageResult(this.vendorTitle, this.items, this.errorMessage);
}
```

> 同时需在 `localization_service.dart` 的 `_table` 增加键（Task 4 之前先补，避免编译缺键）：
> `'token5h': {'zh':'Token(5H)','en':'Token(5H)'}`、`'tokenWeekly': {'zh':'Token(周)','en':'Token(Week)'}`、`'tokenMonthly': {'zh':'Token(月)','en':'Token(Month)'}`、`'mcpMonthly': {'zh':'MCP(月)','en':'MCP(Month)'}`。
> （现有 `token5hLabel/tokenWeekLabel/mcpMonthLabel` 是旧键；新增无 Label 后缀的 `token5h/tokenWeekly/tokenMonthly/mcpMonthly` 作为 UsageItem.labelKey。）

- [ ] **Step 3: 写 app_config_test.dart**

创建 `test/models/app_config_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';

void main() {
  test('新格式多组往返', () {
    final c = AppConfig(
      providers: [
        ProviderConfig(id: 'a', name: '智谱', apiUrl: 'https://x', apiKey: 'k', model: 'glm-5.1'),
        ProviderConfig(id: 'b', name: '火山', apiUrl: 'https://ark', apiKey: 'k2', model: 'ep-1'),
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
      'IsCollapsed': true, // 应被丢弃
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
}
```

- [ ] **Step 4: 修改 config_service_test.dart 适配多组**

打开 `test/services/config_service_test.dart`，把所有引用旧字段（`apiUrl/apiKey/model/lastAutoTriggerKey/isCollapsed`）的断言改为多组：`config.providers[0].apiUrl` 等。删除涉及 `isCollapsed` 的测试（字段已移除）。PascalCase 测试改为断言 `Providers`/`Id`/`ApiUrl` 等键。示例关键断言：

```dart
// save 后 load 往返
final loaded = svc.load();
expect(loaded.providers.first.apiUrl, 'https://x');
expect(loaded.providers.first.apiKey, 'sk-1');
// 旧明文 config.json 迁移
final legacyJson = '{"IsAlwaysOnTop":false,"ApiUrl":"https://y","ApiKey":"sk-2","Model":"glm-5.1","LastAutoTriggerKey":""}';
// 迁移后 loaded.providers.first.apiUrl == 'https://y'
// PascalCase 测试：断言 map 含 'Providers'/'IsAlwaysOnTop'，不含 'ApiUrl'（顶层不再有）
```

- [ ] **Step 5: 运行测试**

```bash
cd codingplan_refresh
flutter test test/models/app_config_test.dart test/services/config_service_test.dart
```

期望：全 PASS。若有旧字段引用编译错，按报错更新测试。

- [ ] **Step 6: Commit**

```bash
git add codingplan_refresh/lib/models/ codingplan_refresh/test/models/ codingplan_refresh/test/services/config_service_test.dart codingplan_refresh/lib/services/localization_service.dart
git commit -m "feat(model): 多组配置 ProviderConfig/AppConfig + 统一用量 UsageResult/UsageItem + 旧单组迁移"
```

---

### Task 2: UsageProvider 抽象 + 智谱迁移

**Files:**
- Create: `codingplan_refresh/lib/services/usage_provider.dart`（抽象）
- Create: `codingplan_refresh/lib/services/bigmodel_usage_provider.dart`
- Modify: `codingplan_refresh/lib/services/usage_parser.dart`（返回 UsageResult）
- Test: `codingplan_refresh/test/services/usage_parser_test.dart`（适配 UsageResult）

**Interfaces:**
- Consumes: `UsageResult`/`UsageItem`（Task 1）、`LogService`
- Produces: `abstract class UsageProvider { Future<UsageResult> query(); }`、`BigmodelUsageProvider(apiKey, LogService)`

- [ ] **Step 1: 写抽象 + 智谱 provider**

创建 `lib/services/usage_provider.dart`：

```dart
import 'package:codingplan_refresh/models/usage_info.dart';

/// 用量查询抽象。每个 provider 一个实现。返回 UsageResult（成功 items 非空 / 失败 errorMessage）。
abstract class UsageProvider {
  Future<UsageResult> query();
}
```

- [ ] **Step 2: 改 usage_parser.dart 返回 UsageResult**

完整替换 `lib/services/usage_parser.dart`：

```dart
import 'dart:convert';
import 'package:codingplan_refresh/models/usage_info.dart';

/// 解析 BigModel 配额响应 → UsageResult。
/// vendorTitle = 「智谱」+ level 首字母大写；items = [token5h, tokenWeekly, mcpMonthly]。
UsageResult parseBigmodelUsage(String jsonBody, {String vendorTitle = '智谱'}) {
  try {
    final doc = jsonDecode(jsonBody) as Map<String, dynamic>;
    final data = doc['data'];
    if (data is! Map<String, dynamic>) {
      return const UsageResult('智谱', [], '查询失败，未找到数据');
    }
    final limits = data['limits'];
    if (limits is! List) {
      return const UsageResult('智谱', [], '查询失败，未找到数据');
    }

    final level = data['level'] as String?;
    final title = level == null || level.isEmpty
        ? vendorTitle
        : '$vendorTitle ${level[0].toUpperCase()}${level.substring(1)}';

    int? mcpPct, mcpReset, hour5Pct, hour5Reset, weeklyPct, weeklyReset;
    for (final limit in limits) {
      if (limit is! Map<String, dynamic>) continue;
      final pct = limit['percentage'];
      if (pct is! int) continue;
      final nrt = limit['nextResetTime'];
      final reset = nrt is int ? nrt : null;
      final type = limit['type'] as String?;
      if (type == 'TIME_LIMIT') {
        mcpPct = pct;
        mcpReset = reset;
      } else if (type == 'TOKENS_LIMIT') {
        final unit = limit['unit'] is int ? limit['unit'] as int : 0;
        final number = limit['number'] is int ? limit['number'] as int : 0;
        if (unit == 3 && number == 5) {
          hour5Pct = pct;
          hour5Reset = reset;
        } else {
          weeklyPct = pct;
          weeklyReset = reset;
        }
      }
    }

    final items = <UsageItem>[
      if (hour5Pct != null) UsageItem('token5h', hour5Pct.toDouble(), hour5Reset),
      if (weeklyPct != null) UsageItem('tokenWeekly', weeklyPct.toDouble(), weeklyReset),
      if (mcpPct != null) UsageItem('mcpMonthly', mcpPct.toDouble(), mcpReset),
    ];
    if (items.isEmpty) {
      return UsageResult(title, [], '查询失败，未找到数据');
    }
    return UsageResult(title, items, null);
  } catch (_) {
    return const UsageResult('智谱', [], '查询失败，未找到数据');
  }
}
```

创建 `lib/services/bigmodel_usage_provider.dart`：

```dart
import 'package:http/http.dart' as http;
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/services/usage_provider.dart';
import 'package:codingplan_refresh/services/usage_parser.dart';

class BigmodelUsageProvider implements UsageProvider {
  final String apiKey;
  final LogService log;
  BigmodelUsageProvider(this.apiKey, this.log);

  static const _url = 'https://open.bigmodel.cn/api/monitor/usage/quota/limit';

  @override
  Future<UsageResult> query() async {
    if (apiKey.trim().isEmpty) {
      return const UsageResult('智谱', [], '查询失败，未找到数据');
    }
    try {
      log.append('========== [Usage Request] ==========\nGET $_url\nAuthorization: ***');
      final response = await http.get(Uri.parse(_url), headers: {
        'Authorization': apiKey,
      }).timeout(const Duration(seconds: 120));
      log.append('========== [Usage Response] ${response.statusCode} ==========');
      log.append(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const UsageResult('智谱', [], '查询失败，未找到数据');
      }
      return parseBigmodelUsage(response.body);
    } catch (_) {
      return const UsageResult('智谱', [], '查询失败，未找到数据');
    }
  }
}
```

- [ ] **Step 3: 适配 usage_parser_test.dart**

打开 `test/services/usage_parser_test.dart`，把旧 `parseBigmodelUsage(body)` 返回 `UsageInfo` 的断言改为 `UsageResult`：

```dart
final r = parseBigmodelUsage(body);
expect(r.errorMessage, isNull);
expect(r.vendorTitle, '智谱 Vip');
expect(r.items.length, 3);
expect(r.items[0].labelKey, 'token5h');
expect(r.items[0].percentage, 34);
expect(r.items[1].labelKey, 'tokenWeekly');
expect(r.items[2].labelKey, 'mcpMonthly');
// 缺 data → errorMessage
expect(parseBigmodelUsage('{"msg":"x"}').errorMessage, '查询失败，未找到数据');
```

- [ ] **Step 4: 运行测试**

```bash
flutter test test/services/usage_parser_test.dart
```

期望：PASS。

- [ ] **Step 5: 从 LlmService 移除 queryBigmodelUsage**

打开 `lib/services/llm_service.dart`，删除 `queryBigmodelUsage` 方法（已搬入 `BigmodelUsageProvider`）和 `_usageUrl` 常量。保留 `askStream`/`processSseLines`/`LlmException`。同步删除 `test/services/llm_service_test.dart` 里若有 queryBigmodelUsage 相关测试（保留 processSseLines 测试）。

- [ ] **Step 6: 全套测试 + Commit**

```bash
flutter test
git add codingplan_refresh/lib/services/usage_provider.dart codingplan_refresh/lib/services/bigmodel_usage_provider.dart codingplan_refresh/lib/services/usage_parser.dart codingplan_refresh/lib/services/llm_service.dart codingplan_refresh/test/services/usage_parser_test.dart codingplan_refresh/test/services/llm_service_test.dart
git commit -m "feat(usage): UsageProvider 抽象 + 智谱迁移为 BigmodelUsageProvider，解析返回 UsageResult"
```

---

### Task 3: 火山方舟 arkcli provider

**Files:**
- Create: `codingplan_refresh/lib/services/volc_ark_usage_provider.dart`
- Test: `codingplan_refresh/test/services/volc_ark_usage_provider_test.dart`

**Interfaces:**
- Consumes: `UsageProvider`、`dart:io` Process
- Produces: `VolcArkUsageProvider() implements UsageProvider`——cmd 调 `arkcli usage plan`，10s 超时，解析 periods，失败细化。

- [ ] **Step 1: 写失败测试**

创建 `test/services/volc_ark_usage_provider_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/volc_ark_usage_provider.dart';

void main() {
  test('成功解析 periods → token5h/weekly/monthly', () async {
    const stdout = '''
{
  "viewer": {"user_name": "x"},
  "items": [{"product": "coding-plan", "edition": "personal", "subscribed": true,
    "periods": [
      {"label": "session", "percent": 18.2, "reset_at": 1782478364000},
      {"label": "weekly", "percent": 49.7, "reset_at": 1782662400000},
      {"label": "monthly", "percent": 40.1, "reset_at": 1784303999000}
    ], "updated_at": 1782464268}]
}''';
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async => stdout);
    final r = await provider.query();
    expect(r.errorMessage, isNull);
    expect(r.vendorTitle, '火山方舟 Personal');
    expect(r.items.map((i) => i.labelKey).toList(), ['token5h', 'tokenWeekly', 'tokenMonthly']);
    expect(r.items[0].percentage, closeTo(18.2, 0.01));
  });

  test('arkcli 返回 ok:false → 显示 error.message', () async {
    const stdout = '{"ok":false,"error":{"type":"error","message":"please run arkcli auth login"}}';
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async => stdout);
    final r = await provider.query();
    expect(r.items, isEmpty);
    expect(r.errorMessage, 'please run arkcli auth login');
  });

  test('arkcli 未安装（ProcessException）→ 提示未安装', () async {
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async {
      throw ProcessException('arkcli', args, '命令不存在');
    });
    final r = await provider.query();
    expect(r.errorMessage, contains('arkcli 未安装'));
  });

  test('超时 → 提示查询超时', () async {
    final provider = VolcArkUsageProvider(runner: ({required List<String> args, required Duration timeout}) async {
      throw TimeoutException('timed out', timeout);
    });
    final r = await provider.query();
    expect(r.errorMessage, '查询超时');
  });
}
```

- [ ] **Step 2: 运行确认失败**

```bash
flutter test test/services/volc_ark_usage_provider_test.dart
```

期望：FAIL（VolcArkUsageProvider 未定义）。

- [ ] **Step 3: 实现 provider**

创建 `lib/services/volc_ark_usage_provider.dart`：

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/usage_provider.dart';

/// 火山方舟用量：通过本地 arkcli 子进程查询 `arkcli usage plan`，10s 超时。
/// runner 抽象便于测试注入（生产用默认 _realRunner 调 Process.start）。
typedef ArkRunner = Future<String> Function({required List<String> args, required Duration timeout});

class VolcArkUsageProvider implements UsageProvider {
  final ArkRunner runner;
  VolcArkUsageProvider({ArkRunner? runner}) : runner = runner ?? _realRunner;

  static Future<String> _realRunner({required List<String> args, required Duration timeout}) async {
    // Windows 上 arkcli 是 .cmd；走 runInShell 让 shell 解析。
    final result = await Process.run('arkcli', args, runInShell: true)
        .timeout(timeout, onTimeout: () => throw TimeoutException('arkcli timeout', timeout));
    if (result.exitCode != 0) {
      // 进程失败（含超时杀掉）：stderr 当失败描述
      throw ProcessException('arkcli', args, result.stderr.toString());
    }
    return result.stdout.toString();
  }

  @override
  Future<UsageResult> query() async {
    try {
      final stdout = await runner(args: ['usage', 'plan'], timeout: const Duration(seconds: 10));
      return _parse(stdout);
    } on ProcessException catch (e) {
      final msg = e.message;
      // arkcli 未安装（命令找不到）
      if (msg.contains('命令找不到') || msg.contains('not found') || msg.contains('系统找不到') || e.toString().contains('No such file') || e.errorCode == 2) {
        return const UsageResult('火山方舟', [], 'arkcli 未安装，参考 README');
      }
      // 进程失败但 arkcli 存在（如未登录）→ 尝试解析 stdout/stderr 里的 JSON
      return UsageResult('火山方舟', [], msg.isEmpty ? '查询失败，未找到数据' : msg);
    } on TimeoutException {
      return const UsageResult('火山方舟', [], '查询超时');
    } catch (_) {
      return const UsageResult('火山方舟', [], '查询失败，未找到数据');
    }
  }

  UsageResult _parse(String stdout) {
    try {
      final doc = jsonDecode(stdout) as Map<String, dynamic>;
      // ok:false → error.message
      if (doc['ok'] == false) {
        final err = doc['error'];
        final msg = err is Map ? (err['message'] as String? ?? '查询失败，未找到数据') : '查询失败，未找到数据';
        return UsageResult('火山方舟', [], msg);
      }
      final items = doc['items'] as List;
      if (items.isEmpty) return const UsageResult('火山方舟', [], '查询失败，未找到数据');
      final first = items[0] as Map<String, dynamic>;
      final edition = first['edition'] as String? ?? '';
      final title = edition.isEmpty
          ? '火山方舟'
          : '火山方舟 ${edition[0].toUpperCase()}${edition.substring(1)}';
      final periods = first['periods'] as List? ?? [];
      final usageItems = <UsageItem>[];
      for (final p in periods) {
        if (p is! Map<String, dynamic>) continue;
        final label = p['label'] as String?;
        final percent = p['percent'];
        final resetAt = p['reset_at'];
        if (label == null || percent is! num) continue;
        final key = {
          'session': 'token5h',
          'weekly': 'tokenWeekly',
          'monthly': 'tokenMonthly',
        }[label];
        if (key == null) continue;
        usageItems.add(UsageItem(key, percent.toDouble(), resetAt is int ? resetAt : null));
      }
      if (usageItems.isEmpty) return UsageResult(title, [], '查询失败，未找到数据');
      return UsageResult(title, usageItems, null);
    } catch (_) {
      return const UsageResult('火山方舟', [], '查询失败，未找到数据');
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/volc_ark_usage_provider_test.dart
```

期望：4 测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/services/volc_ark_usage_provider.dart codingplan_refresh/test/services/volc_ark_usage_provider_test.dart
git commit -m "feat(usage): 火山方舟 arkcli provider（cmd/10s超时/失败细化）"
```

---

### Task 4: UsageFrame 组件（legend 框）

**Files:**
- Create: `codingplan_refresh/lib/ui/widgets/usage_frame.dart`
- Test: `codingplan_refresh/test/ui/widgets/usage_frame_test.dart`

**Interfaces:**
- Consumes: `UsageResult`/`UsageItem`（Task 1）、`LocalizationService`
- Produces: `UsageFrame({required UsageResult result, required LocalizationService l10n, required String Function(int?) resetText})`——legend 框，动态行 + 最小高度 + errorMessage。

- [ ] **Step 1: 写 widget test**

创建 `test/ui/widgets/usage_frame_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/widgets/usage_frame.dart';

void main() {
  testWidgets('成功多行：显示标题 + 各行 label', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = UsageResult('智谱 Pro', [
      UsageItem('token5h', 34, null),
      UsageItem('mcpMonthly', 12, null),
    ], null);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: (_) => ''))));
    await tester.pump();
    expect(find.text('智谱 Pro'), findsOneWidget);
    expect(find.text('Token(5H)'), findsOneWidget);
    expect(find.text('MCP(月)'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
  });

  testWidgets('失败：显示 errorMessage', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    final result = const UsageResult('火山方舟', [], 'arkcli 未安装，参考 README');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UsageFrame(result: result, l10n: l10n, resetText: (_) => ''))));
    await tester.pump();
    expect(find.text('arkcli 未安装，参考 README'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

```bash
flutter test test/ui/widgets/usage_frame_test.dart
```

- [ ] **Step 3: 实现 UsageFrame**

创建 `lib/ui/widgets/usage_frame.dart`：

```dart
import 'package:flutter/material.dart';
import '../../models/usage_info.dart';
import '../../services/localization_service.dart';

/// 单个 provider 的用量框：fieldset legend 风格，标题压在上边线。
/// 成功显示 items 各行（label + 重置 + 百分比着色）；失败/无数据显示 errorMessage。
/// 最小高度 = 一行（items 空也不塌陷）。
class UsageFrame extends StatelessWidget {
  final UsageResult result;
  final LocalizationService l10n;
  final String Function(int? resetAtMs) resetText; // 由 main_page 注入（含本地化 + DateFormat）

  const UsageFrame({
    super.key,
    required this.result,
    required this.l10n,
    required this.resetText,
  });

  static Color pctColor(double p) {
    if (p >= 80) return const Color(0xFFFF0000);
    if (p >= 50) return const Color(0xFFFF8C00);
    return const Color(0xFF007ACC);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      // 框（带边框 + 最小高度）
      Container(
        constraints: const BoxConstraints(minHeight: 28),
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF555555)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: result.items.isEmpty
            ? Center(
                child: Text(result.errorMessage ?? '',
                    style: const TextStyle(color: Color(0xFF999999), fontSize: 11)))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: result.items.map((it) => _row(it)).toList(),
              ),
      ),
      // legend 标题（压在上边线）
      Positioned(
        left: 10,
        top: 0,
        child: Container(
          color: const Color(0xFF2D2D30), // 遮住边框，形成 legend 缺口
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(result.vendorTitle,
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
        ),
      ),
    ]);
  }

  Widget _row(UsageItem it) {
    final pct = it.percentage;
    final reset = it.resetAtMs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        SizedBox(
            width: 80,
            child: Text(l10n.t(it.labelKey),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12))),
        Expanded(
            child: Center(
                child: Text(reset == null ? '' : resetText(reset),
                    style: const TextStyle(color: Color(0xFF999999), fontSize: 11)))),
        SizedBox(
            width: 50,
            child: Text('${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(color: pctColor(pct), fontSize: 16, fontWeight: FontWeight.bold))),
      ]),
    );
  }
}
```

- [ ] **Step 4: 运行确认通过 + Commit**

```bash
flutter test test/ui/widgets/usage_frame_test.dart
git add codingplan_refresh/lib/ui/widgets/usage_frame.dart codingplan_refresh/test/ui/widgets/usage_frame_test.dart
git commit -m "feat(ui): UsageFrame legend 框（标题/动态行/最小高度/失败显示）"
```

---

### Task 5: 配置面板（多组，拖动排序）

**Files:**
- Create: `codingplan_refresh/lib/ui/widgets/config_panel.dart`
- Test: `codingplan_refresh/test/ui/widgets/config_panel_test.dart`

**Interfaces:**
- Consumes: `AppConfig`/`ProviderConfig`（Task 1）、`LocalizationService`
- Produces: `ConfigPanel({required AppConfig initial, required LocalizationService l10n, required void Function(AppConfig next, bool langChanged) onSave, required VoidCallback onCancel})`——ReorderableListView 拖动 + 新增/删除(确认)/编辑 + 语言。

- [ ] **Step 1: 写 widget test（关键交互）**

创建 `test/ui/widgets/config_panel_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/ui/widgets/config_panel.dart';

void main() {
  testWidgets('新增一个 provider', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    var saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [ProviderConfig(id: 'a', name: '智谱')]),
      l10n: l10n,
      onSave: (next, _) => saved = next,
      onCancel: () {},
    ))));
    await tester.pump();
    await tester.tap(find.text('新增'));
    await tester.pump();
    expect(find.text('新配置'), findsOneWidget); // 追加默认名
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saved.providers.length, 2);
  });

  testWidgets('删除需确认', (tester) async {
    final l10n = LocalizationService()..initialize('zh');
    var saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ConfigPanel(
      initial: AppConfig(providers: [ProviderConfig(id: 'a', name: '智谱'), ProviderConfig(id: 'b', name: '火山')]),
      l10n: l10n,
      onSave: (next, _) => saved = next,
      onCancel: () {},
    ))));
    await tester.pump();
    await tester.tap(find.text('删除').first);
    await tester.pump();
    expect(find.text('确认删除'), findsOneWidget); // 确认对话框
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saved.providers.length, 1);
  });
}
```

- [ ] **Step 2: 实现 ConfigPanel**

创建 `lib/ui/widgets/config_panel.dart`：

```dart
import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/localization_service.dart';

/// 多组配置面板：ReorderableListView 拖动排序 + 新增/删除(确认)/编辑 + 语言。
/// 拖动用 ReorderableListView 自带拖拽（长按 handle）。
class ConfigPanel extends StatefulWidget {
  final AppConfig initial;
  final LocalizationService l10n;
  final void Function(AppConfig next, bool langChanged) onSave;
  final VoidCallback onCancel;
  const ConfigPanel({
    super.key,
    required this.initial,
    required this.l10n,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<ConfigPanel> createState() => _ConfigPanelState();
}

class _ConfigPanelState extends State<ConfigPanel> {
  late List<ProviderConfig> _providers;
  late int _selectedIdx; // 当前编辑的 provider 索引
  late int _langIndex; // 0 auto 1 zh 2 en
  late TextEditingController _name, _url, _key, _model;
  int _idCounter = 0;

  @override
  void initState() {
    super.initState();
    _providers = List.of(widget.initial.providers);
    _selectedIdx = _providers.isEmpty ? -1 : 0;
    _langIndex = (widget.initial.language ?? 'auto') == 'zh'
        ? 1
        : (widget.initial.language == 'en' ? 2 : 0);
    _name = TextEditingController();
    _url = TextEditingController();
    _key = TextEditingController();
    _model = TextEditingController();
    if (_selectedIdx >= 0) _loadFields(_selectedIdx);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _loadFields(int idx) {
    final p = _providers[idx];
    _name.text = p.name;
    _url.text = p.apiUrl;
    _key.text = p.apiKey;
    _model.text = p.model;
  }

  void _saveCurrentFields() {
    if (_selectedIdx < 0 || _selectedIdx >= _providers.length) return;
    _providers[_selectedIdx] = _providers[_selectedIdx].copyWith(
      name: _name.text, apiUrl: _url.text, apiKey: _key.text, model: _model.text,
    );
  }

  String _newId() => 'cfg_${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}';

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // provider 列表（可拖动）
        SizedBox(
          height: 140,
          child: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorder: (oldI, newI) {
              setState(() {
                _saveCurrentFields();
                if (newI > oldI) newI -= 1;
                final p = _providers.removeAt(oldI);
                _providers.insert(newI, p);
                // 重新定位选中
                final selId = _selectedIdx >= 0 ? _providers[newI].id : null;
                _selectedIdx = _providers.indexWhere((e) => e.id == selId);
                if (_selectedIdx >= 0) _loadFields(_selectedIdx);
              });
            },
            children: [
              for (int i = 0; i < _providers.length; i++)
                ListTile(
                  key: ValueKey(_providers[i].id),
                  dense: true,
                  selected: i == _selectedIdx,
                  selectedTileColor: const Color(0xFF007ACC).withValues(alpha: 0.3),
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle, color: Color(0xFF888888), size: 18),
                  ),
                  title: Text('${_providers[i].name} (${_vendorOf(_providers[i].apiUrl)})',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 16, color: Color(0xFFAAAAAA)),
                    onPressed: () => _confirmDelete(i),
                  ),
                  onTap: () { _saveCurrentFields(); setState(() { _selectedIdx = i; _loadFields(i); }); },
                ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () {
            _saveCurrentFields();
            setState(() {
              final p = ProviderConfig(id: _newId(), name: '新配置');
              _providers.add(p);
              _selectedIdx = _providers.length - 1;
              _loadFields(_selectedIdx);
            });
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('新增', style: TextStyle(fontSize: 12)),
        ),
        const Divider(color: Color(0xFF555555), height: 12),
        // 编辑表单
        if (_selectedIdx >= 0) ...[
          _field('名称', _name),
          _field('API URL', _url, hint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions'),
          _field('API Key', _key, hint: 'sk-xxx', obscure: true),
          _field('Model', _model, hint: 'glm-5.1 / ep-xxx'),
        ],
        const SizedBox(height: 6),
        Text(l.t('languageLabel'), style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
        Row(children: [_langBtn(0, l.t('languageAuto')), _langBtn(1, l.t('languageZh')), _langBtn(2, l.t('languageEn'))]),
        const Spacer(),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: _onSave, child: Text(l.t('save')))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(onPressed: widget.onCancel, child: Text(l.t('cancel')))),
        ]),
      ]),
    );
  }

  void _onSave() {
    _saveCurrentFields();
    final lang = _langIndex == 1 ? 'zh' : (_langIndex == 2 ? 'en' : 'auto');
    final next = AppConfig(
      providers: _providers,
      isAlwaysOnTop: widget.initial.isAlwaysOnTop,
      language: lang,
      lastTriggerKeys: widget.initial.lastTriggerKeys,
    );
    widget.onSave(next, lang != (widget.initial.language ?? 'auto'));
  }

  void _confirmDelete(int idx) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('确认删除', style: TextStyle(fontSize: 14)),
      content: Text('删除「${_providers[idx].name}」？', style: const TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () { Navigator.pop(ctx); setState(() { _providers.removeAt(idx); if (_selectedIdx >= _providers.length) _selectedIdx = _providers.length - 1; if (_selectedIdx >= 0) _loadFields(_selectedIdx); }); }, child: const Text('确认')),
      ],
    ));
  }

  String _vendorOf(String url) {
    if (url.contains('bigmodel.cn')) return '智谱';
    if (url.contains('ark.cn-beijing.volces.com')) return '火山方舟';
    return '未知';
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool obscure = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
      TextField(controller: c, obscureText: obscure, style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(filled: true, fillColor: const Color(0xFF3C3C3C),
          hintText: hint, hintStyle: const TextStyle(color: Color(0xFF666666)),
          isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: InputBorder.none)),
    ]);
  }

  Widget _langBtn(int idx, String text) {
    final sel = _langIndex == idx;
    return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ElevatedButton(style: ElevatedButton.styleFrom(
          backgroundColor: sel ? const Color(0xFF007ACC) : const Color(0xFF3C3C3C),
          foregroundColor: Colors.white, padding: EdgeInsets.zero),
        onPressed: () => setState(() => _langIndex = idx),
        child: Text(text, style: const TextStyle(fontSize: 12)))));
  }
}
```

- [ ] **Step 3: 运行 + Commit**

```bash
flutter test test/ui/widgets/config_panel_test.dart
git add codingplan_refresh/lib/ui/widgets/config_panel.dart codingplan_refresh/test/ui/widgets/config_panel_test.dart
git commit -m "feat(ui): 多组配置面板（ReorderableListView 拖动/新增/删除确认/编辑）"
```

---

### Task 6: 主窗口 mini 重构（多框 + ☰ 菜单 + 高度自适应）

**Files:**
- Modify: `codingplan_refresh/lib/ui/main_page.dart`（大改：去三角/折叠、☰菜单、多框、高度自适应）
- Create: `codingplan_refresh/lib/ui/widgets/result_panel.dart`（手动触发面板：下拉选 provider + 结果区，Task 7 用）
- Test: `codingplan_refresh/test/ui/main_page_test.dart`（重写：适配多框 + 菜单）

**Interfaces:**
- Consumes: `AppConfig`（多组）、`UsageFrame`（Task 4）、`WindowController`、各 service
- Produces: 改造后的 `MainPage`——mini 多框 + ☰ 菜单 + 置顶 + 高度自适应。

> 本任务**只做 mini 态布局**（多框 + 菜单 + 置顶 + 高度自适应），LLL 触发与放大态分别由 Task 7/8 接入。本任务先把 mini 跑起来（☰ 菜单的"设置/手动触发"先留空回调，Task 7/8 接）。

- [ ] **Step 1: 重写 main_page.dart（mini 多框版）**

完整替换 `lib/ui/main_page.dart` 的 `_MainPageState`（保留 MainPage widget 声明 + import，重写 state + build）。关键结构：

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_config.dart';
import '../models/usage_info.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import '../services/localization_service.dart';
import '../services/log_service.dart';
import '../services/scheduler_service.dart';
import '../services/usage_provider.dart';
import '../services/bigmodel_usage_provider.dart';
import '../services/volc_ark_usage_provider.dart';
import '../platform/window_controller.dart';
import 'widgets/usage_frame.dart';

class MainPage extends StatefulWidget {
  final AppConfig config;
  final ConfigService configService;
  final LlmService llm;
  final LogService log;
  final LocalizationService l10n;
  final WindowController window;
  const MainPage({super.key, required this.config, required this.configService, required this.llm, required this.log, required this.l10n, required this.window});
  @override
  State<MainPage> createState() => _MainPageState();
}

/// 单个 provider 的运行时结果状态（定时与手动共享）。
class ResultState {
  String text = '';
  String header = '';
  bool isBusy = false;
  bool isRetrying = false;
}

class _MainPageState extends State<MainPage> {
  late AppConfig _config;
  // key = provider.id
  final Map<String, UsageResult> _usages = {};
  final Map<String, ResultState> _results = {};
  Timer? _usageTimer;
  double _lastContentHeight = 0;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    for (final p in _config.providers) {
      _results[p.id] = ResultState();
    }
    _usageTimer = Timer.periodic(const Duration(seconds: 60), (_) => _queryAllUsage());
    _queryAllUsage();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
  }

  @override
  void dispose() {
    _usageTimer?.cancel();
    super.dispose();
  }

  /// 厂商识别 → 返回该 provider 的 UsageProvider（未知返回 null）。
  UsageProvider? _providerFor(ProviderConfig p) {
    final url = p.apiUrl;
    if (url.contains('bigmodel.cn')) return BigmodelUsageProvider(p.apiKey, widget.log);
    if (url.contains('ark.cn-beijing.volces.com')) return VolcArkUsageProvider();
    return null;
  }

  Future<void> _queryAllUsage() async {
    for (final p in _config.providers) {
      final provider = _providerFor(p);
      if (provider == null) {
        _usages[p.id] = const UsageResult('未知厂商', [], '未知厂商，不支持用量查询');
        continue;
      }
      final result = await provider.query();
      if (!mounted) return;
      setState(() => _usages[p.id] = result);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _resizeToContent());
  }

  /// 测量内容高度 → setSize（高度自适应，仅超阈值时调避免抖动）。
  void _resizeToContent() {
    final ctx = context;
    if (!mounted) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final h = box.size.height;
    if ((h - _lastContentHeight).abs() > 2) {
      _lastContentHeight = h;
      widget.window.setHeight(ConfigService.expandedWidth, h);
    }
  }

  String _resetText(int? ms) {
    if (ms == null || ms < 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final fmt = isToday ? DateFormat('HH:mm') : DateFormat('MM/dd HH:mm');
    return widget.l10n.t(isToday ? 'resetToday' : 'resetOther').fmt([dt]);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: Column(children: [
        // 顶部栏：☰ 菜单 + 置顶
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu, color: Color(0xFFAAAAAA), size: 20),
              tooltip: '',
              onSelected: (v) {
                // Task 7/8 接入：'config' → 打开配置放大态；'trigger' → 打开手动触发放大态
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'config', child: Text(l.t('settings'))),
                PopupMenuItem(value: 'trigger', child: Text(l.t('manualTrigger'))),
              ],
            ),
            const Spacer(),
            Checkbox(
              value: _config.isAlwaysOnTop,
              onChanged: (v) {
                setState(() => _config.isAlwaysOnTop = v ?? false);
                widget.window.setAlwaysOnTop(_config.isAlwaysOnTop);
                widget.configService.save(_config);
              },
            ),
            Text(l.t('pinLabel'), style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(width: 4),
          ]),
        ),
        // 用量框列表（每 provider 一个，ScrollView 可滚）
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _config.providers.map((p) => UsageFrame(
                  result: _usages[p.id] ?? const UsageResult('', [], null),
                  l10n: l,
                  resetText: _resetText,
                )).toList(),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
```

> 同时需在 `localization_service.dart` `_table` 加键：
> `'settings': {'zh':'设置','en':'Settings'}`。

- [ ] **Step 2: 删除旧 widgets 引用**

`main_page.dart` 不再 import `usage_row.dart`/`config_overlay.dart`/`result_overlay.dart`（旧浮层）。这些文件可保留（Task 7/8 决定是否删），但 main_page 不引用。

- [ ] **Step 3: 适配 main_page_test.dart**

重写 `test/ui/main_page_test.dart`（旧测折叠三角/置顶已不适用）：

```dart
// 验证：多 provider 渲染多个 UsageFrame；☰ 菜单点击弹出菜单项；
// 置顶 checkbox 触发 setAlwaysOnTop。
// 用 FakeWindowController（extends WindowController override），url 用非 bigmodel/ark 避免 _queryAllUsage 走 provider（_providerFor 返回 null → 显示「未知厂商」）。
```
（实现时按此模式补全断言：providers=[a,b] → 2 个 UsageFrame；Checkbox → setAlwaysOnTop。）

- [ ] **Step 4: 全套测试 + build**

```bash
flutter test
flutter build windows --debug
```

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/ui/main_page.dart codingplan_refresh/lib/services/localization_service.dart codingplan_refresh/test/ui/main_page_test.dart
git commit -m "feat(ui): 主窗口 mini 多框（去三角/☰菜单/置顶/高度自适应）"
```

---

### Task 7: LLM 触发（定时遍历所有 + 手动面板下拉选 provider）

**Files:**
- Create: `codingplan_refresh/lib/ui/widgets/result_panel.dart`（手动触发面板：下拉选 provider + 结果区）
- Modify: `codingplan_refresh/lib/ui/main_page.dart`（接入定时遍历 + 手动面板触发）
- Test: `codingplan_refresh/test/ui/widgets/result_panel_test.dart`

**Interfaces:**
- Consumes: `LlmService.askStream`、per-provider `ResultState`（Task 6）
- Produces: 定时遍历所有 providers 调用（更新各自 ResultState + lastTriggerKeys）；手动面板 `ResultPanel({required Map<String,ResultState>, required List<ProviderConfig>, ...})` 下拉选 + 触发。

- [ ] **Step 1: 实现 result_panel.dart（手动面板）**

创建 `lib/ui/widgets/result_panel.dart`：

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/llm_service.dart';
import '../../services/localization_service.dart';

/// 手动触发面板：下拉选 provider + 结果区。
/// 调用方传入 onSelect/onTrigger 回调，面板内维护当前选中 provider.id。
class ResultPanel extends StatefulWidget {
  final List<ProviderConfig> providers;
  final String Function(String providerId) getText;     // 取该 provider 当前 resultText
  final String Function(String providerId) getHeader;
  final Future<bool> Function(String providerId) onTrigger; // 触发该 provider，返回成功？
  final LocalizationService l10n;
  const ResultPanel({super.key, required this.providers, required this.getText, required this.getHeader, required this.onTrigger, required this.l10n});
  @override
  State<ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends State<ResultPanel> {
  late String _selectedId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.providers.isEmpty ? '' : widget.providers.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    if (widget.providers.isEmpty) {
      return Center(child: Text('未配置任何模型', style: const TextStyle(color: Color(0xFF999999))));
    }
    final selected = widget.providers.firstWhere((p) => p.id == _selectedId, orElse: () => widget.providers.first);
    final text = widget.getText(_selectedId);
    final header = widget.getHeader(_selectedId);
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          DropdownButton<String>(
            value: _selectedId,
            dropdownColor: const Color(0xFF2D2D30),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            items: widget.providers.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
            onChanged: (v) { if (v != null) setState(() => _selectedId = v); },
          ),
          const Spacer(),
          IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close, size: 16, color: Color(0xFFAAAAAA))),
        ]),
        Text(header, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
        const SizedBox(height: 4),
        Expanded(child: Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.all(6),
          child: SingleChildScrollView(child: Text(text.isEmpty ? l.t('waitingPlaceholder') : text,
            style: TextStyle(color: text.isEmpty ? const Color(0xFF555555) : const Color(0xFFCCCCCC), fontSize: 11))),
        )),
        const SizedBox(height: 6),
        ElevatedButton(
          onPressed: _busy ? null : () async { setState(() => _busy = true); await widget.onTrigger(_selectedId); if (mounted) setState(() => _busy = false); },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007ACC)),
          child: Text(l.t('manualTriggerPopup')),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 2: main_page 接入定时遍历 + 触发逻辑**

在 `main_page.dart` `_MainPageState` 增加：

```dart
Timer? _triggerTimer;
Timer? _retryGuard; // 占位，实际用 per-provider isRetrying

@override
void initState() {
  // ... 已有 ...
  _triggerTimer = Timer.periodic(const Duration(seconds: 6), (_) => _onTriggerTick());
}
@override
void dispose() { _triggerTimer?.cancel(); _usageTimer?.cancel(); super.dispose(); }

void _onTriggerTick() {
  // 全局时间触发键（沿用单值语义即可：整点命中后所有 provider 都触发一次）
  final r = SchedulerService.checkTrigger(DateTime.now(), _globalTriggerKey());
  if (!r.trigger) return;
  _setGlobalTriggerKey(r.key);
  widget.configService.save(_config);
  // 遍历所有 providers，各自独立重试
  for (final p in _config.providers) {
    _callLlmWithRetry(p.id);
  }
}

String _globalTriggerKey() => _config.lastTriggerKeys['__global__'] ?? '';
void _setGlobalTriggerKey(String k) => _config.lastTriggerKeys['__global__'] = k;

/// per-provider 单次调用（节流 50ms，更新该 provider ResultState）。
Future<bool> _callLlmOnce(String providerId, {required bool manual}) async {
  final p = _config.providers.firstWhere((e) => e.id == providerId, orElse: () => _config.providers.first);
  final rs = _results[providerId]!;
  if (rs.isBusy) return false;
  rs.isBusy = true;
  setState(() {});
  final buf = StringBuffer();
  Timer? flushTimer;
  void flush() { flushTimer = null; if (mounted) setState(() {}); }
  try {
    rs.text = widget.l10n.t('loading');
    final model = p.model.isEmpty ? 'glm-5.1' : p.model;
    final prompt = '${widget.l10n.t('jokePrompt')}\nseed=${DateTime.now().millisecondsSinceEpoch % 10000}';
    await widget.llm.askStream(
      apiUrl: p.apiUrl, apiKey: p.apiKey, model: model, question: prompt,
      onChunk: (c) {
        if (buf.isEmpty) rs.text = '';
        buf.write(c);
        rs.text = buf.toString();
        flushTimer ??= Timer(const Duration(milliseconds: 50), flush);
      },
    );
    if (mounted) {
      rs.header = widget.l10n.t('resultTimestamp').fmt([DateTime.now()]);
      setState(() {});
    }
    return true;
  } catch (e) {
    if (!manual) {
      // 自动失败清全局 key 允许下次重试（与旧版一致）
      _setGlobalTriggerKey('');
      widget.configService.save(_config);
    }
    rs.text = e is LlmException ? widget.l10n.t(e.l10nKey).fmt(e.args) : widget.l10n.t('errorMessage').fmt(['$e']);
    widget.log.append('[Error] $e');
    if (mounted) setState(() {});
    return false;
  } finally {
    rs.isBusy = false;
    if (mounted) setState(() {});
  }
}

/// per-provider 重试循环（3 次×5s），用 rs.isRetrying 防并发。
Future<void> _callLlmWithRetry(String providerId) async {
  final rs = _results[providerId]!;
  if (rs.isRetrying) return;
  rs.isRetrying = true;
  try {
    for (int attempt = 1; attempt <= 3; attempt++) {
      if (await _callLlmOnce(providerId, manual: false)) break;
      if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
    }
  } finally {
    rs.isRetrying = false;
  }
}
```

> 注意：`_results[providerId]!` 的 ResultState 需在 provider 列表变化时同步维护（新增/删除时在 config 保存后增删 _results）。本任务先保证固定列表场景正确。

- [ ] **Step 3: ☰ 菜单接入手动触发（放大态由 Task 8，本任务先在 mini 内显示面板占位）**

在 build 的 PopupMenuButton `onSelected` 里：

```dart
onSelected: (v) async {
  if (v == 'trigger') {
    // Task 8 接入放大态；此处先内联显示 panel（占位）
    await showDialog(context: context, builder: (_) => Dialog(
      child: SizedBox(width: 380, height: 460,
        child: ResultPanel(
          providers: _config.providers,
          getText: (id) => _results[id]?.text ?? '',
          getHeader: (id) => _results[id]?.header ?? '',
          onTrigger: (id) => _callLlmOnce(id, manual: true),
          l10n: widget.l10n,
        )),
    ));
  } else if (v == 'config') {
    // Task 8 接入 ConfigPanel 放大态
  }
},
```

> 本任务用 Dialog 占位（Task 8 改为真正的窗口放大态 + 边缘兼容）。

- [ ] **Step 4: 写 result_panel_test + 运行**

```dart
// test/ui/widgets/result_panel_test.dart
// 验证：下拉切换显示对应 provider 的 text；点触发调用 onTrigger。
```

```bash
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/ui/widgets/result_panel.dart codingplan_refresh/lib/ui/main_page.dart codingplan_refresh/test/ui/widgets/result_panel_test.dart
git commit -m "feat(trigger): 定时遍历所有 providers + 手动面板下拉选 provider（per-provider ResultState）"
```

---

### Task 8: 放大态（420×520）+ 屏幕边缘兼容

**Files:**
- Modify: `codingplan_refresh/lib/platform/window_controller.dart`（加放大/缩回 + 边缘兼容）
- Modify: `codingplan_refresh/lib/ui/main_page.dart`（☰ 菜单触发窗口放大 + ConfigPanel/ResultPanel 铺满放大区）

**Interfaces:**
- Consumes: `window_manager`、`ConfigPanel`（Task 5）、`ResultPanel`（Task 7）
- Produces: `WindowController.enlarge({required double w, required double h})`（放大 + 边缘平移）、`shrinkToContent()`（缩回 + 保留位置）。

- [ ] **Step 1: window_controller 加放大/缩回 + 边缘兼容**

在 `window_controller.dart` 增加（保留现有 setup/setHeight 等）：

```dart
/// 放大到目标尺寸，若超出屏幕工作区则平移窗口留屏内。
Future<void> enlarge({required double w, required double h}) async {
  final pos = await windowManager.getPosition();
  final sz = await windowManager.getSize();
  // 屏幕工作区：用 window_manager 的屏幕信息（无直接 API 时用 displayProvider）。
  // 简化：取主屏 size（无任务栏扣除作为首版；后续可接 screen_display 精修）。
  final screen = await _screenSize();
  double x = pos.dx, y = pos.dy;
  if (x + w > screen.width) x = (screen.width - w).clamp(0.0, screen.width);
  if (y + h > screen.height) y = (screen.height - h).clamp(0.0, screen.height);
  await windowManager.setPosition(Offset(x, y));
  await windowManager.setSize(Size(w, h));
}

Future<Size> _screenSize() async {
  // window_manager 0.5.x 无直接取屏 API；用 PlatformDispatcher 物理屏 / 逻辑屏。
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  return view.physicalSize / view.devicePixelRatio;
}

/// 缩回 mini（自适应高度，保留当前位置）。
Future<void> shrinkToContent(double contentHeight) async {
  await windowManager.setSize(Size(330, contentHeight));
}
```

> 需要 `import 'package:flutter/widgets.dart';`（Size/Offset/WidgetsBinding）。

- [ ] **Step 2: main_page 放大态用 enlarge + ConfigPanel/ResultPanel**

替换 Task 7 的 Dialog 占位为真正的窗口放大态：

```dart
bool _enlarged = false;
String? _enlargedMode; // 'config' / 'trigger'

Future<void> _openEnlarged(String mode) async {
  setState(() { _enlarged = true; _enlargedMode = mode; });
  await widget.window.enlarge(w: 420, h: 520);
}
Future<void> _closeEnlarged() async {
  setState(() { _enlarged = false; _enlargedMode = null; });
  await widget.window.shrinkToContent(_lastContentHeight);
}
```

build 的 body 改为：`_enlarged ? _buildEnlarged() : _buildMini()`。
- `_buildEnlarged()`：保留顶部栏（☰ + 置顶），下方放大区 = `_enlargedMode == 'config' ? ConfigPanel(...) : ResultPanel(...)`，铺满。
- ConfigPanel onSave/onCancel → `_closeEnlarged()`；ResultPanel 关闭 → `_closeEnlarged()`。

☰ 菜单 onSelected：
```dart
if (v == 'config') _openEnlarged('config');
else if (v == 'trigger') _openEnlarged('trigger');
```

- [ ] **Step 3: 测试 + build 验证**

```bash
flutter test
flutter build windows --debug
# 手动 flutter run -d windows 验证：菜单放大到 420×520、靠边缘时不溢出、关闭缩回
```

- [ ] **Step 4: Commit**

```bash
git add codingplan_refresh/lib/platform/window_controller.dart codingplan_refresh/lib/ui/main_page.dart
git commit -m "feat(ui): 放大态 420×520 + 屏幕边缘兼容（放大平移/缩回保留位置）"
```

---

### Task 9: README + 旧浮层清理 + 验收

**Files:**
- Create: `codingplan_refresh/README.md`（中文，替换 flutter create 默认英文）
- Modify: `README.md`（根，增补火山方舟 + 多组配置）
- Delete（若 Task 6 后无引用）: `codingplan_refresh/lib/ui/widgets/usage_row.dart`、`config_overlay.dart`、`result_overlay.dart`（旧浮层，已被 UsageFrame/ConfigPanel/ResultPanel 取代）

- [ ] **Step 1: 写 codingplan_refresh/README.md**

```markdown
# Coding Plan Time Refresh（Flutter 版）

定时调用 LLM 并在桌面常驻显示多厂商 API 用量百分比的小工具。

## 支持厂商
- **智谱 BigModel**（bigmodel.cn）：HTTP 查询用量配额。
- **火山方舟 Volcengine Ark**（ark.cn-beijing.volces.com）：通过本地 `arkcli` 工具查询用量。

## 火山方舟用量前置条件
火山方舟用量查询依赖官方 `arkcli` 命令行工具，请先安装并登录：
1. 安装 arkcli（参考 https://console.volcengine.com/ark/region:cn-beijing/docs/82379/2536875 ）
2. 执行 `arkcli auth login` 完成登录
3. 软件内通过 `arkcli usage plan` 自动查询

未安装/未登录时，火山方舟用量框会提示「arkcli 未安装，参考 README」。

## 配置
- 主界面 ☰ 菜单 → 设置：管理多个模型配置（长按拖动排序、新增、删除、编辑）。
- 每个配置填：名称、API URL、API Key、Model（智谱填模型名如 glm-5.1；火山填 endpoint id 如 ep-xxx）。
- 厂商由 API URL 自动识别。

## 构建
\`\`\`bash
flutter build windows --release
\`\`\`
```

- [ ] **Step 2: 根 README 增补**

在根 `README.md` 增加一节说明 Flutter 版（多厂商 + arkcli 前置条件 + 配置），与 MAUI 版说明并存（MAUI 版待 Task 15 下线，此处只增补 Flutter 版信息）。

- [ ] **Step 3: 清理旧浮层（确认无引用后删除）**

```bash
cd codingplan_refresh
# 确认 usage_row/config_overlay/result_overlay 无 import
grep -rn "usage_row\|config_overlay\|result_overlay" lib/ || echo "无引用，可删"
rm lib/ui/widgets/usage_row.dart lib/ui/widgets/config_overlay.dart lib/ui/widgets/result_overlay.dart
rm test/ui/main_page_test.dart  # 若旧测引用旧浮层已重写，确认新测存在
flutter test
flutter build windows --release
```

> 删除前确认 `lib/` 无引用（grep）。若仍有引用，先更新。

- [ ] **Step 4: 验收（手动 + 自动）**

- `flutter test` 全套通过。
- `flutter build windows --release` 通过。
- 手动 `flutter run -d windows` 验收：
  - mini 多框（配几个厂商显示几个）+ ☰ 菜单 + 置顶。
  - 设置放大态：新增/删除确认/拖动排序/编辑/保存。
  - 手动触发放大态：下拉选 provider + 触发 + 流式。
  - 边缘兼容：窗口拖到屏幕边缘再放大，不溢出。
  - 定时触发（到 01/07/13:00 或 mock）所有 providers 调用。
  - 火山方舟：装 arkcli → 用量显示；卸载/未登录 → 提示。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/README.md README.md
git rm codingplan_refresh/lib/ui/widgets/usage_row.dart codingplan_refresh/lib/ui/widgets/config_overlay.dart codingplan_refresh/lib/ui/widgets/result_overlay.dart 2>/dev/null || true
git add -A
git commit -m "docs+chore: README（火山arkcli/多组配置）+ 清理旧浮层"
```

---

## 实现顺序与闸口

```
T1 数据模型+迁移（闸口①：旧 config.dat 迁移到多组、往返正确）
  └─ T2 UsageProvider 抽象 + 智谱迁移（闸口②：parseBigmodelUsage 返回 UsageResult）
        └─ T3 火山 arkcli provider（闸口③：cmd/超时/失败细化单测过）
              └─ T4 UsageFrame（闸口④：legend 框 widget test 过）
                    └─ T5 配置面板多组（拖动/新增/删除确认 widget test 过）
                          └─ T6 主窗口 mini 多框（高度自适应）
                                └─ T7 LLM 触发 per-provider（定时遍历/手动下拉）
                                      └─ T8 放大态 + 边缘兼容
                                            └─ T9 README + 清理 + 验收
```

**硬闸口**：①旧配置迁移正确（否则老用户配置丢失）②③④单测全过 ⑤配置面板交互 widget test 过 ⑨手动验收（多框/放大/边缘/定时/火山）全过。

> **注意**：T6/T7/T8 都改 `main_page.dart`，需顺序执行（同文件）。T6 先建 mini 骨架，T7 接触发，T8 接放大态。每任务独立 build + 测试 + commit。
