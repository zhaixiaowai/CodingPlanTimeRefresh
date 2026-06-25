# 将 CodingPlanTimeRefresh 从 MAUI 迁移到 Flutter 的设计

- **日期**：2026-06-25
- **状态**：待审阅
- **作者**：zxw（由 Claude 协助 brainstorming）
- **一句话需求**：当前所有功能 1:1 平移到 Flutter，样式允许微调，编译产物要明显小于现有 MAUI 版本

---

## 1. 背景与目标

### 1.1 背景

`CodingPlanTimeRefresh` 是一个 .NET MAUI 桌面小工具：定时调用 LLM（OpenAI 兼容接口，主要对接智谱 BigModel）并在界面上显示 API 用量百分比。目标平台 Windows（WinUI 3）与 macOS（MacCatalyst），UI 语言中文（支持 zh/en/auto 切换）。

核心痛点：**MAUI 自包含发布体积过大**。

| 平台 | 当前体积（实测） |
|---|---|
| Windows（`net10.0-windows10.0.19041.0` 自包含） | **约 301 MB** |
| macOS（`net10.0-maccatalyst`） | **约 217 MB** |

这是 .NET 运行时 + MAUI/WinUI 框架的固有开销，与应用本身的简单程度不匹配。

### 1.2 目标

- 用 **Flutter（Dart）** 重写客户端，**1:1 平移现有全部功能**，样式允许微调。
- 编译产物自包含、**不依赖系统 WebView/WebKit**，单平台发布产物 **< 40 MB**。
- Windows 与 macOS **双平台功能对等**（含置顶、禁用最大化等平台特定行为）。
- 兼容读取旧版加密配置，用户升级后配置/置顶/折叠状态无缝继承。
- 新版在根目录新建子文件夹实现，旧 MAUI 项目暂并存，验证通过后再删除。

### 1.3 非目标（YAGNI）

- 不重设计 UI（风格接近即可，不做视觉翻新）。
- 不支持 Linux（旧版也不支持）。
- 不引入状态管理框架（Riverpod/Provider 等）。
- 不引入 `intl` / `gen-l10n`（字符串少，自管理 Map）。
- 不做像素级 1:1 还原（间距、控件默认样式允许微调）。
- 不替换底层加密体系（保留与旧版一致的 AES-256-CBC key/IV 以兼容读取）。

---

## 2. 技术选型

### 2.1 为何排除 Web 框架（Wails / Tauri）

用户明确不想依赖 WebView/WebKit，且界面简单。Web 框架（Wails/Tauri）本质是「Web 前端 + 系统 WebView」，其体积优势来自「蹭系统组件」，与「自包含」诉求冲突；Windows 上 WebView2 在 Win10 并非 100% 内置，是外部依赖点。故排除。

### 2.2 为何选 Flutter

在「自包含 + < 40 MB + 不依赖 WebView + 双平台对等 + 置顶是核心特性」约束下对比三个纯原生候选：

| 维度 | Go + Fyne | **Flutter（Dart）✓** | Rust + Slint/egui |
|---|---|---|---|
| Windows 体积 | ~15-20 MB | **~20-25 MB** | ~5-12 MB |
| macOS 体积 | ~20 MB | **~30-40 MB** | ~8-15 MB |
| **置顶（核心特性）** | 无原生 API，macOS 需 cgo | **`window_manager` 一行** | 需 winit 手写 |
| **禁 macOS zoom 按钮** | 需 cgo | **`macos_window_utils` 支持** | 需原生 |
| 双平台对等的平台特定代码量 | macOS 需自写 cgo + macdriver | **插件封装，零平台代码** | 较多 |
| UI 还原省心度 | ★★★ | **★★★★★** | ★★★★ |
| 后端（SSE/AES/定时）零依赖 | ✓ Go 标准库 | 成熟包，多几个依赖 | reqwest+tokio，较繁琐 |
| 工具链/学习成本 | 低 | 低 | 高 |

**决定性因素**：置顶是这个常驻桌面小工具的灵魂特性，Flutter 的 `window_manager` 跨平台一行实现；而 Fyne 无原生置顶 API，macOS 还需 cgo（必须在 Mac + Xcode 上编译，长期维护 objc 代码）。用户要求双平台对等，放大了 Fyne 的这一弱点。几 MB 的体积差（仍在目标内）不抵窗口控制的开发与维护成本。

