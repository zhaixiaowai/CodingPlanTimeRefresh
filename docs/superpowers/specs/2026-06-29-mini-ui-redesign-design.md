# mini UI 重构 + 删除手动触发 + 触发时刻可配置 设计

- **日期**：2026-06-29
- **状态**：待审阅
- **基础**：已完成多厂商重构的 Flutter 版（分支 `feature/flutter-migration`，`codingplan_refresh/`）
- **相关**：在 `2026-06-27-multi-provider-ui-redesign-design.md` 已落地代码上的增量改造

## 1. 背景与目标

多厂商重构已全部落地（多组配置、每 provider 用量框、定时遍历触发、放大态设置面板）。但主窗口偏宽偏松，手动触发功能使用价值低，触发时刻硬编码不可调。本次三件事：

1. **删除手动触发功能**：保活由定时触发覆盖，手动触发非必需，删干净（feature 分支未推送）。
2. **UsageFrame 重构为进度条卡片**：每项单行 = label + 进度条(内嵌百分比) + 重置时间，宽度 330→约 280，更 mini 更直观。
3. **触发时刻可配置**：01/07/13/19 改为设置里可调（仅整点，网格勾选）。

多厂商结构、数据模型(ProviderConfig)、配置面板拖动机制、定时触发轮询框架、放大态机制**不动**。

## 2. 删除手动触发

- 删 `lib/ui/widgets/result_panel.dart`（138 行）。
- `main_page.dart`：`_buildEnlarged` 删 `'trigger'` 分支，放大态只留 ConfigPanel。
- 顶部栏 `PopupMenuButton`（☰ + 两项菜单）→ 替换为 `IconButton(Icons.settings)`，点击直接 `_openEnlarged('config')`。
- 删本地化 key：`manualTrigger`、`manualTriggerPopup`、`waitingPlaceholder`、`resultHeader`。**保留** `loading`/`jokePrompt`/`resultTimestamp`（`_callLlmOnce` 定时触发仍写 `rs.text`/`rs.header`，供日志消费）。
- `ResultState` 结构保留（定时触发仍用 `text`/`header`/`isBusy`/`isRetrying`），mini 态不显示结果文本。
- `test/ui/widgets/result_panel_test.dart` 若有则删。

## 3. UsageFrame 进度条卡片

每项单行 `label | 进度条(内嵌百分比) | 重置时间`：

```
智谱 Pro · 下次 19:00          ← legend 标题区（保留 Text.rich + nextTriggerText）
─────────────────────────────────
Token(5H)  ▓▓▓▓░░░░░░░░░ 34% ⟳重置 19:00
Token(周)  ▓▓░░░░░░░░░░░ 12% ⟳重置 06/30
MCP(月)   ▓░░░░░░░░░░░░  8% ⟳重置 07/01
```

- **进度条**：`Stack`——底层灰条 `Color(0xFF3F3F46)` 圆角，上层按 `pctColor` 着色填充（≥80 红 / ≥50 橙 / 其余蓝，沿用 `UsageFrame.pctColor`），`Center(Text('34%'))` 白色文字。
- **百分比内嵌进度条**：百分比文字不再单独占 50px 列，省宽度；0% 时进度条空但仍显示「0%」。
- **重置时间**：右侧 `⟳重置 HH:mm`（今天）/ `⟳重置 MM/dd HH:mm`（跨日），复用 `resetToday`/`resetOther` 本地化资源；`resetAtMs` 为 null 时整段不显示（不占位）。
- **label**：宽度 80→70 右对齐，避免不同长度进度条起点错位。
- **legend**：保留现有 `Transform.translate` 压边框方案 + `Text.rich`（标题 + nextTriggerText）。
- **失败/无数据/loading**：保留现有逻辑（items 空 → `errorMessage` 或 `l10n.t('usageLoading')`），居中显示。
- **最小高度**：仍保一行高。

## 4. 顶部栏简化

```
[⚙] ............ [✓置顶]
```

- 齿轮 `IconButton(Icons.settings, size:14)`，`onPressed: _openEnlarged('config')`。
- 置顶 checkbox + label 保留现状。
- 行高仍锁 20px。
- 放大态覆盖顶部栏机制不变。

## 5. 触发时刻可配置

### 5.1 数据

