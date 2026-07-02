[English](README.en.md) | 中文

# Coding Plan Time Refresh

一个 Flutter 桌面小工具，定时调用 LLM API 并在桌面常驻显示多厂商 API 用量百分比。主要用于保持智谱 BigModel 编程套餐等额度处于活跃状态。由旧 .NET MAUI 版迁移而来。

## 预览

| 主视图 | 设置面板 |
|:---:|:---:|
| ![主视图](previews/normal.png) | ![设置面板](previews/setting.png) |

## 功能

- 定时自动触发 LLM 保活：触发时刻可在「设置」中自定义（默认 01:00、07:00、13:00、19:00，每 6 秒检查一次；失败自动重试 3 次，间隔 5 秒；全部取消勾选则关闭定时保活）
- 实时显示多厂商用量配额（智谱 5H / 周 / 月；火山方舟），常驻桌面
- 窗口置顶
- 配置加密存储（AES-256-CBC），兼容继承旧 MAUI 版配置
- 支持中英文切换
- 支持 Windows 与 macOS

## 支持厂商

- **智谱 BigModel**（bigmodel.cn）：HTTP 查询用量配额。
- **火山方舟 Volcengine Ark**（ark.cn-beijing.volces.com）：用 Access Key / Secret Access Key 查询用量配额。

## 火山方舟用量前置条件

火山方舟用量查询使用火山引擎长效 **Access Key / Secret Access Key**（OpenAPI V4 签名），无需安装本地工具、无需登录态：

1. 在火山引擎控制台 → 密钥管理（IAM）创建一对 Access Key / Secret Access Key。
2. 软件内「设置」中，新增或编辑一个 API URL 含 `ark.cn-beijing.volces.com` 的配置时，会额外出现 **Access Key** / **Secret Access Key** 两个输入框，填入即可。

未配置或 AK/SK 无效时，火山方舟用量框会提示相应错误（如「未配置 Access Key / Secret Access Key」「AK/SK 无效或无权限」）。

## 环境要求

- Flutter stable（含桌面支持）
- Windows 10+ 或 macOS

## 构建与运行

源码位于 `codingplan_refresh/` 子目录。

```bash
cd codingplan_refresh

# 运行 (Windows)
flutter run -d windows

# 发布 (Windows)
flutter build windows --release

# 发布 (macOS)
flutter build macos --release
```

## 配置

- 主界面齿轮 → 设置：管理多个模型配置（长按拖动排序、新增、删除、编辑），并可在「触发时刻（整点）」勾选每日自动触发的小时（0-23，默认 1/7/13/19，全不勾则关闭定时保活）。
- 每个配置填：名称、API URL、API Key、Model（智谱填模型名如 `glm-5.1`；火山填 endpoint id 如 `ep-xxx`）。火山方舟配置额外填 Access Key / Secret Access Key（仅用量查询用）。
- 厂商由 API URL 自动识别。
- 配置加密存储，兼容读取旧 MAUI 版的 `config.dat`（AES-256-CBC，同 key/IV，自动迁移）。

## 项目结构

```
codingplan_refresh/
├── lib/
│   ├── main.dart              # 入口：窗口/单实例/配置/本地化初始化
│   ├── models/                # AppConfig、UsageInfo
│   ├── services/              # 配置/日志/LLM/调度/本地化/用量 provider
│   ├── platform/              # 窗口控制、单实例
│   ├── ui/                    # 主界面与 widgets
│   └── utils/                 # AES、SSE、签名
├── test/                      # 单元测试
├── windows/ macos/            # 平台工程
└── pubspec.yaml
```

## License

[MIT](LICENSE)
