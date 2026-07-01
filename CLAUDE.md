# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

一个 Flutter（Dart）桌面小工具，定时调用 LLM API（兼容 OpenAI 格式，主要对接智谱 BigModel 与火山方舟），并在桌面常驻显示多厂商 API 用量百分比。目标平台为 Windows 与 macOS。UI 语言为中文（支持 zh/en/auto 切换）。由旧 .NET MAUI 版迁移而来（旧版已下线）。

## 构建与运行

源码位于 `codingplan_refresh/` 子目录。

```bash
cd codingplan_refresh

# 运行 (Windows)
flutter run -d windows

# 构建 (Windows)
flutter build windows --release

# 构建 (macOS)
flutter build macos --release

# 单元测试
flutter test
```

单元测试覆盖 services / platform / models / ui / utils 各层，位于 `codingplan_refresh/test/`。

## 架构

单页面 Flutter 桌面应用，分层：`utils`（AES / SSE / 签名）→ `models` → `services`（配置 / 日志 / LLM / 调度 / 本地化 / 用量 provider，纯 Dart 可单测）→ `platform`（窗口控制 / 单实例）→ `ui`（渲染）。业务层只依赖 `platform` 抽象方法，不直接碰平台 API。

**核心流程：** `main.dart` 初始化窗口（window_manager：固定尺寸 / 居中 / 置顶）、单实例（Windows 互斥体）、数据目录、配置、本地化，随后 `runApp`。`MainPage` 运行两个 `Timer.periodic`——一个（6 秒）检查是否命中触发时段（01:00、07:00、13:00、19:00）并对每个 provider 调用 LLM（失败重试 3 次 × 5 秒）；另一个（60 秒）并行轮询各 provider 用量配额。主界面在 mini 用量视图与设置视图间原地切换。

**关键文件（均位于 `codingplan_refresh/lib/` 下）：**

- `main.dart` — 入口：窗口 / 单实例 / 数据目录 / 配置 / 本地化初始化，`runApp`。
- `ui/main_page.dart` — 全部 UI 逻辑：两个定时器、流式 LLM 调用、用量轮询与显示、mini / 设置视图切换、窗口高度自适应、窗体标题百分比。
- `services/llm_service.dart` — `askStream` 通过 SSE 流式调用任意 OpenAI 兼容聊天接口；请求 / 响应完整 JSON 写日志。
- `services/config_service.dart` — AES-256-CBC 加密配置，存于系统 AppData 下 `config.dat`；兼容读旧 MAUI 版加密 `config.dat` 与旧明文 `config.json`（同 key/IV，自动迁移）。多 provider 配置（`AppConfig.providers`）。
- `services/usage_provider.dart` + `bigmodel_usage_provider.dart` / `volc_ark_usage_provider.dart` — 用量查询：智谱 HTTP、火山方舟 AK/SK（OpenAPI V4 签名）。厂商由 apiUrl 域名识别。
- `services/scheduler_service.dart` — 触发时段匹配与下次触发时刻计算。
- `services/localization_service.dart` — zh / en 字符串表与运行时切换。
- `platform/window_controller.dart` — 封装 window_manager（固定尺寸 / 置顶 / 动态 resize / 标题）。
- `platform/single_instance.dart` — Windows 命名互斥体单实例（`CodingPlanTimeRefresh_SingleInstance`）。

**平台特定：** Windows 与 macOS 平台工程位于 `codingplan_refresh/windows/`、`codingplan_refresh/macos/`（`flutter create` 生成）。禁最大化由 `window_manager` 的 `setResizable(false)` + `setMaximumSize` 实现，不依赖系统 WebView/WebKit。

## 文件访问范围限制

- 所有文件读取必须限制在 `D:\My\Project\Common\Other\CodingPlanTimeRefresh\`（项目根目录）内。
- 除非用户明确要求，否则不得读取此目录之外的文件。