### 2.3 核心依赖

| 包 | 用途 |
|---|---|
| `window_manager` | 置顶 / 固定尺寸 / 居中 / 动态 resize（跨平台） |
| `macos_window_utils` | macOS NSWindow 深度控制（禁 zoom、置顶） |
| `http` | SSE 流式（`StreamedResponse` + `LineSplitter`） |
| `encrypt` | AES-256-CBC + PKCS7（复刻旧加密） |
| `path_provider` | AppData 等目录路径 |
| `win32` | Windows 互斥体单实例（仅 Windows） |

---

## 3. 架构设计

### 3.1 仓库结构

根目录新建子目录 `codingplan_refresh/`，与旧 `CodingPlanTimeRefresh/`（MAUI）并列。

```
CodingPlanTimeRefresh/                 # 仓库根
├── CodingPlanTimeRefresh/             # 旧 MAUI 项目（暂留，验证通过后删除）
├── codingplan_refresh/                # ★ 新 Flutter 项目
│   ├── lib/                           # Dart 源码（分层见 3.2）
│   ├── windows/                       # Flutter 生成的 Windows 平台代码
│   ├── macos/                         # Flutter 生成的 macOS 平台代码
│   ├── test/                          # 单元测试
│   └── pubspec.yaml
├── docs/
├── README.md
└── ...
```

### 3.2 项目分层（`lib/`）

```
lib/
├── main.dart                  # 入口：初始化窗口/配置/本地化 → runApp
├── app.dart                   # MaterialApp 根 + 暗色主题(#2D2D30)
├── models/
│   ├── app_config.dart        # 对应旧 AppConfig.cs（7 个字段）
│   └── usage_info.dart        # UsageInfo / LimitInfo
├── services/                  # 纯逻辑层，无 Flutter 依赖，可直接单测
│   ├── config_service.dart    # 加载/保存/迁移（AES 兼容，见 §5）
│   ├── llm_service.dart       # AskStream(SSE) + QueryBigmodelUsage
│   ├── scheduler_service.dart # 两个 Timer.periodic（6s 触发 / 60s 用量）
│   ├── log_service.dart       # 追加 log.txt
│   └── localization_service.dart  # zh/en/auto 运行时切换
├── platform/
│   ├── window_controller.dart # 窗口控制抽象（封装 window_manager）
│   └── single_instance.dart   # 单实例（Win mutex / Mac 文件锁）
├── ui/
│   ├── main_page.dart         # 主界面（对应 MainPage）
│   └── widgets/               # 用量行、折叠三角、配置/结果浮层
└── utils/
    ├── aes.dart               # AES-256-CBC（复刻 key/IV）
    └── sse.dart               # SSE 行解析
```

**分层原则**：`services` 是纯逻辑（不 import Flutter，可直接单测）；`ui` 只管渲染；`platform` 隔离平台差异。业务层只依赖 `platform` 的抽象方法（如 `setAlwaysOnTop(bool)`、`setHeight(double)`），不直接碰平台 API。

### 3.3 状态管理

界面小，使用 `StatefulWidget` + `ValueNotifier`，不引入框架。流式结果通过回调累积后 `setState` 刷新。

---

## 4. 功能平移清单（零删减）

| # | 功能 | 新实现 |
|---|---|---|
| 1 | 定时触发 LLM | `Timer.periodic` 6s → 匹配 01:00/07:00/13:00/19:00 → SSE 流式 → 失败重试 **3 次，间隔 5s** |
| 2 | 用量轮询 | `Timer.periodic` 60s → BigModel 配额 API → MCP月 / 5h token / 周 token 三行百分比 + 重置时间 |
| 3 | 手动触发弹窗 | 流式 chunk 实时渲染到只读文本框 |
| 4 | 置顶 | `windowController.setAlwaysOnTop(bool)` |
| 5 | 折叠/展开 | `setHeight(h)` + 三角形 widget 翻转 + 持久化 `IsCollapsed` |
| 6 | 配置面板 | API URL / Key / Model / 语言 表单浮层 |
| 7 | 本地化 | zh / en / auto，运行时切换 |
| 8 | 窗口控制 | 固定 330×318 / 折叠 120 / 142、居中、不可缩放、单实例 |
| 9 | 日志 | 完整请求/响应 JSON → `log.txt` |
| 10 | 标题栏 | 实时显示主用量百分比 + level |

