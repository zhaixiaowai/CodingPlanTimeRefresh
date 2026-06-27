# Coding Plan Time Refresh（Flutter 版）

定时调用 LLM 并在桌面常驻显示多厂商 API 用量百分比的小工具。

## 支持厂商

- **智谱 BigModel**（bigmodel.cn）：HTTP 查询用量配额。
- **火山方舟 Volcengine Ark**（ark.cn-beijing.volces.com）：通过本地 `arkcli` 工具查询用量。

## 火山方舟用量前置条件

火山方舟用量查询依赖官方 `arkcli` 命令行工具，请先安装并登录：

1. 安装 arkcli（参考 https://console.volcengine.com/ark/region:cn-beijing/docs/82379/2536875 ）
2. 执行 `arkcli auth login` 完成登录
3. 软件内通过 `arkcli usage plan` 自动查询

未安装/未登录时，火山方舟用量框会提示「arkcli 未安装，参考 README」。

## 配置

- 主界面 ☰ 菜单 → 设置：管理多个模型配置（长按拖动排序、新增、删除、编辑）。
- 每个配置填：名称、API URL、API Key、Model（智谱填模型名如 `glm-5.1`；火山填 endpoint id 如 `ep-xxx`）。
- 厂商由 API URL 自动识别。

## 构建

```bash
flutter build windows --release
```
