# 无边框标题栏 + 全界面拖动 + 设置独立窗口 设计

日期：2026-06-29
分支：feature/flutter-migration
范围：Flutter 迁移项目 `codingplan_refresh/`

## 1. 背景与目标

当前主窗口用系统原生标题栏（`TitleBarStyle.normal`），设置面板以「放大态覆盖」方式在主窗口内显示（`enlarge` 把窗口撑到 420×520 覆盖 `ConfigPanel`）。

本次改造目标：

1. **隐藏系统标题栏**，自绘顶部控制行。
2. **整个默认（mini 用量）界面可拖动**移动窗口。
3. 顶部一行四个按钮：**置顶 / 设置 / 最小化 / 关闭**。
4. **置顶改为图标切换状态**（两个不同图标互切 + 颜色变化）。
5. **设置界面走独立第二窗口**：真 OS 窗口、模态弹出，关闭后只回传「是否有保存」布尔，主窗口自行重新读取配置文件应用变更。
6. **关闭按钮 = 退出应用**（最小化负责常驻后台；不引入系统托盘）。

## 2. 非目标（YAGNI）

- 不引入系统托盘（关闭即退出，后期可评估）。
- 不做「未保存提示」弹窗（与现有 `ConfigPanel` 取消语义一致，直接放弃）。
- 不迁移主窗口的窗口控制 API 到 `desktop_multi_window`（后期评估，见 §9）。
- 不实现 macOS 真机验证（Windows-first，macOS 留 TODO，延续既有约定）。

## 3. 窗口模型与入口架构

进程内双窗口，各自独立 Flutter engine；单实例互斥体（`SingleInstance`）不挡同进程多窗口。

```
单进程
├─ 主窗口 engine
│   └─ window_manager 接管（现有逻辑保留）
│       TitleBarStyle.hidden + 全界面拖动 + 顶部栏(4 按钮)
│       数据：内存 _config + config.dat 持久化
│
└─ 设置窗口 engine（点「设置」时按需创建）
    └─ desktop_multi_window 接管
        自带 X 关闭按钮 + ConfigPanel
        数据：独立 ConfigService 实例，load/save 同一 config.dat
```

**main() 入口分发**（`desktop_multi_window` 标准模式）：
- 主 main 仍是主窗口入口（`_App` / `MainPage`），保留 `SingleInstance` 检测与 `window_manager` 初始化。
- 注册多窗口 widget builder：当前 engine 按 arguments 判定主窗口 / 设置窗口，分发到不同 widget tree。
- 主窗口点「设置」→ `WindowController.create(WindowConfiguration(arguments: 'settings', ...))` 开设置窗口。

**职责边界（文件级解耦）：**
- 设置窗口**不接收** `AppConfig` 引用、**不回传** `AppConfig` 对象。
- 唯一数据媒介 = `config.dat` 文件：设置窗口自己 `load()` 编辑、自己 `save()` 写盘。
- IPC 只传一个布尔：`onSettingsClosed(saved: true/false)`。
- 主窗口收到 `saved=true` → 自己 `ConfigService.load()` reload → 重建运行时态。

**模态实现：** 主窗口创建设置窗口时盖一层半透遮罩 + `AbsorbPointer` 禁用交互；收到关闭回调后移除。

## 4. 标题栏隐藏 + 全界面拖动 + 顶部栏

**标题栏隐藏：**
- 主窗口：`TitleBarStyle.normal` → `TitleBarStyle.hidden`。
- 设置窗口：`desktop_multi_window` 创建时配置无标题栏（实现期对照其 API）。
- 失焦半透逻辑（窗口 `setOpacity 0.9`）保留，顶部栏跟随窗口透明度（既有方案）。

**全界面拖动：**
- mini body 外包 `GestureDetector(onPanStart: () => windowManager.startDragging())`。
- 按钮行作为子节点：按钮的 tap 与父 pan 在手势竞技场共存——点按钮 → tap 胜出不触发拖动；空白处按住移动 → pan 胜出 → `startDragging`（社区标准模式）。
- 用量框（legend / 进度条）纯展示无交互，整行同样可拖。
- 设置窗口内容也可拖（同模式）。

