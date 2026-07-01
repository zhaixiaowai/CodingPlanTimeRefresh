# Coding Plan Time Refresh（Flutter 版）

定时调用 LLM 并在桌面常驻显示多厂商 API 用量百分比的小工具。

## 支持厂商

- **智谱 BigModel**（bigmodel.cn）：HTTP 查询用量配额。
- **火山方舟 Volcengine Ark**（ark.cn-beijing.volces.com）：用 Access Key / Secret Access Key 查询用量配额。

## 火山方舟用量前置条件

火山方舟用量查询使用火山引擎长效 **Access Key / Secret Access Key**（OpenAPI V4 签名），无需安装本地工具、无需登录态：

1. 在火山引擎控制台 → 密钥管理（IAM）创建一对 Access Key / Secret Access Key。
2. 软件内「设置」中，新增或编辑一个 API URL 含 `ark.cn-beijing.volces.com` 的配置时，会额外出现 **Access Key** / **Secret Access Key** 两个输入框，填入即可。

未配置或 AK/SK 无效时，火山方舟用量框会提示相应错误（如「未配置 Access Key / Secret Access Key」「AK/SK 无效或无权限」）。

## 配置

- 主界面齿轮 → 设置：管理多个模型配置（长按拖动排序、新增、删除、编辑）。
- 每个配置填：名称、API URL、API Key、Model（智谱填模型名如 `glm-5.1`；火山填 endpoint id 如 `ep-xxx`）。火山方舟配置额外填 Access Key / Secret Access Key（仅用量查询用）。
- 厂商由 API URL 自动识别。

## 构建

```bash
flutter build windows --release
```
