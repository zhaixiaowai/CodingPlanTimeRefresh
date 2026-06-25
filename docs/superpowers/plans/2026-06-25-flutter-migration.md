# CodingPlanTimeRefresh MAUI→Flutter 迁移 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 .NET MAUI 桌面小工具 1:1 平移为 Flutter 桌面应用（Windows + macOS），编译产物 < 40 MB 且不依赖系统 WebView，兼容读取旧版加密配置。

**Architecture:** 单页面 Flutter 桌面应用。分层：`utils`（纯逻辑：AES/SSE）→ `models` → `services`（配置/日志/LLM/调度/本地化，纯 Dart 可单测）→ `platform`（窗口控制/单实例，封装平台差异）→ `ui`（渲染）。业务层只依赖 `platform` 抽象方法，不直接碰平台 API。

**Tech Stack:** Flutter (Dart) 桌面 stable；`window_manager`、`http`、`encrypt`、`path_provider`、`win32`（Windows 单实例 mutex）；测试用内置 `flutter_test`。

## Global Constraints

- **目标平台**：Windows 10（10.0.19041+）、macOS。Windows 任务在 Windows 机器执行；macOS 平台特定任务（Task 10/14 的 mac 部分）必须在 Mac + Xcode 环境执行。
- **配置兼容（关键）**：AES-256-CBC + PKCS7。
  - Key（Base64）= `Y2RmN2g5azNxUDZ5V0JuTG1SNXZpM3hYN2tybEk4SFg=`（32 字节）
  - IV（Base64）= `UGs0dTl2T3dxWjRuY2xmSA==`（16 字节）
  - 旧 `config.dat` 是**原始密文字节**（非 Base64 文本）。
- **配置 JSON 字段名（PascalCase，与旧版一致）**：`IsAlwaysOnTop`、`ApiUrl`、`ApiKey`、`Model`、`LastAutoTriggerKey`、`IsCollapsed`、`Language`。
- **触发时段**：`[(1,0),(7,0),(13,0),(19,0)]`；定时器 6s 轮询；命中后失败重试 **3 次，间隔 5s**。
- **用量轮询**：60s；仅当 `apiUrl` 含 `bigmodel.cn` 才查询；端点 `https://open.bigmodel.cn/api/monitor/usage/quota/limit`；`Authorization` 头**直接传 apiKey，无 Bearer 前缀**。
- **用量归类**：`type=="TIME_LIMIT"`→MCP 月限；`type=="TOKENS_LIMIT" && unit==3 && number==5`→5 小时限；其余 `TOKENS_LIMIT`→周限。
- **HTTP 超时**：120s。
- **百分比着色阈值**：≥80 红（`Color(0xFFFF0000)`）、≥50 橙（`Color(0xFFFF8C00)`）、其余蓝（`Color(0xFF007ACC)`）。
- **窗口尺寸**：宽 330；展开高 318；折叠高 120（无周行）/ 142（有周行）。
- **单实例互斥体名**（Windows）：`CodingPlanTimeRefresh_SingleInstance`。
- **体积上限**：各平台单份发布产物 < 40 MB。
- **旧版**：迁移期间 MAUI 项目（`CodingPlanTimeRefresh/`）保留，Task 15 验证通过后才删。
- **新子目录**：`codingplan_refresh/`（Dart 包名规范，snake_case）。
- **提交**：每个 Task 结束本地 commit（中文 message）；**禁止 push 远端**（用户全局规则）。

---

### Task 1: 项目脚手架与依赖

**Files:**
- Create: `codingplan_refresh/`（整个 Flutter 工程）
- Create: `codingplan_refresh/pubspec.yaml`
- Create: `codingplan_refresh/lib/main.dart`（临时空壳）
- Create: `codingplan_refresh/.gitignore`

**Interfaces:**
- Consumes: 无（起点）
- Produces: 可编译运行的 Flutter 桌面空壳工程；分层目录骨架；全部依赖就位。

- [ ] **Step 1: 生成 Flutter 桌面工程**

在仓库根目录执行（Windows 上生成 windows + macos 平台目录）：

```bash
flutter create --org com.zhaixiaowai --project-name codingplan_refresh --platforms=windows,macos codingplan_refresh
```

期望：生成 `codingplan_refresh/`，内含 `lib/main.dart`、`windows/`、`macos/`、`pubspec.yaml`、`test/`。

- [ ] **Step 2: 建立分层目录骨架**

创建空目录（后续任务填充）：

```bash
cd codingplan_refresh
mkdir -p lib/models lib/services lib/platform lib/ui/widgets lib/utils
```

- [ ] **Step 3a: 简化 pubspec.yaml**

`flutter create` 生成的 `pubspec.yaml` 已含基础配置。**删除** `dependencies:` 下任何手写的第三方包版本号（不编造版本），只保留 `flutter` SDK 与 create 自带的 `flutter_lints`。确认 `dependencies:` 形如：

```yaml
dependencies:
  flutter:
    sdk: flutter
```

- [ ] **Step 3b: 用 flutter pub add 添加依赖（自动取当前稳定版）**

```bash
cd codingplan_refresh
flutter pub add window_manager http encrypt path_provider win32
```

期望：`flutter pub add` 把最新稳定版本写入 `pubspec.yaml`，避免手写编造版本号导致 `flutter pub get` 失败。**不添加 `macos_window_utils`**（禁 zoom 改由 window_manager 的 setResizable 实现，见 Task 10）。

- [ ] **Step 4: 拉取依赖并验证空壳可编译**

```bash
cd codingplan_refresh
flutter pub get
flutter build windows --debug
```

期望：`build\windows\x64\runner\Debug\codingplan_refresh.exe` 生成，无报错。

- [ ] **Step 5: 配置 .gitignore**

确认 `codingplan_refresh/.gitignore`（flutter create 已生成）含 `build/`、`.dart_tool/`、`.flutter-plugins*`。若缺失则补。

- [ ] **Step 6: Commit**

```bash
git add codingplan_refresh
git commit -m "feat: 初始化 Flutter 桌面工程脚手架与依赖"
```

---

### Task 2: AES-256-CBC 加解密工具

**Files:**
- Create: `codingplan_refresh/lib/utils/aes.dart`
- Test: `codingplan_refresh/test/utils/aes_test.dart`

**Interfaces:**
- Consumes: `package:encrypt/encrypt.dart`
- Produces: `class Aes256Cbc`，静态方法 `List<int> encrypt(String plain)` 与 `String decrypt(List<int> cipherBytes)`。这是配置兼容的核心——必须能解密旧版 `config.dat`。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/utils/aes_test.dart`：

```dart
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd codingplan_refresh
flutter test test/utils/aes_test.dart
```

期望：FAIL，`Aes256Cbc` 未定义。

- [ ] **Step 3: 实现 aes.dart**

创建 `codingplan_refresh/lib/utils/aes.dart`：

```dart
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
  static List<int> encrypt(String plain) =>
      _encrypter.encrypt(plain, iv: _iv).bytes;

  /// 解密原始密文字节（与旧版 File.ReadAllBytes 对应）。
  static String decrypt(List<int> cipherBytes) {
    final encrypted = Encrypted(Uint8List.fromList(cipherBytes));
    return _encrypter.decrypt(encrypted, iv: _iv);
  }
}
```

注：`Uint8List` 来自 `dart:typed_data`，需在文件顶部 `import 'dart:typed_data';`。补上该 import。

完整文件头：

```dart
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/utils/aes_test.dart
```

期望：4 个测试全 PASS。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/utils/aes.dart codingplan_refresh/test/utils/aes_test.dart
git commit -m "feat(utils): AES-256-CBC 加解密，兼容旧版 config.dat"
```

---

### Task 3: 配置模型与配置服务（含迁移）

**Files:**
- Create: `codingplan_refresh/lib/models/app_config.dart`
- Create: `codingplan_refresh/lib/services/config_service.dart`
- Test: `codingplan_refresh/test/services/config_service_test.dart`