**顶部栏布局（自绘，取代系统标题栏）：**
```
┌──────────────────────────────────────┐
│                          📌  ⚙  ─  ✕ │  ← 右侧 4 按钮；左侧留白拖动
├──────────────────────────────────────┤
│ 智谱 Pro : 下次触发大模型: 19:00       │
│ 5H  ████████ 34%      重置 09:05      │
│ 周  ██████ 56%        重置 ...        │
└──────────────────────────────────────┘
```
- 一行 4 个 `IconButton`（icon 14px，紧凑高度 ~20px），右侧紧挨排列（窗口控制靠右的桌面惯例 + 尊重用户列出的顺序：置顶→设置→最小化→关闭）；左侧 `Spacer` 兼作拖动区。

**四个按钮：**

| 按钮 | 图标 | 行为 |
|---|---|---|
| 置顶 | `pin_off`（未置顶，灰）/ `push_pin`（已置顶，高亮蓝）—— 两个不同图标互切 | 切换 `setAlwaysOnTop` + 保存配置；去掉「置顶」文字 |
| 设置 | `settings` | 打开设置窗口（模态） |
| 最小化 | `horizontal_rule` | `windowManager.minimize()` |
| 关闭 | `close` | `windowManager.close()` = 退出应用 |

**置顶图标依赖：** `pin_off` 是较新的 Material Symbols 图标；优先用 Flutter 内置 `Icons.pin_off`（若已 expose），否则引入官方轻量 `material_symbols_icons` 包。`push_pin` 内置已有。实现期确认。

## 5. 设置窗口 + IPC + 模态 + 配置 reload

**数据流：**
```
[主窗口] 点「设置」
  → SettingsWindowOpener.open()  （内部 WindowController.create('settings')）
  → 主窗口 setState 进入「设置中」态：半透遮罩 + AbsorbPointer

[设置窗口 engine] SettingsApp
  → ConfigService.load() 自读 config.dat → ConfigPanel(initial)
  用户编辑……
  ├ 点「保存」 → ConfigService.save(next) 写盘
  │           → WindowMethodChannel.invokeMethod(主窗口Id, 'onSettingsClosed', {saved:true})
  │           → 关闭自己
  └ 点「取消」/ X → invokeMethod(..., {saved:false}) → 关闭自己

[主窗口] 收到 onSettingsClosed(saved)
  → if saved: next = ConfigService.load() → _applyConfig(next)
  → setState 移除遮罩、恢复交互
  → _queryAllUsage() 立即刷新用量
```

**设置窗口结构（新文件 `lib/ui/settings_window.dart`）：**
- 极简自绘标题栏：仅一个 `close` 图标 X（=取消不保存）；内容区复用现有 `ConfigPanel`（保存/取消按钮已在面板内）。
- `ConfigPanel.onSave` → `ConfigService.save(next)` 写盘 + IPC `{saved:true}` + 关窗。
- `ConfigPanel.onCancel` / X → IPC `{saved:false}` + 关窗。

**主窗口 reload（`_applyConfig`，提炼自现有 `_onConfigSaved` 的对齐逻辑）：**
- `oldIds` vs `newIds` 对齐运行时态：新增 id 加空 `ResultState`、删除 id 清 `_results`/`_usages`/`lastTriggerKeys`。
- `_config = next`；语言变（`old.language != next.language`）→ `l10n.initialize`。
- `triggerHours` 变 → `_updateNextTrigger()`（复用既有）。
- `setState` 重建 → `_queryAllUsage()`。
- 放大态全组删除（`_openEnlarged`/`_closeEnlarged`/`_onConfigHeight`/`_enlarged`/`_lastEnlargedH`/`_buildEnlarged`）。