- `AppConfig` 加 `List<int> triggerHours`（0-23），默认 `[1, 7, 13, 19]`。
- `fromJson` 读 `TriggerHours`（`List<dynamic>`→`List<int>`），缺失→默认 `[1,7,13,19]`；旧单组迁移分支也补默认。
- `toJson` 写 `TriggerHours`。
- 空列表允许（等于关闭定时保活）：`nextTrigger` 返回 null→文本不显示，`checkTrigger` 永不触发。

### 5.2 SchedulerService 参数化

- 原硬编码 `triggerTimes` 常量改名为 `defaultTriggerHours`（`List<int>`，值 `[1,7,13,19]`），作为 `AppConfig.triggerHours` 缺失时的 fallback 默认。
- `checkTrigger(DateTime now, String lastKey, List<int> hours)` —— 内部对每个 hour 生成 `(h, 0)`，判定逻辑不变。
- `nextTrigger(DateTime now, String lastKey, List<int> hours)` —— 同理。
- `main_page`：`_onTriggerTick`/`_updateNextTrigger` 调用时传 `_config.triggerHours`。
- 正在跑的 6s tick 立即用新列表判定（tick 读 `_config` 即时值，无竞态）。

### 5.3 UI（ConfigPanel）

语言切换下方新增「触发时刻」分区：

```
触发时刻（整点）
□0  ☑1  □2  □3  □4  □5
□6  ☑7  □8  □9  □10 □11
□12 ☑13 □14 □15 □16 □17
□18 ☑19 □20 □21 □22 □23
```

- 状态 `Set<int> _triggerHours`（`initState` 从 `widget.initial.triggerHours` 初始化为 `Set`）。
- 24 个紧凑勾选按钮，`Wrap` 或 `GridView.count(crossAxisCount: 6)`，放大态宽 420 够放。
- 保存时 `next.triggerHours = _triggerHours.toList()..sort()`。
- 本地化加 `triggerTimesLabel`（zh「触发时刻（整点）」/ en「Trigger Hours」）。
- 保存后 `_onConfigSaved` 同步 `_config.triggerHours`，下个 6s tick 立即按新时刻判定。

## 6. 改动文件清单

| 文件 | 操作 |
|---|---|
| `lib/ui/widgets/usage_frame.dart` | `_row` 重构：进度条 Stack + 百分比内嵌 + 重置右显 |
| `lib/ui/main_page.dart` | 顶部栏 PopupMenu→齿轮；删 trigger 分支；触发用 `_config.triggerHours` |
| `lib/ui/widgets/result_panel.dart` | **删除** |
| `lib/models/app_config.dart` | 加 `triggerHours` 字段 + 序列化 + 迁移默认 |
| `lib/services/scheduler_service.dart` | `checkTrigger`/`nextTrigger` 收 `List<int> hours` 参数 |
| `lib/ui/widgets/config_panel.dart` | 加触发时刻网格勾选 UI |
| `lib/services/localization_service.dart` | 删 4 个 ResultPanel key；加 `triggerTimesLabel` |
| `test/ui/widgets/usage_frame_test.dart` | 断言 `find.text`→`find.textContaining`（百分比内嵌进度条） |
| `test/services/scheduler_service_test.dart` | 加 hours 参数用例（默认/自定义/空列表） |
| `test/models/app_config_test.dart` | 加 triggerHours 迁移默认/序列化用例 |
| `test/ui/widgets/result_panel_test.dart` | 若有则删 |

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| SchedulerService 从静态常量改参数化 | 所有调用点同步改；加测试覆盖空列表/默认/自定义 |
| 删本地化 key 误删定时触发仍用的 | grep 逐 key 核实引用：`loading`/`jokePrompt`/`resultTimestamp` 确认保留 |
| 触发时刻保存后正在跑的 6s tick | tick 读 `_config` 即时值，立即生效，无竞态 |
| 进度条 Stack 文字居中 | `Center` 保证居中，无风险 |
| 空列表导致定时保活被关 | 允许（用户有意为之）；legend 下次触发文本隐藏作视觉提示 |
| 旧 config.dat 无 TriggerHours 字段 | `fromJson` 缺失→默认 `[1,7,13,19]`，向后兼容 |

## 8. 非目标（本次不做）

- 不改放大态机制（仍 420×520 + 屏幕边缘兼容）。
- 不改多厂商数据模型与配置面板拖动机制。
- 不在 mini 态显示 LLM 结果。
- 触发时刻不支持分钟级（仅整点）。
- 不做配置导入/导出。