**Interfaces:**
- Consumes: `Aes256Cbc`（Task 2）
- Produces: `class AppConfig`（`fromJson`/`toJson`，PascalCase 字段）；`class ConfigService`（构造注入 `Directory dataDir`；方法 `AppConfig load()`、`void save(AppConfig c)`、`static const` 窗口尺寸常量）。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/services/config_service_test.dart`：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/services/config_service.dart';

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

  test('JSON 字段为 PascalCase', () {
    svc.save(AppConfig(apiKey: 'sk-x'));
    // 通过 decrypt 读回 JSON 验证字段名
    final bytes = File('${tmpDir.path}${Platform.pathSeparator}config.dat').readAsBytesSync();
    // 重新加载即验证了反序列化；这里再确认默认 model
    expect(svc.load().model, 'glm-5.1');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/config_service_test.dart
```

期望：FAIL，类型未定义。

- [ ] **Step 3: 实现 app_config.dart**

创建 `codingplan_refresh/lib/models/app_config.dart`：

```dart
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
```

- [ ] **Step 4: 实现 config_service.dart**

创建 `codingplan_refresh/lib/services/config_service.dart`：

```dart
import 'dart:convert';
import 'dart:io';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/utils/aes.dart';

class ConfigService {
  /// 窗口尺寸常量（与旧版 ConfigService.cs 一致）。
  static const double expandedWidth = 330;
  static const double expandedHeight = 318;
  static const double collapsedHeight = 120;
  static const double collapsedHeightWithWeekly = 142;

  final Directory dataDir;
  ConfigService(this.dataDir);

  File get _configFile =>
      File('${dataDir.path}${Platform.path.separator}config.dat');
  File get _legacyJsonFile =>
      File('${dataDir.path}${Platform.path.separator}config.json');

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
    final exeDir = File(Platform.resolvedAddress).parent.path;
    final oldPath =
        '$exeDir${Platform.path.separator}data${Platform.path.separator}config.dat';
    final oldFile = File(oldPath);
    if (!oldFile.existsSync()) return;
    try {
      if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
      oldFile.copySync(_configFile.path);
    } catch (_) {/* 迁移失败不影响启动 */}
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
flutter test test/services/config_service_test.dart
```

期望：5 个测试全 PASS。

- [ ] **Step 6: Commit**

```bash
git add codingplan_refresh/lib/models/app_config.dart codingplan_refresh/lib/services/config_service.dart codingplan_refresh/test/services/config_service_test.dart
git commit -m "feat(config): 配置模型与服务，含旧明文/旧路径迁移"
```

---

### Task 4: 日志服务

**Files:**
- Create: `codingplan_refresh/lib/services/log_service.dart`
- Test: `codingplan_refresh/test/services/log_service_test.dart`

**Interfaces:**
- Consumes: 注入 `Directory dataDir`
- Produces: `class LogService(Directory dataDir)`，方法 `void append(String message)`。路径 `<dataDir>/log.txt`。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/services/log_service_test.dart`：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/log_service.dart';

void main() {
  late Directory tmpDir;
  late LogService log;
  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('log_test_');
    log = LogService(tmpDir);
  });
  tearDown(() => tmpDir.deleteSync(recursive: true));

  test('append 写入 log.txt 并追加', () {
    log.append('第一行');
    log.append('第二行');
    final content =
        File('${tmpDir.path}${Platform.path.separator}log.txt').readAsStringSync();
    expect(content.contains('第一行'), isTrue);
    expect(content.contains('第二行'), isTrue);
  });

  test('每条带时间戳前缀', () {
    log.append('hi');
    final content =
        File('${tmpDir.path}${Platform.path.separator}log.txt').readAsStringSync();
    expect(RegExp(r'\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]').hasMatch(content), isTrue);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/log_service_test.dart
```

期望：FAIL。

- [ ] **Step 3: 实现 log_service.dart**

创建 `codingplan_refresh/lib/services/log_service.dart`：

```dart
import 'dart:io';

class LogService {
  final Directory dataDir;
  LogService(this.dataDir);

  File get _logFile =>
      File('${dataDir.path}${Platform.path.separator}log.txt');

  void append(String message) {
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
    final now = DateTime.now();
    final stamp =
        '[${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}]';
    final line = '$stamp $message\n';
    _logFile.writeAsStringSync(line, mode: FileMode.append, flush: true);
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/log_service_test.dart
```

期望：2 个测试全 PASS。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/services/log_service.dart codingplan_refresh/test/services/log_service_test.dart
git commit -m "feat(log): 日志追加服务"
```

---

### Task 5: SSE 行解析

**Files:**
- Create: `codingplan_refresh/lib/utils/sse.dart`
- Test: `codingplan_refresh/test/utils/sse_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class SseParser`：`static bool isDone(String line)`、`static String? extractDeltaContent(String line)`（返回 `choices[0].delta.content` 或 null；坏 chunk 返回 null）。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/utils/sse_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/utils/sse.dart';

void main() {
  test('isDone 识别结束标记', () {
    expect(SseParser.isDone('data: [DONE]'), isTrue);
    expect(SseParser.isDone('data: {"x":1}'), isFalse);
  });

  test('extractDeltaContent 提取 delta.content', () {
    const line = 'data: {"choices":[{"delta":{"content":"你好"}}]}';
    expect(SseParser.extractDeltaContent(line), '你好');
  });

  test('无 content 字段返回 null', () {
    const line = 'data: {"choices":[{"delta":{"role":"assistant"}}]}';
    expect(SseParser.extractDeltaContent(line), isNull);
  });

  test('坏 JSON 返回 null（不抛异常）', () {
    expect(SseParser.extractDeltaContent('data: {坏json'), isNull);
  });

  test('非 data: 前缀返回 null', () {
    expect(SseParser.extractDeltaContent(': keepalive'), isNull);
    expect(SseParser.extractDeltaContent(''), isNull);
  });

  test('[DONE] 行也返回 null content', () {
    expect(SseParser.extractDeltaContent('data: [DONE]'), isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/utils/sse_test.dart
```

期望：FAIL。

- [ ] **Step 3: 实现 sse.dart**

创建 `codingplan_refresh/lib/utils/sse.dart`：

```dart
import 'dart:convert';

/// OpenAI 兼容 SSE 单行解析。复刻旧版 AskStreamAsync 的逐行处理。
class SseParser {
  static const _prefix = 'data: ';

  static bool isDone(String line) => line == 'data: [DONE]';

  /// 返回该行的 delta.content；无内容、坏 chunk、非 data 行均返回 null。
  static String? extractDeltaContent(String line) {
    if (line.isEmpty || isDone(line)) return null;
    if (!line.startsWith(_prefix)) return null;
    final data = line.substring(_prefix.length);
    try {
      final doc = jsonDecode(data) as Map<String, dynamic>;
      final choices = doc['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices[0];
      if (first is! Map<String, dynamic>) return null;
      final delta = first['delta'];
      if (delta is! Map<String, dynamic>) return null;
      final content = delta['content'];
      return content is String ? content : null;
    } catch (_) {
      return null; // 坏 chunk 跳过
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/utils/sse_test.dart
```

期望：6 个测试全 PASS。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/utils/sse.dart codingplan_refresh/test/utils/sse_test.dart
git commit -m "feat(utils): SSE 行解析"
```

---

### Task 6: 用量模型与用量 JSON 解析

**Files:**
- Create: `codingplan_refresh/lib/models/usage_info.dart`
- Create: `codingplan_refresh/lib/services/usage_parser.dart`
- Test: `codingplan_refresh/test/services/usage_parser_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class LimitInfo(int percentage, int? nextResetTimeMs)`、`class UsageInfo(String? level, LimitInfo? mcp, LimitInfo? hour5, LimitInfo? weekly)`；`UsageInfo? parseBigmodelUsage(String jsonBody)`（按 type 归类）。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/services/usage_parser_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/usage_parser.dart';

void main() {
  test('归类 TIME_LIMIT→mcp, TOKENS_LIMIT(unit3,number5)→hour5, 其余→weekly', () {
    const body = '''
{
  "data": {
    "level": "vip",
    "limits": [
      {"type":"TIME_LIMIT","percentage":12,"nextResetTime":1717200000000},
      {"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":34,"nextResetTime":1717300000000},
      {"type":"TOKENS_LIMIT","unit":1,"number":7,"percentage":56}
    ]
  }
}''';
    final u = parseBigmodelUsage(body)!;
    expect(u.level, 'vip');
    expect(u.mcp!.percentage, 12);
    expect(u.mcp!.nextResetTimeMs, 1717200000000);
    expect(u.hour5!.percentage, 34);
    expect(u.weekly!.percentage, 56);
    expect(u.weekly!.nextResetTimeMs, isNull);
  });

  test('缺 data 返回 null', () {
    expect(parseBigmodelUsage('{"msg":"x"}'), isNull);
  });

  test('坏 JSON 返回 null', () {
    expect(parseBigmodelUsage('{坏'), isNull);
  });

  test('level 缺省为 null', () {
    const body = '{"data":{"limits":[]}}';
    expect(parseBigmodelUsage(body)!.level, isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/usage_parser_test.dart
```