触发时段、重试次数、间隔、超时（120s）、百分比着色阈值（≥80 红、≥50 橙、其余蓝）、BigModel 判定（API URL 含 `bigmodel.cn`）等**所有可配置常量与阈值，全部沿用旧值**。

---

## 5. 配置兼容方案（关键风险点）

### 5.1 AES 复刻

新版必须能解密旧版 `config.dat`，故采用完全相同的对称参数：

- **Key** = `BASE64("Y2RmN2g5azNxUDZ5V0JuTG1SNXZpM3hYN2tybEk4SFg=")`（32 字节）
- **IV** = `BASE64("UGs0dTl2T3dxWjRuY2xmSA==")`（16 字节）
- **算法**：AES-256-CBC + PKCS7 padding
- Dart 侧用 `encrypt` 包：`Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'))`，与 .NET `Aes.Create()` 默认行为一致。
- JSON 结构与旧 `AppConfig` 完全一致（字段名、大小写、默认值），用 `jsonEncode/Decode` + 字段映射对齐。

### 5.2 配置模型字段（对应旧 `AppConfig.cs`）

| 字段 | 类型 | 默认值 |
|---|---|---|
| `IsAlwaysOnTop` | bool | false |
| `ApiUrl` | string | "" |
| `ApiKey` | string | "" |
| `Model` | string | "glm-5.1" |
| `LastAutoTriggerKey` | string | "" |
| `IsCollapsed` | bool | false |
| `Language` | string? | null（auto） |

### 5.3 迁移链路（复刻旧版三段式迁移）

1. **旧加密 `config.dat`**（系统 AppData 目录）：直接解密读取（主路径）。
2. **旧明文 `config.json`**（`TryLoadLegacyJson`）：若加密文件不存在，读明文 JSON，转存加密格式后删除明文文件。
3. **旧路径迁移**（`MigrateFromOldPath`）：若系统 AppData 无配置，尝试从程序运行目录下的 `data/config.dat` 复制过来。

新版按同一优先级链路查找与迁移。

### 5.4 路径风险（前置验证项）

- **Windows**：旧路径 `%APPDATA%\CodingPlanTimeRefresh\config.dat`（即 `C:\Users\<u>\AppData\Roaming\CodingPlanTimeRefresh\config.dat`）明确。`path_provider` 的 `getApplicationSupportPath` 需对齐到该位置（必要时显式拼接，不依赖默认映射）。
- **macOS（最大风险）**：旧版是 **MacCatalyst**，其 `Environment.SpecialFolder.ApplicationData` 的实际落盘路径与新版 Flutter 原生 macOS 的 `path_provider` 默认目录（`~/Library/...`）**可能不一致**。
  - **对策**：实现第一步，先在 Mac 上实测定位旧 `config.dat` 的真实绝对路径，新版去该路径读取迁移；若两路径不同，按「先查旧路径，再查新路径」的回退顺序加载。

---

## 6. 平台窗口控制

所有平台特定逻辑封装在 `platform/window_controller.dart`，业务层只调抽象方法。

| 需求 | 实现 |
|---|---|
| 置顶 | `windowManager.setAlwaysOnTop(flag)`（双平台一行） |
| 固定尺寸 330×318 / 折叠 120 / 142 | `setMinimumSize` + `setMaximumSize` 锁定 + `setResizable(false)` |
| 禁缩放 / 禁最大化 | `setResizable(false)` + `setMaximumSize` |
| 居中 | `windowManager.center()` |
| 折叠 ↔ 展开动态改高 | `windowManager.setSize(330, h)` |
| **禁 macOS zoom 按钮** | `macos_window_utils` 的 NSWindow styleMask API（仅 `Platform.isMacOS` 下调用） |
| 单实例 | Windows：`win32` `CreateMutexW`（复用互斥体名 `CodingPlanTimeRefresh_SingleInstance`）；macOS：AppData 锁文件独占打开 |

