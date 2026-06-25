[English](README.en.md) | 中文

# Coding Plan Time Refresh

一个 .NET MAUI 桌面小工具，定时调用 LLM API 并在界面上显示 API 用量百分比。主要用于保持智谱 BigModel 编程套餐额度处于活跃状态。

## 预览

| 正常视图 | 折叠视图 |
|:---:|:---:|
| ![正常视图](previews/normal.png) | ![折叠视图](previews/mini.png) |

| 设置面板 | 触发弹窗 |
|:---:|:---:|
| ![设置面板](previews/setting.png) | ![触发弹窗](previews/makeajoke.png) |

## 功能

- 定时自动触发 LLM（01:00、07:00、13:00、19:00，每 6 秒检查一次）
- 手动触发大模型调用
- 流式显示 LLM 返回结果
- 实时显示 BigModel 用量配额（5H / 周 / 月），目前仅支持智谱 Coding Plan，其他平台后续补充
- 窗口置顶、折叠/展开
- 配置加密存储（AES-256-CBC）
- 支持中英文切换
- 支持 Windows（WinUI 3）和 macOS（MacCatalyst）

## 环境要求

- .NET 10.0 SDK
- Windows 10 1809+ 或 macOS 15.0+

## 构建与运行

```bash
# 构建 (Windows)
dotnet build CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0

# 运行 (Windows)
dotnet run --project CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0

# 发布 (Windows, 自包含)
dotnet publish CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0 -c Release -r win-x64

# 构建 (Mac)
dotnet build CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-maccatalyst
```

也可直接使用项目根目录的发布脚本：

- `publish-win.bat` — Windows 自包含发布并清理多余语言包
- `publish-mac.sh` — macOS 发布

## 配置

首次运行会显示配置面板，填入：

- **API URL** — OpenAI 兼容的聊天接口地址（如 `https://open.bigmodel.cn/api/paas/v4/chat/completions`）
- **API Key** — 对应的 API 密钥
- **Model** — 模型名称（默认 `glm-5.1`）

配置加密存储于 `data/config.dat`。

## 项目结构

```
CodingPlanTimeRefresh/
├── App.xaml.cs              # 窗口生命周期管理
├── MainPage.xaml(cs)        # 主界面 UI 与逻辑
├── LLMService.cs            # LLM 调用与用量查询
├── ConfigService.cs         # 配置加密读写
├── AppConfig.cs             # 配置模型
├── LogService.cs            # 日志服务
├── Resources/Strings/       # 中英文资源文件
└── Platforms/               # 平台特定代码
```

## License

[MIT](LICENSE)