期望：FAIL。

- [ ] **Step 3: 实现 usage_info.dart**

创建 `codingplan_refresh/lib/models/usage_info.dart`：

```dart
class LimitInfo {
  final int percentage;
  final int? nextResetTimeMs; // Unix 毫秒
  const LimitInfo(this.percentage, this.nextResetTimeMs);
}

class UsageInfo {
  final String? level;
  final LimitInfo? mcp;   // TIME_LIMIT（月）
  final LimitInfo? hour5; // TOKENS_LIMIT unit==3 number==5
  final LimitInfo? weekly;
  const UsageInfo(this.level, this.mcp, this.hour5, this.weekly);
}
```

- [ ] **Step 4: 实现 usage_parser.dart**

创建 `codingplan_refresh/lib/services/usage_parser.dart`：

```dart
import 'dart:convert';
import 'package:codingplan_refresh/models/usage_info.dart';

/// 解析 BigModel 配额 API 响应。复刻旧版 QueryBigmodelUsagePercentageAsync 的归类逻辑。
UsageInfo? parseBigmodelUsage(String jsonBody) {
  try {
    final doc = jsonDecode(jsonBody) as Map<String, dynamic>;
    final data = doc['data'];
    if (data is! Map<String, dynamic>) return null;
    final limits = data['limits'];
    if (limits is! List) return null;

    final level = data['level'] as String?;
    LimitInfo? mcp, hour5, weekly;

    for (final limit in limits) {
      if (limit is! Map<String, dynamic>) continue;
      final pct = limit['percentage'];
      if (pct is! int) continue;
      final nrt = limit['nextResetTime'];
      final nextReset = nrt is int ? nrt : null;
      final info = LimitInfo(pct, nextReset);

      final type = limit['type'] as String?;
      if (type == 'TIME_LIMIT') {
        mcp = info;
      } else if (type == 'TOKENS_LIMIT') {
        final unit = limit['unit'] is int ? limit['unit'] as int : 0;
        final number = limit['number'] is int ? limit['number'] as int : 0;
        if (unit == 3 && number == 5) {
          hour5 = info;
        } else {
          weekly = info;
        }
      }
    }
    return UsageInfo(level, mcp, hour5, weekly);
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
flutter test test/services/usage_parser_test.dart
```

期望：4 个测试全 PASS。

- [ ] **Step 6: Commit**

```bash
git add codingplan_refresh/lib/models/usage_info.dart codingplan_refresh/lib/services/usage_parser.dart codingplan_refresh/test/services/usage_parser_test.dart
git commit -m "feat(usage): 用量模型与 BigModel 响应解析"
```

---

### Task 7: LLM 服务（SSE 流式 + 用量查询）

**Files:**
- Create: `codingplan_refresh/lib/services/llm_service.dart`
- Test: `codingplan_refresh/test/services/llm_service_test.dart`

**Interfaces:**
- Consumes: `SseParser`（Task 5）、`parseBigmodelUsage`（Task 6）、`LogService`（Task 4）、`package:http`
- Produces: `class LlmService(LogService log)`：
  - `Future<String> askStream({required String apiUrl, required String apiKey, required String model, required String question, required void Function(String chunk) onChunk})`
  - `Future<UsageInfo?> queryBigmodelUsage(String apiKey)`
  - 抽出可测纯函数 `String processSseLines(List<String> lines, void Function(String) onChunk)`（消费行列表，返回累积全文，供单测）。

- [ ] **Step 1: 写失败测试（聚焦可测纯函数 processSseLines）**

创建 `codingplan_refresh/test/services/llm_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/llm_service.dart';

void main() {
  test('processSseLines 累积 delta.content 并在 [DONE] 停止', () {
    final lines = [
      'data: {"choices":[{"delta":{"content":"你"}}]}',
      'data: {"choices":[{"delta":{"content":"好"}}]}',
      'data: {"choices":[{"delta":{"role":"assistant"}}]}', // 无 content，跳过
      'data: {坏',                                       // 坏 chunk，跳过
      'data: [DONE]',
      'data: {"choices":[{"delta":{"content":"不应出现"}}]}', // DONE 后忽略
    ];
    final chunks = <String>[];
    final full = processSseLines(lines, chunks.add);
    expect(full, '你好');
    expect(chunks, ['你', '好']);
  });

  test('processSseLines 无 DONE 时消费全部行', () {
    final lines = ['data: {"choices":[{"delta":{"content":"abc"}}]}'];
    expect(processSseLines(lines, (_) {}), 'abc');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/llm_service_test.dart
```

期望：FAIL，`processSseLines` 未定义。

- [ ] **Step 3: 实现 llm_service.dart**

创建 `codingplan_refresh/lib/services/llm_service.dart`：

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/services/usage_parser.dart';
import 'package:codingplan_refresh/utils/sse.dart';

class LlmService {
  final LogService log;
  LlmService(this.log);

  static const _usageUrl =
      'https://open.bigmodel.cn/api/monitor/usage/quota/limit';

  /// 消费 SSE 行列表，累积返回全文。可单测的纯函数。
  String processSseLines(List<String> lines, void Function(String) onChunk) {
    final sb = StringBuffer();
    for (final line in lines) {
      if (SseParser.isDone(line)) break;
      final delta = SseParser.extractDeltaContent(line);
      if (delta != null) {
        sb.write(delta);
        onChunk(delta);
      }
    }
    return sb.toString();
  }