> macOS 禁 zoom 的具体 API 名称以实现时 `macos_window_utils` 最新文档为准；若插件未直接提供「隐藏 zoom 按钮」，则通过 Flutter macOS 的 `MainFlutterWindow.swift` 原生 AppDelegate 注入（修改 NSWindow styleMask，移除 Resizable 位），与旧 MAUI 版 `DisableMacZoomButton` 思路一致。

---

## 7. 核心数据流

### 7.1 触发流（复刻 `OnTimerTick`）

`Timer.periodic(6s)` → 计算当前时段 key `"{yyyy-MM-dd} {HH}:{mm}"` → 命中 01/07/13/19 之一且 `≠ LastAutoTriggerKey` → 写入 key、保存配置 → `CallLLM`（最多重试 3 次，每次间隔 5s）。

### 7.2 SSE 流式（复刻 `AskStreamAsync`）

`http.Client().send(POST, body, stream:true)` → `StreamedResponse` → `response.stream.transform(utf8.decoder).transform(const LineSplitter())` → 逐行：
- 跳过空行；
- `data: [DONE]` 终止；
- 非 `data: ` 前缀跳过；
- 解析 JSON 取 `choices[0].delta.content`，回调累积并刷新 UI；
- 坏 chunk（`JsonException`）跳过。

请求头、响应头、完整请求体、完整响应正文（格式化）全部写入日志；Authorization 头日志中脱敏为 `Bearer ***`。HTTP 超时 120s。

### 7.3 用量流（复刻 `QueryBigmodelUsagePercentageAsync`）

GET `https://open.bigmodel.cn/api/monitor/usage/quota/limit`（Authorization 头直接传 apiKey，无 Bearer 前缀）→ 解析 `data.limits[]` 数组：
- `type == "TIME_LIMIT"` → MCP 月限；
- `type == "TOKENS_LIMIT"` 且 `unit == 3 && number == 5` → 5 小时限；
- 其余 `TOKENS_LIMIT` → 周限。

每项取 `percentage` 与 `nextResetTime`（Unix 毫秒）。仅当 API URL 含 `bigmodel.cn` 时查询（复刻判断）。三行更新 + 标题栏更新（主百分比取 5h → MCP → 0 回退，拼 level）。

---

## 8. 本地化

字符串约 20 条，用 `Map<String, Map<String, String>>` 自管理（`zh` / `en` 两份）。
- `auto`：启动时按系统语言判定（`en` → 英文，其余 → 中文）。
- 运行时切换：切 Map + 全量 `setState` 刷新（复刻 `RefreshUI`）。
- 不引入 `intl` / `gen-l10n`。

需平移的字符串资源来自旧 `AppResources.resx` / `AppResources.en.resx`（含 `JokePrompt`、各 Label、错误格式、占位符等），平移时逐条搬运。

---

## 9. 错误处理与日志（复刻旧行为）

- **SSE 失败**：catch → 写日志 → UI 显示错误（格式 `{0}`）；**自动触发失败时清空 `LastAutoTriggerKey`**，允许下次时段重试。
- **用量查询失败**：静默返回 null（不弹错），对应行留空。
- **日志路径**：与旧版一致（系统 AppData 下 `CodingPlanTimeRefresh/log.txt`），追加写。
- **JSON 格式化**：用 `JsonEncoder.withIndent('  ')`，复刻 `FormatJson`。
- **窗口/折叠异常**：catch 后写日志（复刻 `OnToggleCollapse` 的 try/catch + `LogService.Append`）。

---

## 10. 测试策略（补旧版缺失）

旧版无测试。新版对**纯 services 层**加单元测试（不依赖 Flutter，快且稳），框架用内置 `flutter_test`：

| 测试文件 | 覆盖点 |
|---|---|
| `sse_test.dart` | SSE 行解析、`[DONE]` 终止、坏 chunk 跳过、`data:` 前缀过滤 |
| `aes_test.dart` | 加解密往返；用旧版真实 key/IV 加密一段 JSON，验证新版能解密（兼容性黄金用例） |
| `usage_test.dart` | BigModel JSON → `UsageInfo` 归类（TIME_LIMIT / TOKENS_LIMIT×unit3×number5 / 其余） |
| `scheduler_test.dart` | 触发时段匹配、`LastAutoTriggerKey` 去重、跨天计算 |
| `config_test.dart` | 旧明文 `config.json` 迁移、加密往返、字段默认值 |

