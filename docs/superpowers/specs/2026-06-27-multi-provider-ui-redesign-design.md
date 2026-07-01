# 多厂商接入 + 主窗口 UI 重构 设计

- **日期**：2026-06-27
- **状态**：待审阅
- **基础**：已迁移的 Flutter 版（分支 `feature/flutter-migration`，`codingplan_refresh/`）

## 1. 背景与目标

在已完成的 MAUI→Flutter 迁移基础上：

1. **新增多厂商用量接入**：智谱 BigModel + **火山方舟（Volcengine Ark）**，配几个厂商就在主界面上下排列几个用量框，为后续更多厂商预留结构。
2. **主窗口 UI 精简**：去掉折叠三角，顶部改 ☰ 下拉菜单，窗口高度自适应内容；结果/设置改为「放大态」（窗口动态变大），屏幕边缘溢出兼容。

核心诉求：桌面常驻占用最小化（mini 态只显多厂商用量框），结果/设置按需放大。

## 2. 需求清单

- 配置改为**多组**：拖动排序、新增、删除（确认）、编辑。
- 厂商从 API URL 自动识别（智谱 / 火山方舟）。
- **主界面每个 provider 一个用量框**（legend 风格 + 厂商名），上下排列；只显用量，无结果。
- 每 provider 独立用量查询 + 独立结果状态。
- **定时触发**遍历所有 providers（讲笑话保活），更新各自结果状态（不弹结果区）。
- **手动触发面板**（放大态）：下拉选 provider → 结果区显示该 provider 结果状态；手动触发实时流式。
- 火山方舟用量通过本地 `arkcli` 工具（cmd 子进程）查询。
- mini 高度自适应；放大态 420×520；屏幕边缘溢出兼容。
- README 增加火山方舟 arkcli 安装说明。

## 3. 厂商识别（URL 推断）

| URL 包含 | 厂商 | 用量查询方式 |
|---|---|---|
| `bigmodel.cn` | 智谱 BigModel | HTTP GET `quota/limit` |
| `ark.cn-beijing.volces.com/api/` | 火山方舟 | cmd 子进程 `arkcli usage plan` |
| 其他 | 未知厂商 | 不查用量，框显示「未知厂商，不支持用量查询」 |

厂商由每个 provider 的 `apiUrl` 独立推断，只读显示。

## 4. 数据模型

### 4.1 ProviderConfig（持久化，每个厂商一组）

```dart
class ProviderConfig {
  final String id;     // 稳定唯一标识（创建时生成），拖动排序不变
  String name;         // 用户自定义名称，如「我的智谱」
  String apiUrl;
  String apiKey;
  String model;        // 智谱: glm-5.1；火山: endpoint id 如 ep-xxx
}
```

### 4.2 AppConfig（持久化）

```dart
class AppConfig {
  List<ProviderConfig> providers;          // 多组，顺序即显示顺序
  bool isAlwaysOnTop;
  String? language;                        // 'zh'/'en'/'auto'
  Map<String, String> lastTriggerKeys;     // key=provider.id → 该 provider 的 LastAutoTriggerKey（定时去重，独立）
}
```

- 旧字段 `IsCollapsed` 移除（不再有折叠态）。
- 旧字段 `LastAutoTriggerKey`（单值）→ 迁为 `lastTriggerKeys[providers[0].id]`。

### 4.3 UsageResult（每 provider 查询结果，运行时）

```dart
class UsageItem {
  final String labelKey;     // 'token5h'/'tokenWeekly'/'tokenMonthly'/'mcpMonthly'
  final double percentage;
  final int? resetAtMs;
}

class UsageResult {
  final String vendorTitle;       // 「智谱 Pro」「火山方舟 Personal」
  final List<UsageItem> items;    // 成功时的用量行
  final String? errorMessage;     // 非 null=失败/无数据，框内显示此消息
}
```

### 4.4 ResultState（每 provider 结果状态，运行时不持久化）

```dart
class ResultState {
  String resultText;
  String resultHeader;
  bool isBusy;        // 单次调用占用
  bool isRetrying;    // 重试循环占用（与 isBusy 分工，沿用现有设计）
}
```

每 provider 一份（`Map<String, ResultState>`，key=provider.id）。定时触发与手动触发**共享**同一 provider 的 ResultState（即"关联"）：定时更新该 provider 的 ResultState（缓存+日志），手动面板切到该 provider 时看到最新结果。

### 4.5 配置迁移（旧 config.dat → 新多组）

- AES key/IV 不变（沿用 `Aes256Cbc`）。
- 旧单组 `ApiUrl/ApiKey/Model/IsAlwaysOnTop/Language/LastAutoTriggerKey` →
  - `providers = [ProviderConfig(id: 新生成, name: '默认', apiUrl, apiKey, model)]`
  - `isAlwaysOnTop`、`language` 直接搬
  - `lastTriggerKeys = {providers[0].id: 旧LastAutoTriggerKey}`
  - `IsCollapsed` 丢弃