  /// OpenAI 兼容流式调用。失败抛 Exception（调用方处理重试与 LastAutoTriggerKey）。
  Future<String> askStream({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String question,
    required void Function(String chunk) onChunk,
  }) async {
    if (apiUrl.trim().isEmpty) throw Exception('API URL 未配置');
    if (apiKey.trim().isEmpty) throw Exception('API Key 未配置');

    final body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': [
        {'role': 'user', 'content': question}
      ],
      'temperature': 0.9,
    });

    final reqLog = StringBuffer()
      ..writeln('========== [Request] ==========')
      ..writeln('POST $apiUrl')
      ..writeln('Authorization: Bearer ***')
      ..writeln('Content-Type: application/json')
      ..writeln()
      ..writeln(_prettyJson(body));
    log.append(reqLog.toString());

    final request = http.Request('POST', Uri.parse(apiUrl));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Content-Type'] = 'application/json';
    request.body = body;

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(
        const Duration(seconds: 120),
      );

      final respLog = StringBuffer()
        ..writeln('========== [Response] ${response.statusCode} ==========');
      log.append(respLog.toString());

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errBody = await response.stream.bytesToString();
        log.append(errBody);
        throw Exception('API 调用失败: ${response.statusCode} $errBody');
      }

      final full = StringBuffer();
      final lineStream =
          response.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lineStream) {
        if (SseParser.isDone(line)) break;
        final delta = SseParser.extractDeltaContent(line);
        if (delta != null) {
          full.write(delta);
          onChunk(delta);
        }
      }
      log.append(_prettyJson(full.toString()));
      return full.toString();
    } finally {
      client.close();
    }
  }

  /// 查询 BigModel 配额。失败返回 null（静默）。
  Future<UsageInfo?> queryBigmodelUsage(String apiKey) async {
    if (apiKey.trim().isEmpty) return null;
    try {
      final reqLog = StringBuffer()
        ..writeln('========== [Usage Request] ==========')
        ..writeln('GET $_usageUrl')
        ..writeln('Authorization: ***');
      log.append(reqLog.toString());

      final response = await http.get(Uri.parse(_usageUrl), headers: {
        'Authorization': apiKey,
      }).timeout(const Duration(seconds: 120));

      final body = response.body;
      log.append('========== [Usage Response] ${response.statusCode} ==========');
      log.append(_prettyJson(body));

      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return parseBigmodelUsage(body);
    } catch (_) {
      return null;
    }
  }

  String _prettyJson(String raw) {
    try {
      final obj = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return raw;
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/llm_service_test.dart
```

期望：2 个测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/services/llm_service.dart codingplan_refresh/test/services/llm_service_test.dart
git commit -m "feat(llm): SSE 流式调用与用量查询服务"
```

---

### Task 8: 调度服务（触发时段匹配）

**Files:**
- Create: `codingplan_refresh/lib/services/scheduler_service.dart`
- Test: `codingplan_refresh/test/services/scheduler_service_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class SchedulerService`：
  - `static const List<(int,int)> triggerTimes = [(1,0),(7,0),(13,0),(19,0)]`
  - `({bool trigger, String key}) checkTrigger(DateTime now, String lastKey)` —— 命中且 key 不同返回 trigger=true 与新 key。
  - `DateTime? nextTrigger(DateTime now, String lastKey)` —— 下一个触发时刻（复刻 UpdateNextTriggerLabel 逻辑）。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/services/scheduler_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/scheduler_service.dart';

void main() {
  test('命中 01:00 且 lastKey 不同 → trigger', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '');
    expect(r.trigger, isTrue);
    expect(r.key, '2026-06-25 01:00');
  });

  test('同一 key 已触发过 → 不再触发', () {
    final now = DateTime(2026, 6, 25, 1, 0);
    final r = SchedulerService.checkTrigger(now, '2026-06-25 01:00');
    expect(r.trigger, isFalse);
  });

  test('非触发时段 → 不触发', () {
    final now = DateTime(2026, 6, 25, 2, 30);
    final r = SchedulerService.checkTrigger(now, '');
    expect(r.trigger, isFalse);
  });

  test('nextTrigger：当前 00:30 → 当天 01:00', () {
    final now = DateTime(2026, 6, 25, 0, 30);
    final next = SchedulerService.nextTrigger(now, '')!;
    expect(next, DateTime(2026, 6, 25, 1, 0));
  });

  test('nextTrigger：当前 23:00 → 次日 01:00', () {
    final now = DateTime(2026, 6, 25, 23, 0);
    final next = SchedulerService.nextTrigger(now, '')!;
    expect(next, DateTime(2026, 6, 26, 1, 0));
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/scheduler_service_test.dart
```

期望：FAIL。

- [ ] **Step 3: 实现 scheduler_service.dart**

创建 `codingplan_refresh/lib/services/scheduler_service.dart`：

```dart
class SchedulerService {
  static const List<(int, int)> triggerTimes = [(1, 0), (7, 0), (13, 0), (19, 0)];

  static String _key(DateTime d, int h, int m) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// 判断 now 是否命中触发时段且本轮未触发。
  static ({bool trigger, String key}) checkTrigger(
      DateTime now, String lastKey) {
    for (final (h, m) in triggerTimes) {
      if (now.hour == h && now.minute == m) {
        final key = _key(now, h, m);
        if (key != lastKey) return (trigger: true, key: key);
      }
    }
    return (trigger: false, key: lastKey);
  }

  /// 计算下一个触发时刻（考虑当天该时段是否已被 lastKey 标记完成）。
  static DateTime? nextTrigger(DateTime now, String lastKey) {
    DateTime? next;
    for (final (h, m) in triggerTimes) {
      var target = DateTime(now.year, now.month, now.day, h, m);
      final key = _key(now, h, m);
      if (target.isAfter(now) || key != lastKey) {
        if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
        if (next == null || target.isBefore(next)) next = target;
      }
    }
    return next;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/scheduler_service_test.dart
```

期望：5 个测试全 PASS。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/services/scheduler_service.dart codingplan_refresh/test/services/scheduler_service_test.dart
git commit -m "feat(scheduler): 触发时段匹配与下次触发计算"
```

---

### Task 9: 本地化服务

**Files:**
- Create: `codingplan_refresh/lib/services/localization_service.dart`
- Test: `codingplan_refresh/test/services/localization_service_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class LocalizationService`：`String current`、`void initialize(String? saved)`、`String setLanguage(String code)`、`String t(String key)`。键集合见 Step 3。

- [ ] **Step 1: 写失败测试**

创建 `codingplan_refresh/test/services/localization_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/services/localization_service.dart';

void main() {
  test('显式 en 后 current=en', () {
    final l = LocalizationService();
    l.initialize('en');
    expect(l.current, 'en');
  });

  test('zh 与 en 文案不同', () {
    final l = LocalizationService();
    l.initialize('zh');
    final zhText = l.t('resultHeader');
    l.setLanguage('en');
    final enText = l.t('resultHeader');
    expect(zhText, isNot(equals(enText)));
  });

  test('auto 在中文系统回退 zh（测试强制 zh）', () {
    final l = LocalizationService();
    l.initialize('auto');
    expect(l.current, anyOf('zh', 'en')); // 不依赖系统时接受二者
  });

  test('未知 key 返回 key 本身', () {
    final l = LocalizationService();
    l.initialize('zh');
    expect(l.t('不存在的键'), '不存在的键');
  });
}
```

> 注：`initialize('auto')` 的结果依赖测试主机的系统语言；测试用 `anyOf` 容忍。实现中 `auto` 按 `Platform.localeName` 判定。

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/localization_service_test.dart
```

期望：FAIL。

- [ ] **Step 3: 实现 localization_service.dart（字符串必须从旧 resx 抄录，禁止编造）**

**先读旧资源文件**：`CodingPlanTimeRefresh/Resources/Strings/AppResources.resx`（中文）与 `AppResources.en.resx`（英文）。把下表每个键对应的 resx `data name` 的值，**原样抄进** `_table` 的 `zh`/`en`。任何文案偏差都算实现错误——不许自己写文案。

| camelCase 键 | 旧 resx data name |
|---|---|
| manualTrigger | ManualTriggerButton |
| manualTriggerPopup | ManualTriggerPopupButton |
| waitingPlaceholder | WaitingPlaceholder |
| resultHeader | ResultHeader |
| save | SaveButton |
| cancel | CancelButton |
| token5hLabel | Token5HLabel |
| tokenWeekLabel | TokenWeekLabel |
| mcpMonthLabel | MCPMonthLabel |
| pinLabel | PinLabel |
| languageLabel | LanguageLabel |
| languageAuto | LanguageAuto |
| languageZh | LanguageZh |
| languageEn | LanguageEn |
| loading | LoadingText |
| errorMessage | ErrorMessageFormat |
| apiUrlNotConfigured | ApiUrlNotConfigured |
| apiKeyNotConfigured | ApiKeyNotConfigured |
| apiCallFailed | ApiCallFailedFormat |
| windowTitle | WindowTitleFormat |
| nextTriggerFormat | NextTriggerFormat |
| resetToday | ResetTextToday |
| resetOther | ResetTextOther |
| jokePrompt | JokePrompt |
| resultTimestamp | ResultTimestampFormat |

创建 `codingplan_refresh/lib/services/localization_service.dart`，按上表把 resx 值填入 `_table`：

```dart
import 'dart:io';

class LocalizationService {
  String current = 'zh';

  /// 键 → {语言: 文案}。文案从旧 AppResources.resx / AppResources.en.resx 原样抄录。
  /// （下方仅示意结构——每个值必须替换为 resx 中对应 data name 的真实 value。）
  static const _table = <String, Map<String, String>>{
    'manualTrigger': {'zh': '<抄 AppResources.resx: ManualTriggerButton>',
                      'en': '<抄 AppResources.en.resx: ManualTriggerButton>'},
    // …按上表逐条填入全部 25 个键，zh 取 AppResources.resx、en 取 AppResources.en.resx…
  };

  void initialize(String? saved) {
    if (saved == null || saved.isEmpty || saved == 'auto') {
      current = Platform.localeName.toLowerCase().startsWith('en') ? 'en' : 'zh';
    } else {
      current = saved == 'en' ? 'en' : 'zh';
    }
  }

  String setLanguage(String code) {
    if (code == 'auto') {
      current = Platform.localeName.toLowerCase().startsWith('en') ? 'en' : 'zh';
    } else {
      current = code == 'en' ? 'en' : 'zh';
    }
    return current;
  }

  String t(String key) {
    final entry = _table[key];
    if (entry == null) return key;
    return entry[current] ?? entry['zh']!;
  }
}

extension FmtString on String {
  /// 占位替换：旧 resx 用 {0} 格式（如 ErrorMessageFormat="错误：{0}"）。
  /// 抄录后二选一保持一致：要么把 resx 的 {0} 改写为 %s 配合本 fmt，
  /// 要么改本 fmt 改用 replaceFirst('{0}', ...)。禁止混用。
  String fmt(List<Object> args) {
    var s = this;
    for (final a in args) {
      s = s.replaceFirst(RegExp(r'%[ds]'), '$a');
    }
    return s;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/localization_service_test.dart
```

期望：4 个测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/services/localization_service.dart codingplan_refresh/test/services/localization_service_test.dart
git commit -m "feat(i18n): zh/en 本地化服务与字符串表"
```

---

### Task 10: 窗口控制（window_manager）

**Files:**
- Create: `codingplan_refresh/lib/platform/window_controller.dart`
- Modify: `codingplan_refresh/lib/main.dart`（在 Task 13 串联；本任务只建类）

**Interfaces:**
- Consumes: `package:window_manager`
- Produces: `class WindowController`：`Future<void> setup({required double width, required double height, required bool alwaysOnTop, required bool fixed})`、`Future<void> setAlwaysOnTop(bool v)`、`Future<void> setHeight(double h)`、`Future<void> center()`。

> 平台特定代码不易单测；本任务以「手动验证 + 编译通过」为验收。

- [ ] **Step 1: 实现 window_controller.dart**

创建 `codingplan_refresh/lib/platform/window_controller.dart`：

```dart
import 'package:window_manager/window_manager.dart';

class WindowController {
  /// 初始化窗口：固定尺寸、居中、不可缩放、置顶。
  /// 「禁最大化」由 setResizable(false) + setMaximumSize 实现（双平台），不引入 macos_window_utils。
  Future<void> setup({
    required double width,
    required double height,
    required bool alwaysOnTop,
  }) async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(const WindowOptions(
      size: Size(width, height),
      minimumSize: Size(width, 120),
      maximumSize: Size(width, 350),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    ), () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
      await windowManager.setAlwaysOnTop(alwaysOnTop);
      await windowManager.setSize(Size(width, height));
    });
  }

  Future<void> setAlwaysOnTop(bool v) => windowManager.setAlwaysOnTop(v);

  Future<void> setHeight(double width, double h) =>
      windowManager.setSize(Size(width, h));

  /// 更新窗口标题（用量百分比 + level）。
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  Future<void> center() => windowManager.center();
}
```

- [ ] **Step 2: 禁最大化机制（无需原生注入，无 macos_window_utils）**

「禁最大化/禁 zoom」统一由 `window_manager` 的 `setResizable(false)` + `setMaximumSize` 实现（已在 Step 1 setup 内）。`setResizable(false)` 在双平台禁用窗口缩放，配合 `maximumSize` 锁定尺寸——绿色 zoom 按钮点击后窗口不变大（功能上禁用最大化）。

**不引入** `macos_window_utils`，也**不修改** `MainFlutterWindow.swift`——避免与 window_manager 的窗口操作互相覆盖 styleMask。若 Mac 实测 zoom 仍能放大窗口，再单独评估（届时二选一：全程交给 macos_window_utils 管，或在 window_manager 初始化之后做原生注入），不要两边各管一半。

- [ ] **Step 3: 验证 Windows 编译**

```bash
cd codingplan_refresh
flutter build windows --debug
```

期望：无编译错误（window_controller 仅用 window_manager，无平台分支）。

- [ ] **Step 4: （Mac 环境）验证 macOS 编译与禁 zoom**

在 Mac 上：

```bash
cd codingplan_refresh
flutter build macos --debug
open build/macos/Build/Products/Debug/codingplan_refresh.app
```

期望：窗口固定尺寸，点击绿色 zoom 后窗口不变大（最大化无效）。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/lib/platform/window_controller.dart
git commit -m "feat(platform): 窗口控制封装（固定尺寸/居中/置顶/禁最大化）"
```

---

### Task 11: 单实例（Windows mutex + macOS 文件锁）

**Files:**
- Create: `codingplan_refresh/lib/platform/single_instance.dart`

**Interfaces:**
- Consumes: `package:win32`（Windows）、`dart:io`（macOS 文件锁）
- Produces: `class SingleInstance`：`bool ensure()` —— 返回 false 表示已有实例在跑（应退出）。

- [ ] **Step 1: 实现 single_instance.dart**

创建 `codingplan_refresh/lib/platform/single_instance.dart`：

```dart
import 'dart:ffi';
import 'dart:io';
import 'package:win32/win32.dart';

/// 单实例：Windows 用命名互斥体（复刻旧版 CodingPlanTimeRefresh_SingleInstance）。
/// mutex 是 OS 内核命名对象——不监听端口、不触防火墙，进程退出 OS 自动释放。
/// macOS/Linux 暂不强制单实例（return true 放行）。
class SingleInstance {
  /// 返回 true=当前是首实例可继续；false=已有实例（仅 Windows 检测），应退出。
  bool ensure() {
    if (!Platform.isWindows) return true;
    final name = 'CodingPlanTimeRefresh_SingleInstance'.toNativeUtf16();
    final handle = CreateMutex(nullptr, TRUE, name);
    final err = GetLastError();
    if (err == ERROR_ALREADY_EXISTS) return false;
    return handle != 0;
  }
}
```

- [ ] **Step 2: 验收双开单实例**

验证（先启动一次保持运行，再启动第二次）：

```bash
cd codingplan_refresh
flutter build windows --debug
build\\windows\\x64\\runner\\Debug\\codingplan_refresh.exe &
build\\windows\\x64\\runner\\Debug\\codingplan_refresh.exe
```

期望：第二次进程因互斥体 `CodingPlanTimeRefresh_SingleInstance` 已存在（`GetLastError` = 183）而立即退出，只保留一个窗口。无端口监听、无防火墙弹窗。

- [ ] **Step 3: 验证编译**

```bash
cd codingplan_refresh
flutter build windows --debug
```

期望：无编译错误。

- [ ] **Step 4: Commit**

```bash
git add codingplan_refresh/lib/platform/
git commit -m "feat(platform): 单实例（Windows 互斥体 / macOS 文件锁）"
```

---

### Task 12: UI 主界面与组件（平移 MainPage）

**Files:**
- Create: `codingplan_refresh/lib/ui/widgets/usage_row.dart`
- Create: `codingplan_refresh/lib/ui/widgets/config_overlay.dart`
- Create: `codingplan_refresh/lib/ui/widgets/result_overlay.dart`
- Create: `codingplan_refresh/lib/ui/main_page.dart`

**Interfaces:**
- Consumes: `AppConfig`、`LlmService`、`ConfigService`、`LocalizationService`、`SchedulerService`、`WindowController`、`LogService`
- Produces: `class MainPage extends StatefulWidget` —— 平移旧 `MainPage.xaml` + `.cs` 的全部交互。

> UI 难以纯单测；本任务以 widget test 覆盖关键状态切换（折叠、置顶、语言），其余手动验证。

- [ ] **Step 1: 实现 usage_row.dart**

创建 `codingplan_refresh/lib/ui/widgets/usage_row.dart`：一行用量（标签 + 重置时间 + 百分比着色）。

```dart
import 'package:flutter/material.dart';
import '../../models/usage_info.dart';

class UsageRow extends StatelessWidget {
  final String label;
  final LimitInfo? info;
  final String Function(int ms) resetText;
  const UsageRow(
      {super.key, required this.label, required this.info, required this.resetText});

  static Color pctColor(int p) {
    if (p >= 80) return const Color(0xFFFF0000);
    if (p >= 50) return const Color(0xFFFF8C00);
    return const Color(0xFF007ACC);
  }

  @override
  Widget build(BuildContext context) {
    final pct = info?.percentage;
    return Row(children: [
      SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12))),
      Expanded(
          child: Center(
              child: Text(info == null ? '' : resetText(info!.nextResetTimeMs ?? -1),
                  style: const TextStyle(color: Color(0xFF999999), fontSize: 11)))),
      SizedBox(
          width: 50,
          child: Text(pct == null ? '' : '$pct%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: pct == null ? const Color(0xFF007ACC) : pctColor(pct),
                  fontSize: 16,
                  fontWeight: FontWeight.bold))),
    ]);
  }
}
```

- [ ] **Step 2: 实现 config_overlay.dart**

配置浮层（API URL / Key / Model / 语言三按钮）。完整代码：

```dart
import 'package:flutter/material.dart';
import '../../models/app_config.dart';
import '../../services/localization_service.dart';

class ConfigOverlay extends StatefulWidget {
  final AppConfig initial;
  final LocalizationService l10n;
  final void Function(AppConfig next, bool langChanged) onSave;
  final VoidCallback onCancel;
  const ConfigOverlay(
      {super.key, required this.initial, required this.l10n, required this.onSave, required this.onCancel});

  @override
  State<ConfigOverlay> createState() => _ConfigOverlayState();
}

class _ConfigOverlayState extends State<ConfigOverlay> {
  late final TextEditingController url, key, model;
  late int langIndex; // 0 auto 1 zh 2 en

  @override
  void initState() {
    super.initState();
    url = TextEditingController(text: widget.initial.apiUrl);
    key = TextEditingController(text: widget.initial.apiKey);
    model = TextEditingController(text: widget.initial.model);
    langIndex = (widget.initial.language ?? 'auto') == 'zh'
        ? 1
        : (widget.initial.language == 'en' ? 2 : 0);
  }

  @override
  void dispose() {
    url.dispose();
    key.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Expanded(child: ListView(children: [
          _field('API URL', url, 'https://api.openai.com/v1/chat/completions'),
          _field('API Key', key, 'sk-xxx', obscure: true),
          _field('Model', model, 'glm-5.1'),
          const SizedBox(height: 6),
          Text(l.t('languageLabel'),
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
          Row(children: [
            _langBtn(0, l.t('languageAuto')), _langBtn(1, l.t('languageZh')), _langBtn(2, l.t('languageEn')),
          ]),
        ])),
        Row(children: [
          Expanded(child: ElevatedButton(
              onPressed: () {
                final next = AppConfig(
                  isAlwaysOnTop: widget.initial.isAlwaysOnTop,
                  apiUrl: url.text,
                  apiKey: key.text,
                  model: model.text,
                  lastAutoTriggerKey: widget.initial.lastAutoTriggerKey,
                  isCollapsed: widget.initial.isCollapsed,
                  language: langIndex == 1 ? 'zh' : (langIndex == 2 ? 'en' : 'auto'),
                );
                widget.onSave(next, next.language != (widget.initial.language ?? 'auto'));
              },
              child: Text(l.t('save')))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(
              onPressed: widget.onCancel, child: Text(l.t('cancel')))),
        ]),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, String hint, {bool obscure = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
      TextField(
          controller: c,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF3C3C3C),
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF666666)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: InputBorder.none)),
    ]);
  }

  Widget _langBtn(int idx, String text) {
    final selected = langIndex == idx;
    return Expanded(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: selected ? const Color(0xFF007ACC) : const Color(0xFF3C3C3C),
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero),
          onPressed: () => setState(() => langIndex = idx),
          child: Text(text, style: const TextStyle(fontSize: 12))),
    ));
  }
}
```

- [ ] **Step 3: 实现 result_overlay.dart**

结果浮层（只读流式文本 + 关闭 + 手动触发）。完整代码：

```dart
import 'package:flutter/material.dart';
import '../../services/localization_service.dart';