UI 层不强求测试。`aes_test.dart` 中「用旧版产物解密」是配置兼容的验收关键。

---

## 11. 构建发布与体积控制

| 平台 | 命令 | 预期产物体积 |
|---|---|---|
| Windows | `flutter build windows --release` | ~20-25 MB（Release 目录：exe + dll + data） |
| macOS | `flutter build macos --release` | ~30-40 MB（`.app`） |

体积控制手段：
- 默认 tree-shake 已开启；
- `--split-debug-info=<dir>` 分离调试符号（减小主产物）；
- 不引入重依赖；
- Windows exe 可选 UPX 压缩进一步减小。

对齐旧版发布流程：新建 `publish-win` / `publish-mac` 脚本（替代 `publish-win.bat` / `publish-mac.sh`）。

---

## 12. 迁移验证与旧版下线

### 12.1 验收标准（双平台各跑一遍）

1. 启动正常，**单实例**生效（二次启动不出现两个窗口）。
2. 窗口固定尺寸、居中、不可缩放/最大化；**置顶**可切换；**折叠/展开**正常并联动窗口高度。
3. **配置从旧版无缝继承**（API URL/Key/Model/置顶/折叠/语言/LastAutoTriggerKey）——Windows 必过，macOS 需先解决 §5.4 路径问题。
4. **定时触发**在 01/07/13/19 点命中并流式出结果，失败按 3 次×5s 重试。
5. **用量轮询**正确显示三行（MCP/5h/周）百分比 + 重置时间，标题栏实时更新。
6. **手动触发**弹窗流式渲染正常。
7. **语言切换**（zh/en/auto）实时生效。
8. **日志**完整记录请求/响应（含脱敏）。
9. 体积：Windows < 40 MB、macOS < 40 MB。
10. 所有 services 单测通过。

### 12.2 旧版下线

全部验收通过后：
- 删除旧 `CodingPlanTimeRefresh/` MAUI 子目录；
- 删除旧 `publish-win.bat` / `publish-mac.sh`；
- 更新 `README.md` / `README.en.md` 指向新版构建方式；
- 更新 `CLAUDE.md` 的「构建与运行」「架构」章节。

---

## 13. 风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| macOS 旧 `config.dat` 路径与新版不一致 | 高 | §5.4：实现首步实测定位旧路径，回退顺序加载 |
| macOS 体积接近 40 MB 上限 | 中 | `--split-debug-info`、精简依赖；若仍超，与用户确认放宽至 ~45 MB 或裁剪资源 |
| `macos_window_utils` 禁 zoom 的确切 API 不确定 | 中 | 实现时按插件最新文档；必要时 `MainFlutterWindow.swift` 原生注入 |
| macOS 文件锁单实例在异常退出后残留 | 低 | 用 `flock`（进程退出自动释放）而非普通独占文件 |
| SSE 在代理/弱网下行为 | 低 | 复刻 120s 超时；坏 chunk 跳过不中断 |
| Flutter 桌面生态演进（API 变更） | 低 | 锁定依赖版本（pubspec 中固定 major） |

---

## 14. 实现里程碑（供后续 writing-plans 展开）

1. **脚手架**：`flutter create` 生成 windows/macos 桌面工程，建立 §3.2 分层目录，配 `pubspec.yaml` 依赖。
2. **配置层**：`aes.dart` + `config_service.dart`，先写 `aes_test.dart` / `config_test.dart` 确认能解密旧 `config.dat`（兼容性闸口，不过则不继续）。
3. **服务层**：`sse.dart` + `llm_service.dart`（含日志）+ `usage_test.dart`。
4. **调度层**：`scheduler_service.dart` + `scheduler_test.dart`。
5. **平台层**：`window_controller.dart`（window_manager + macos_window_utils）+ `single_instance.dart`。
6. **UI 层**：`main_page.dart` + widgets，平移 10 项功能与本地化字符串。
7. **集成**：`main.dart` 串联，双平台联调，按 §12.1 验收。
8. **发布**：发布脚本 + 体积核验，通过后下线旧版。