**关键隔离抽象 —— `SettingsWindowOpener` 接口：**
```dart
abstract class SettingsWindowOpener {
  Future<void> open();                                  // 创建设置窗口 + 主窗口进模态
  void onClosed(void Function(bool saved) cb);          // 注册关闭回调（含 saved 布尔）
}
```
- 生产实现：`desktop_multi_window` + `WindowMethodChannel`。
- 测试：fake 实现，直接触发 `onClosed` —— 主窗口模态/reload 逻辑可完全 widget 测试，不依赖真实多窗口。
- 主窗口依赖此接口（构造注入，同 `WindowController` 模式）。

## 6. 错误处理

| 场景 | 处理 |
|---|---|
| 设置窗口创建失败 | `open()` try-catch；失败则不进/退出模态 + 日志，主窗口不卡 |
| 设置窗口异常关闭未回传 IPC（主窗口卡遮罩） | **窗口关闭事件兜底**：监听设置窗口 destroyed，无论是否收到 IPC 都移除遮罩。正常流程由 IPC 的 saved 决定是否 reload；异常关闭（未收到 IPC）按 saved=false 处理 |
| reload 读配置失败 | `ConfigService.load` 已有兜底链（解密失败→旧 json→默认 `AppConfig`），不抛 |
| save 写盘失败（磁盘/权限） | catch → 不发 `{saved:true}`、不关设置窗口、提示重试 |
| 拖动 vs 按钮竞技 | GestureDetector pan + 按钮 tap 共存（标准模式），边界可接受 |

## 7. 测试策略

分层测试：

- **单测（纯逻辑，不依赖多窗口/IPC）：**
  - `_applyConfig(next)` 的 provider 增删/语言/triggerHours 对齐（抽纯逻辑或可注入方法）。
  - `ConfigService` save→load 往返。
- **widget 测试（注入 fake `WindowController` + fake `SettingsWindowOpener`）：**
  - 顶部栏 4 按钮：置顶→`setAlwaysOnTop`+存、最小化→`minimize`、关闭→`close`、设置→`opener.open`+显遮罩。
  - 模态：进设置态显遮罩+`AbsorbPointer`；`opener.onClosed(false)` 移遮罩；`onClosed(true)` 移遮罩+reload。
  - 拖动：`onPanStart` 调 `startDragging`。
  - 置顶图标：未置顶=`pin_off`、已置顶=`push_pin`。
- **真实多窗口/IPC 链路：** 难以自动化 → 手动验证（开窗/保存回传/取消/异常关闭兜底），spec 标注。

## 8. 改动影响面

| 文件 | 改动 |
|---|---|
| `lib/main.dart` | 多窗口 engine 分发（主/设置） |
| `lib/ui/main_page.dart` | 顶部栏重构(4 按钮)、删放大态全组、加模态遮罩、`_applyConfig`、依赖 `SettingsWindowOpener` |
| `lib/ui/settings_window.dart` | **新**：SettingsApp + ConfigPanel 容器 + IPC 回传 |
| `lib/platform/window_controller.dart` | `TitleBarStyle.hidden`、加 `minimize()`/`close()`；删 `enlarge`/`shrinkToContent`/`setOpacityForcedActive`（放大态连带删除，`opacityFor` 简化为无 forcedActive） |
| `pubspec.yaml` | + `desktop_multi_window`（+ `material_symbols_icons` 若内置无 `pin_off`） |
| 测试 | 见 §7 |

## 9. 风险与后期评估

- **`desktop_multi_window` 维护风险：** 包 8 个月未更新。通过 `SettingsWindowOpener` 接口隔离，多窗口实现集中在 `settings_window.dart` + 一个 opener 实现，若换方案只改一处，主窗口零侵入。
- **macOS 多窗口未实测：** Windows-first，macOS 留 TODO（延续既有）。
- **主窗口 API 迁移：** 后期评估是否把主窗口的窗口控制也迁移到 `desktop_multi_window`（届时 `window_controller.dart` 重写、单测改、可去掉 `window_manager` 依赖）。当前不做，spec 标注为 future。
