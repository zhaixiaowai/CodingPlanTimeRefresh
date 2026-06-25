# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

一个 .NET MAUI 桌面小工具，定时调用 LLM API（兼容 OpenAI 格式，主要对接智谱 BigModel），并在界面上显示 API 用量百分比。目标平台为 Windows（WinUI 3）和 MacCatalyst。UI 语言为中文。

## 构建与运行

源码位于 `CodingPlanTimeRefresh/` 子目录（项目根目录为解决方案文件夹）。

```bash
# 构建 (Windows)
dotnet build CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0

# 运行 (Windows, 免安装包)
dotnet run --project CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0

# 发布 (Windows, 自包含免安装包)
dotnet publish CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0 -c Release -r win-x64

# 构建 (MacCatalyst)
dotnet build CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-maccatalyst
```

无测试项目，无代码检查工具配置。

## 架构

单页面 MAUI 应用，无导航（`AppShell` 仅包含 `MainPage`）。

**核心流程：** `App` 创建固定大小、不可调整的窗口。`MainPage` 运行两个调度器定时器——一个（6秒间隔）检查当前时间是否匹配触发时段（01:00、07:00、13:00、19:00）并调用 LLM；另一个（60秒间隔）轮询 BigModel 用量配额。另有手动触发按钮。

**关键文件（均位于 `CodingPlanTimeRefresh/` 下）：**

- `App.xaml.cs` — 窗口生命周期管理，平台相关的置顶/调整大小/居中逻辑。静态 `MainWindow` 引用供 `MainPage` 更新标题使用。
- `MainPage.xaml.cs` — 全部 UI 逻辑：定时器、流式 LLM 调用、折叠/展开、配置面板浮层、用量显示。
- `LLMService.cs` — 静态 `HttpClient` 服务。`AskStreamAsync` 通过 SSE 流式调用任意 OpenAI 兼容的聊天接口。`QueryBigmodelUsagePercentageAsync` 调用 BigModel 配额 API（详见 `docs/bigmodel-usage-api.md`）。
- `ConfigService.cs` — AES-256-CBC 加密配置文件，存储于 `data/config.dat`。自动从旧版明文 `data/config.json` 迁移。存储 `AppConfig`（API URL、Key、模型、置顶状态、折叠状态、上次触发标识）。
- `AppConfig.cs` — 配置模型类，默认模型为 `glm-5.1`。
- `LogService.cs` — 追加写入日志至 `data/log.txt`。LLMService 会将完整的请求/响应 JSON 记录至此。

**平台特定代码：**

- `Platforms/Windows/App.xaml.cs` — WinUI `MauiWinUIApplication`，通过互斥体（`CodingPlanTimeRefresh_SingleInstance`）实现单实例运行。
- `Platforms/MacCatalyst/` — 标准 `AppDelegate` + `Program` 入口。

## 文件访问范围限制

- 所有文件读取必须限制在 `D:\My\Project\Common\Other\CodingPlanTimeRefresh\`（项目根目录）内。
- 除非用户明确要求，否则不得读取此目录之外的文件。
