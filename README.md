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

## Flutter 版（多厂商接入重构）

本仓库正在进行 Flutter 多厂商接入重构（位于 `codingplan_refresh/`），MAUI 版待后续下线，以下为 Flutter 版说明，与上方 MAUI 版并存。

### 支持厂商

- **智谱 BigModel**（bigmodel.cn）：HTTP 查询用量配额。
- **火山方舟 Volcengine Ark**（ark.cn-beijing.volces.com）：用 Access Key / Secret Access Key 查询用量配额。

### 火山方舟用量前置条件

火山方舟用量查询使用火山引擎长效 **Access Key / Secret Access Key**（OpenAPI V4 签名），无需安装本地工具、无需登录态：

1. 在火山引擎控制台 → 密钥管理（IAM）创建一对 Access Key / Secret Access Key。
2. 软件内「设置」中，新增或编辑一个 API URL 含 `ark.cn-beijing.volces.com` 的配置时，会额外出现 **Access Key** / **Secret Access Key** 两个输入框，填入即可。

未配置或 AK/SK 无效时，火山方舟用量框会提示相应错误（如「未配置 Access Key / Secret Access Key」「AK/SK 无效或无权限」）。

### 配置（多组）

- 主界面 ☰ 菜单 → 设置：管理多个模型配置（长按拖动排序、新增、删除、编辑）。
- 每个配置填：名称、API URL、API Key、Model（智谱填模型名如 `glm-5.1`；火山填 endpoint id 如 `ep-xxx`）。火山方舟配置额外填 Access Key / Secret Access Key（仅用量查询用）。
- 厂商由 API URL 自动识别。

### 构建

```bash
cd codingplan_refresh
flutter build windows --release
```

详见 [codingplan_refresh/README.md](codingplan_refresh/README.md)。

## License

[MIT](LICENSE)