- 新版读旧 JSON 时按字段缺失兜底迁移。

## 5. 配置面板（放大态「设置」）

- **`ReorderableListView` 拖动排序**（长按拖动调整 provider 顺序），不显示上移/下移按钮。
- 每项显示：`name` + 推断厂商徽标 + 编辑（展开表单）/ 删除按钮。
- **新增**：追加空白 `ProviderConfig`（生成新 id，默认 name「新配置」），进入编辑。
- **删除**：弹**确认对话框** → 移除；同时清理该 id 的 `lastTriggerKeys` 和运行时 `ResultState`/`UsageResult`。
- **编辑**：name / apiUrl / apiKey / model。
- **语言切换**：zh / en / auto。
- **保存/取消**：保存写回 `AppConfig` 并 `ConfigService.save`；取消放弃。
- 保存后主界面用量框数量/顺序随之更新。

## 6. UsageFrame 组件（legend 风格，每 provider 一个）

主界面上下排列多个，每个对应一个 provider，显示该 provider 的 `UsageResult`。

- **外观**：fieldset legend——带边框的框，标题压在框上边线 `|--- 智谱 Pro ---|`。
- **标题** `vendorTitle`：
  - 智谱：`智谱` + level 首字母大写（level 来自 `quota/limit` 的 `data.level`；缺省只显「智谱」）。
  - 火山方舟：`火山方舟` + edition 首字母大写（edition 来自 `arkcli` 返回 `items[0].edition`）。
- **行**：`UsageResult.items` 动态渲染，每行 = 本地化 label + 重置时间 + 百分比着色（≥80 红 / ≥50 橙 / 其余蓝，沿用 `UsageRow.pctColor`）。
  - 智谱 items：`token5h` / `tokenWeekly` / `mcpMonthly`
  - 火山方舟 items：`token5h`(session) / `tokenWeekly` / `tokenMonthly`（**无 MCP**）
- **条件渲染**：行数随 items 动态。
- **最小高度**：框至少一行高（items 空也不塌陷）。
- **失败/无数据**：items 空 → 框内居中显示 `errorMessage`。

## 7. 用量查询（`UsageProvider` 抽象，每 provider 独立）

### 7.1 接口

```dart
abstract class UsageProvider {
  Future<UsageResult> query();
}
```

按 provider 的厂商实例化。**60s 定时器遍历所有 providers**，每个独立查询，结果存 `Map<String, UsageResult>`（key=provider.id），各框显示各自结果。

### 7.2 智谱实现 `BigmodelUsageProvider`

- 现有 `queryBigmodelUsage` 逻辑搬入，返回 `UsageResult`：
  - vendorTitle = `智谱` + level 首字母大写
  - items = [token5h, tokenWeekly, mcpMonthly]（按 `type` 归类，沿用现有解析）
  - 失败/无数据 → errorMessage = 「查询失败，未找到数据」

### 7.3 火山方舟实现 `VolcArkUsageProvider`

- cmd 子进程 `arkcli usage plan`：`Process.start('arkcli', ['usage', 'plan'])`（Windows 走 `arkcli.cmd` 或 shell）。
- **10s 超时**：`process.kill()` 杀进程，按失败处理。
- 收集 stdout 解析 JSON。
- 成功：vendorTitle = `火山方舟` + `items[0].edition` 首字母大写；periods 映射 `session`→token5h、`weekly`→tokenWeekly、`monthly`→tokenMonthly；取 `percent` + `reset_at`。
- 失败见 §7.4。

### 7.4 火山方舟失败显示

| 情况 | errorMessage |
|---|---|
| arkcli 未安装（`ProcessException`） | 「arkcli 未安装，参考 README」 |
| 返回 `ok:false` | `error.message` 原文 |
| 10s 超时 | 「查询超时」 |
| 解析异常 | 「查询失败，未找到数据」 |

## 8. 主窗口（mini 态，常驻）

- **去掉左上角折叠三角**。
- **顶部栏**：`[☰ PopupMenuButton]`（下拉：设置 / 手动触发）+ `[置顶 checkbox 外露]`。
- **下方**：`UsageFrame` 列表（每 provider 一个，垂直排列；外层 `SingleChildScrollView`，框多时可滚）。
- **无结果区**（结果只在放大态手动面板）。
- **高度自适应**：渲染后测量所有 UsageFrame 实际总高 → `setSize(330, 顶部栏 + 总高 + padding)`；设最小高度阈值，仅内容高度变化超阈值时 setSize，避免抖动。宽度固定 330。

## 9. LLM 触发

### 9.1 定时触发（所有 providers）

- 6s `Timer.periodic` 调 `SchedulerService.checkTrigger`（全局时间，命中 01/07/13/19）。
- 命中：**遍历所有 providers**，每个独立 `_callLlmWithRetry(provider)`（失败重试 3 次×5s，per provider 的 isBusy/isRetrying），更新该 provider 的 `ResultState` 与 `lastTriggerKeys[id]`，写日志。
- **不弹结果区**（mini 无结果）；结果状态缓存供手动面板查看。
- 各 provider 独立并发，互不阻塞。