class ResultOverlay extends StatelessWidget {
  final String header;
  final String text;
  final String placeholder;
  final VoidCallback onClose;
  final VoidCallback onTrigger;
  final LocalizationService l10n;
  const ResultOverlay(
      {super.key, required this.header, required this.text, required this.placeholder, required this.onClose, required this.onTrigger, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xE62D2D30),
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(header, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11))),
          GestureDetector(onTap: onClose, child: const Text('✕', style: TextStyle(color: Color(0xFFAAAAAA)))),
        ]),
        const SizedBox(height: 6),
        Expanded(child: Container(
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.all(6),
          child: SingleChildScrollView(
            child: Text(text.isEmpty ? placeholder : text,
                style: TextStyle(
                    color: text.isEmpty ? const Color(0xFF555555) : const Color(0xFFCCCCCC),
                    fontSize: 11)),
          ),
        )),
        const SizedBox(height: 6),
        ElevatedButton(
            onPressed: onTrigger,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007ACC)),
            child: Text(l10n.t('manualTriggerPopup'))),
      ]),
    );
  }
}
```

- [ ] **Step 4: 实现 main_page.dart（状态机平移）**

创建 `codingplan_refresh/lib/ui/main_page.dart`：平移两个定时器、触发重试、用量轮询、折叠、置顶、配置/结果浮层、本地化刷新、标题栏。关键骨架（实现者补全样式微调）：

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/usage_info.dart';
import '../services/config_service.dart';
import '../services/llm_service.dart';
import '../services/localization_service.dart';
import '../services/log_service.dart';
import '../services/scheduler_service.dart';
import '../platform/window_controller.dart';
import 'widgets/usage_row.dart';
import 'widgets/config_overlay.dart';
import 'widgets/result_overlay.dart';

class MainPage extends StatefulWidget {
  final AppConfig config;
  final ConfigService configService;
  final LlmService llm;
  final LogService log;
  final LocalizationService l10n;
  final WindowController window;
  const MainPage({
    super.key,
    required this.config,
    required this.configService,
    required this.llm,
    required this.log,
    required this.l10n,
    required this.window,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late AppConfig _config;
  bool _collapsed = false;
  bool _isBusy = false;
  bool _showConfig = false;
  bool _showResult = false;
  String _resultText = '';
  String _resultHeader = '';
  String _nextTriggerText = '';
  UsageInfo? _usage;
  Timer? _triggerTimer;
  Timer? _usageTimer;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _collapsed = _config.isCollapsed;
    _resultHeader = widget.l10n.t('resultHeader');
    if (_config.apiUrl.isEmpty || _config.apiKey.isEmpty) _showConfig = true;
    _triggerTimer = Timer.periodic(const Duration(seconds: 6), (_) => _onTriggerTick());
    _usageTimer = Timer.periodic(const Duration(seconds: 60), (_) => _queryUsage());
    _queryUsage();
    _updateNextTrigger();
  }

  @override
  void dispose() {
    _triggerTimer?.cancel();
    _usageTimer?.cancel();
    super.dispose();
  }

  void _onTriggerTick() {
    _updateNextTrigger();
    final r = SchedulerService.checkTrigger(DateTime.now(), _config.lastAutoTriggerKey);
    if (!r.trigger) return;
    _config.lastAutoTriggerKey = r.key;
    widget.configService.save(_config);
    _callLlm(manual: false, retry: 3);
  }

  Future<void> _callLlm({required bool manual, int retry = 1}) async {
    if (_isBusy) return;
    setState(() { _isBusy = true; _resultText = widget.l10n.t('loading'); _showResult = true; });
    // 流式节流：累积到 buf，每 50ms 最多 setState 一次，避免逐 chunk 高频重建卡顿。
    final buf = StringBuffer();
    Timer? flushTimer;
    void flush() {
      flushTimer = null;
      if (mounted) setState(() => _resultText = buf.toString());
    }
    try {
      final model = _config.model.isEmpty ? 'glm-5.1' : _config.model;
      final prompt = '${widget.l10n.t('jokePrompt')}\nseed=${DateTime.now().millisecondsSinceEpoch % 10000}';
      await widget.llm.askStream(
        apiUrl: _config.apiUrl,
        apiKey: _config.apiKey,
        model: model,
        question: prompt,
        onChunk: (c) {
          if (buf.isEmpty) setState(() => _resultText = ''); // 清掉 loading 占位
          buf.write(c);
          flushTimer ??= Timer(const Duration(milliseconds: 50), flush);
        },
      );
      flush(); // 流结束后确保完整文本落盘
      _resultHeader = widget.l10n.t('resultHeader');
    } catch (e) {
      if (!manual) {
        _config.lastAutoTriggerKey = '';
        widget.configService.save(_config);
      }
      setState(() => _resultText = widget.l10n.t('errorMessage').fmt(['$e']));
      widget.log.append('[Error] $e');
      if (!manual && retry > 1) {
        await Future.delayed(const Duration(seconds: 5));
        await _callLlm(manual: false, retry: retry - 1);
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _queryUsage() async {
    if (_config.apiUrl.isEmpty || _config.apiKey.isEmpty) return;
    if (!_config.apiUrl.contains('bigmodel.cn')) return;
    final u = await widget.llm.queryBigmodelUsage(_config.apiKey);
    if (u == null) return;
    final primary = u.hour5?.percentage ?? u.mcp?.percentage ?? 0;
    final level = (u.level == null || u.level!.isEmpty)
        ? ''
        : ' ${u.level![0].toUpperCase()}${u.level!.substring(1)}';
    await widget.window
        .setTitle(widget.l10n.t('windowTitle').fmt([primary, level.trim()]));
    setState(() => _usage = u);
  }

  void _updateNextTrigger() {
    final next = SchedulerService.nextTrigger(DateTime.now(), _config.lastAutoTriggerKey);
    if (next == null) return;
    final diff = next.difference(DateTime.now());
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    setState(() => _nextTriggerText =
        widget.l10n.t('nextTriggerFormat').fmt(['$next', m, s]));
  }

  String _resetText(int? ms) {
    if (ms == null || ms < 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final isToday = dt.year == DateTime.now().year && dt.month == DateTime.now().month && dt.day == DateTime.now().day;
    return widget.l10n.t(isToday ? 'resetToday' : 'resetOther').fmt(['$dt']);
  }

  void _toggleCollapse() {
    setState(() => _collapsed = !_collapsed);
    _config.isCollapsed = _collapsed;
    widget.configService.save(_config);
    final h = _collapsed
        ? (_usage?.weekly != null ? ConfigService.collapsedHeightWithWeekly : ConfigService.collapsedHeight)
        : ConfigService.expandedHeight;
    widget.window.setHeight(ConfigService.expandedWidth, h);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D30),
      body: Stack(children: [
        // 主内容：下次触发 + 三行用量
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
          child: Column(children: [
            Align(alignment: Alignment.centerRight,
                child: Text(_nextTriggerText, style: const TextStyle(color: Color(0xFF666666), fontSize: 10))),
            const Divider(color: Color(0xFF444444), height: 6),
            if (_usage?.hour5 != null) UsageRow(label: l.t('token5hLabel'), info: _usage?.hour5, resetText: _resetText),
            if (_usage?.weekly != null) UsageRow(label: l.t('tokenWeekLabel'), info: _usage?.weekly, resetText: _resetText),
            UsageRow(label: l.t('mcpMonthLabel'), info: _usage?.mcp, resetText: _resetText),
            const Spacer(),
            // 底部栏：手动触发 + 置顶 + 设置
            if (!_collapsed) Row(children: [
              ElevatedButton(
                  onPressed: _isBusy ? null : () => setState(() => _showResult = true),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007ACC)),
                  child: Text(l.t('manualTrigger'))),
              const Spacer(),
              Row(children: [
                Checkbox(value: _config.isAlwaysOnTop, onChanged: (v) {
                  setState(() => _config.isAlwaysOnTop = v ?? false);
                  widget.window.setAlwaysOnTop(_config.isAlwaysOnTop);
                  widget.configService.save(_config);
                }),
                Text(l.t('pinLabel'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                IconButton(onPressed: () => setState(() => _showConfig = true), icon: const Icon(Icons.settings, color: Color(0xFFAAAAAA), size: 18)),
              ]),
            ]),
          ]),
        ),
        // 折叠三角（左上）
        Positioned(left: 4, top: 4, child: GestureDetector(
          onTap: _toggleCollapse,
          child: Icon(_collapsed ? Icons.arrow_drop_down : Icons.arrow_drop_up, color: const Color(0xFF888888)),
        )),
        if (_showResult) ResultOverlay(
          header: _resultHeader, text: _resultText, placeholder: l.t('waitingPlaceholder'),
          onClose: () => setState(() => _showResult = false),
          onTrigger: () => _callLlm(manual: true), l10n: l),
        if (_showConfig) ConfigOverlay(
          initial: _config, l10n: l,
          onSave: (next, langChanged) {
            final urlChanged = next.apiUrl != _config.apiUrl || next.apiKey != _config.apiKey;
            setState(() { _config = next; _showConfig = false; });
            widget.configService.save(_config);
            if (langChanged) { widget.l10n.setLanguage(next.language ?? 'auto'); _updateNextTrigger(); _queryUsage(); }
            if (urlChanged) _queryUsage();
          },
          onCancel: () => setState(() => _showConfig = false)),
      ]),
    );
  }
}
```