### 9.2 手动触发（放大态手动面板）

- 放大态「手动触发」面板：顶部 **下拉选 provider**（列所有 providers 的 name）+ 结果区（显示选中 provider 的 `ResultState`：resultHeader + resultText）。
- 点「触发」按钮：调选中 provider 的 `askStream`，实时流式刷新该 provider 的 `ResultState` + 结果区显示（节流 50ms，沿用现有）。
- **切换下拉**：结果区切换显示对应 provider 的最新 `ResultState`（含定时触发已生成的结果）。
- 即定时与手动共享同一 provider 的 ResultState。

## 10. 放大态（设置 / 手动触发）

- 触发：☰ 菜单选「设置」或「手动触发」。
- 窗口放大到统一 **420×520**（容纳多组配置列表/表单/结果；实现时可按内容微调）。
- 保留顶部栏（☰ + 置顶仍可用），放大区在顶部栏下方铺满。
- 「设置」→ §5 配置面板；「手动触发」→ §9.2 手动面板。
- 关闭（✕ / 保存 / 取消）→ 缩回 mini（自适应高度）。
- **位置保留**：缩回 mini 时停在放大后的位置。

## 11. 屏幕边缘溢出兼容

放大到 420×520 时，若窗口左上角 + 目标尺寸超出屏幕工作区：

- 取当前窗口 `getPosition` + 屏幕工作区（优先 `window_manager` 屏幕API，必要时加 `screen_display`）。
- 右超出 → 左移 x = `screenRight - 420`；下超出 → 上移 y = `screenBottom - 520`。
- `setPosition` + `setSize` 一起调。缩回 mini 不修正位置。

## 12. README 更新

- `codingplan_refresh/README.md`（新建，中文，替换 flutter create 默认英文模板）+ 根 `README.md` 增补：
  - 火山方舟用量需先装官方 `arkcli` 并 `arkcli auth login`，附链接 https://console.volcengine.com/ark/region:cn-beijing/docs/82379/2536875
  - 智谱配置说明（URL/Key/Model）。
  - 多组配置说明（拖动排序/新增/删除/编辑）。

## 13. 非目标（本次不做）

- 不在主界面显示 LLM 结果（结果只在放大态手动面板）。
- 不深度解析 arkcli 错误码（仅区分未安装/失败描述/超时）。
- 不做配置导入/导出。
- 不改 AES 加密体系。
- 不为 arkcli 提供自动安装（用户手动装）。

## 14. 风险与对策

| 风险 | 对策 |
|---|---|
| arkcli 未安装/未登录是常态 | 友好提示「arkcli 未安装，参考 README」；不崩溃 |
| cmd 子进程卡死 | 10s 超时 `process.kill()` |
| 多 provider 定时触发并发 | 每 provider 独立 isBusy/isRetrying，互不阻塞 |
| 拖动排序后结果/用量状态错位 | provider 用稳定 `id` 标识，状态 Map 按 id 而非 index |
| 多框高度自适应抖动 | 最小高度阈值 + 仅超阈值才 setSize |
| 放大态边缘兼容多屏/缩放不准 | 用屏幕工作区 API（扣任务栏）；缩回不修正 |
| `Process.start('arkcli')` Windows 需 `.cmd` | 用 `arkcli.cmd` 或 shell；实现时验证 |
| 多组配置迁移破坏旧用户 | 旧单组兜底迁移为 `providers[0]`；AES/JSON 向后兼容 |

## 15. 实现里程碑（供 writing-plans 展开）

1. **数据模型 + 迁移**：`ProviderConfig`(含 id) / `AppConfig`(多组+lastTriggerKeys map) / `UsageResult` / `ResultState` + 旧 config.dat 迁移 + 单测。
2. **UsageProvider 抽象 + 智谱迁移**：现有 bigmodel 查询搬入 `BigmodelUsageProvider` 返回 `UsageResult` + 单测。
3. **火山方舟 arkcli provider**：cmd 调用 + 解析 + 10s 超时 + 失败细化 + 单测（mock Process）。
4. **UsageFrame 组件**：legend 框 + 动态行 + 最小高度 + 失败显示 + widget test。
5. **配置面板（多组）**：ReorderableListView 拖动 + 新增/删除确认/编辑 + 迁移 + widget test。
6. **主窗口 mini 重构**：去三角 + ☰ 菜单 + 置顶外露 + 多框垂直排列 + 高度自适应。
7. **LLM 触发**：定时遍历所有 providers（per provider ResultState/重试）+ 手动面板下拉选 provider + 结果区 + 节流。
8. **放大态 + 屏幕边缘兼容**：动态尺寸 420×520 + 边缘平移 + 缩回保留位置。
9. **README + 验收**。