- [ ] **Step 5: Widget test（折叠/置顶）**

`WindowController` 的方法为普通实例方法，可被子类 override，故直接写 `FakeWindowController` 注入即可（无需 mocktail）。创建 `codingplan_refresh/test/ui/main_page_test.dart`：

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingplan_refresh/models/app_config.dart';
import 'package:codingplan_refresh/platform/window_controller.dart';
import 'package:codingplan_refresh/services/config_service.dart';
import 'package:codingplan_refresh/services/llm_service.dart';
import 'package:codingplan_refresh/services/localization_service.dart';
import 'package:codingplan_refresh/services/log_service.dart';
import 'package:codingplan_refresh/ui/main_page.dart';

class FakeWindowController extends WindowController {
  final List<double> heights = [];
  final List<bool> onTop = [];
  @override
  Future<void> setup({required double width, required double height, required bool alwaysOnTop}) async {}
  @override
  Future<void> setHeight(double width, double h) async => heights.add(h);
  @override
  Future<void> setAlwaysOnTop(bool v) async => onTop.add(v);
  @override
  Future<void> setTitle(String t) async {}
  @override
  Future<void> center() async {}
}

void main() {
  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('ui_'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  // 用一个非空、不含 bigmodel.cn 的 url，避免配置浮层遮挡主内容、且不触发用量网络请求。
  Widget buildApp(FakeWindowController win) => MaterialApp(
        home: MainPage(
          config: AppConfig(apiUrl: 'https://x', apiKey: 'k'),
          configService: ConfigService(tmpDir),
          llm: LlmService(LogService(tmpDir)),
          log: LogService(tmpDir),
          l10n: LocalizationService()..initialize('zh'),
          window: win,
        ),
      );

  testWidgets('置顶 checkbox 触发 setAlwaysOnTop(true)', (tester) async {
    final win = FakeWindowController();
    await tester.pumpWidget(buildApp(win));
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(win.onTop, contains(true));
  });

  testWidgets('点击折叠三角触发 setHeight', (tester) async {
    final win = FakeWindowController();
    await tester.pumpWidget(buildApp(win));
    await tester.pump();
    // 展开态三角为 arrow_drop_up；点击触发折叠 → setHeight 被调用。
    await tester.tap(find.byIcon(Icons.arrow_drop_up).first);
    await tester.pump();
    expect(win.heights, isNotEmpty);
  });
}
```

> 说明：用 `tester.pump()` 而非 `pumpAndSettle()`——主页面有 `Timer.periodic`（6s/60s）在跑，`pumpAndSettle` 会因定时器永不空闲而超时。`url` 不含 `bigmodel.cn`，`_queryUsage` 直接 return，测试不发网络请求。

- [ ] **Step 6: 运行测试 + 手动验证**

```bash
flutter test test/ui/main_page_test.dart
flutter run -d windows
```

期望：测试 PASS；手动验证界面与交互（三行用量、折叠、置顶、配置浮层、结果浮层、语言切换）。

- [ ] **Step 7: Commit**

```bash
git add codingplan_refresh/lib/ui codingplan_refresh/test/ui
git commit -m "feat(ui): 平移主界面与配置/结果浮层"
```

---

### Task 13: 入口串联与主题

**Files:**
- Create: `codingplan_refresh/lib/app.dart`
- Modify: `codingplan_refresh/lib/main.dart`

**Interfaces:**
- Consumes: 所有 services + platform + ui
- Produces: 可运行应用。

- [ ] **Step 1: 实现 main.dart**

用以下内容**完整替换** `codingplan_refresh/lib/main.dart`：

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'models/app_config.dart';
import 'services/config_service.dart';
import 'services/llm_service.dart';
import 'services/localization_service.dart';
import 'services/log_service.dart';
import 'platform/window_controller.dart';
import 'platform/single_instance.dart';
import 'ui/main_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 单实例（Windows 互斥体检测；已有实例则退出）
  if (!SingleInstance().ensure()) {
    exit(0);
  }

  // 数据目录：复用旧版路径，兼容读旧 config.dat。
  // Windows: %APPDATA%/CodingPlanTimeRefresh；macOS: 需对齐旧 MacCatalyst 落盘路径。
  final dataDir = await _resolveDataDir();
  final configService = ConfigService(dataDir);
  final log = LogService(dataDir);
  final llm = LlmService(log);
  final l10n = LocalizationService();

  final config = configService.load();
  l10n.initialize(config.language);

  final window = WindowController();
  await window.setup(
    width: ConfigService.expandedWidth,
    height: config.isCollapsed ? ConfigService.collapsedHeight : ConfigService.expandedHeight,
    alwaysOnTop: config.isAlwaysOnTop,
  );

  runApp(_App(config: config, configService: configService, llm: llm, log: log, l10n: l10n, window: window));
}

Future<Directory> _resolveDataDir() async {
  // 旧版 Windows 用 %APPDATA%/CodingPlanTimeRefresh。
  // path_provider 的 getApplicationSupportPath 在 Windows 上指向
  // %APPDATA%\<publisher>\<app>，需显式拼到旧路径以保证兼容。
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    final dir = Directory('$appData${Platform.pathSeparator}CodingPlanTimeRefresh');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
  // macOS：先尝试旧 MacCatalyst 的常见落盘位置，再回退到 path_provider 默认。
  // 实现者：在 Mac 上实测旧 config.dat 真实路径（见 spec §5.4），
  // 在此按「先查旧路径，再回退默认」的顺序返回。
  final support = await getApplicationSupportDirectory();
  return support;
}

class _App extends StatelessWidget {
  final AppConfig config;
  final ConfigService configService;
  final LlmService llm;
  final LogService log;
  final LocalizationService l10n;
  final WindowController window;
  const _App({required this.config, required this.configService, required this.llm, required this.log, required this.l10n, required this.window});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Coding Plan Time Refresh',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF2D2D30)),
      home: MainPage(
        config: config,
        configService: configService,
        llm: llm,
        log: log,
        l10n: l10n,
        window: window,
      ),
    );
  }
}
```

> **macOS 配置路径前置验证（spec §5.4）**：`_resolveDataDir` 在 macOS 上必须返回旧 `config.dat` 所在目录。实现者首步在 Mac 上定位旧文件真实绝对路径（典型候选：`~/Library/Application Support/CodingPlanTimeRefresh/` 或旧 MacCatalyst bundle 容器路径），填入此处。

- [ ] **Step 2: 运行 + 手动验证（Windows）**

```bash
cd codingplan_refresh
flutter run -d windows
```

期望：窗口出现，配置从旧版 `%APPDATA%\CodingPlanTimeRefresh\config.dat` 继承（无需重填），三行用量显示，定时器运行，折叠/置顶/配置/结果浮层正常。

- [ ] **Step 3: 全量测试**

```bash
flutter test
```

期望：所有单测 PASS。

- [ ] **Step 4: Commit**

```bash
git add codingplan_refresh/lib/main.dart codingplan_refresh/lib/app.dart
git commit -m "feat: 入口串联，单实例与数据目录解析"
```

---

### Task 14: 发布脚本与体积核验

**Files:**
- Create: `codingplan_refresh/publish-win.bat`
- Create: `codingplan_refresh/publish-mac.sh`

**Interfaces:**
- Consumes: 完整应用
- Produces: 各平台 release 产物 + 体积报告（须 < 40 MB）。

- [ ] **Step 1: Windows 发布脚本**

创建 `codingplan_refresh/publish-win.bat`：

```bat
@echo off
setlocal
set PUBLISH_DIR=build\windows\x64\runner\Release
rmdir /s /q build 2>nul
flutter build windows --release
if %errorlevel% neq 0 goto :error
echo --- 体积核验 ---
powershell -Command "$d='%PUBLISH_DIR%'; $mb='{0:N2}' -f ((Get-ChildItem $d -Recurse | Measure-Object Length -Sum).Sum/1MB); Write-Host \"Windows Release 体积: $mb MB\""
exit /b 0
:error
echo Publish failed.
exit /b 1
```

- [ ] **Step 2: 执行 Windows 发布并核验体积**

```bash
cd codingplan_refresh
cmd //c publish-win.bat
```

期望：编译成功；体积 **< 40 MB**（预期 ~20-25 MB）。若超 40 MB，加 `--split-debug-info=build\symbols` 重测；仍超则上报（spec §13 约定与用户确认是否放宽）。

- [ ] **Step 3: macOS 发布脚本**

创建 `codingplan_refresh/publish-mac.sh`（在 Mac 上执行）：

```bash
#!/usr/bin/env bash
set -e
PUBLISH_APP="build/macos/Build/Products/Release/codingplan_refresh.app"
flutter build macos --release
echo "--- 体积核验 ---"
du -sh "$PUBLISH_APP"
```

- [ ] **Step 4: （Mac 环境）执行 macOS 发布并核验**

```bash
cd codingplan_refresh
chmod +x publish-mac.sh && ./publish-mac.sh
```

期望：`.app` 生成；体积 **< 40 MB**（预期 ~30-40 MB）。

- [ ] **Step 5: Commit**

```bash
git add codingplan_refresh/publish-win.bat codingplan_refresh/publish-mac.sh
git commit -m "build: 发布脚本与体积核验（<40MB）"
```

---

### Task 15: 旧版下线（验证全部通过后）

**Files:**
- Delete: `CodingPlanTimeRefresh/`（旧 MAUI 子目录）
- Delete: `publish-win.bat`、`publish-mac.sh`（仓库根的旧脚本）
- Modify: `README.md`、`README.en.md`、`CLAUDE.md`

> **前置闸口**：必须先按 spec §12.1 在双平台完成 10 项验收（单实例/窗口控制/配置继承/定时触发/用量/手动触发/语言/日志/体积/单测）。任一项未过则**不得**执行本任务。

- [ ] **Step 1: 确认验收清单全部通过**

逐项核对 spec §12.1 的 10 条，双平台各过一遍。未全过 → 停止，回到对应 Task 修复。

- [ ] **Step 2: 删除旧 MAUI 项目与旧发布脚本**

```bash
cd "D:/My/Project/Common/Other/CodingPlanTimeRefresh"
git rm -r CodingPlanTimeRefresh
git rm publish-win.bat publish-mac.sh
```

- [ ] **Step 3: 更新 README**

`README.md` / `README.en.md`：将「构建与运行」「发布」章节改为 Flutter 命令（`flutter build windows/macos`），移除 .NET / MAUI 相关说明。新子目录说明指向 `codingplan_refresh/`。

- [ ] **Step 4: 更新 CLAUDE.md**

`CLAUDE.md` 的「构建与运行」「架构」「关键文件」章节：替换为 Flutter 项目结构（`codingplan_refresh/lib/` 分层、`flutter build` 命令、依赖清单）。删除 MAUI/WinUI/MacCatalyst 描述。文件访问范围改为 `codingplan_refresh/`。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: 下线旧 MAUI 版，README/CLAUDE.md 切换到 Flutter"
```

---

## 实现顺序与闸口

```
T1 脚手架
  └─ T2 AES（验证①：加解密对称 + 算法参数与旧版一致即兼容）
       └─ T3 配置（闸口②：旧 config.json 迁移、往返）
              └─ T4 日志 ─ T5 SSE ─ T6 用量解析
                      └─ T7 LLM（集成 4/5/6）
                             └─ T8 调度 ─ T9 本地化
                                    └─ T10 窗口 ─ T11 单实例
                                           └─ T12 UI ─ T13 入口
                                                  └─ T14 发布（体积闸口③：<40MB）
                                                         └─ T15 下线（验收闸口④：§12.1 全过）
```

**四个硬闸口**（不过则不前进）：① AES 兼容、② 配置迁移、③ 体积 < 40MB、④ 验收清单全过。
