# 火山引擎用量查询支持 — 设计存档（已封存）

> 状态：**已封存，暂不实现**。本文档仅记录需求调研成果，便于后续恢复。
> 封存原因：`console.volcengine.com` 控制台接口的鉴权方式（是否需要登录 Cookie）未确定，构成实现阻塞。详见"待解决问题"。
> 创建日期：2026-06-22

## 背景与目标

现有应用通过 `LLMService.QueryBigmodelUsagePercentageAsync` 查询智谱 BigModel 的用量配额，并在界面显示 Mcp / Hour5 / Weekly 三行百分比。`MainPage.xaml.cs` 的 `QueryUsageAsync` 已按 `ApiUrl` 域名分发：

```csharp
if (_config.ApiUrl.Contains("bigmodel.cn"))
    usage = await LLMService.QueryBigmodelUsagePercentageAsync(_config.ApiKey);
else
    return;
```

目标：当 `ApiUrl` 为火山引擎（`https://ark.cn-beijing.volces.com/api/` 开头）时，改走火山引擎控制台用量查询接口，复用同一套 UI 展示。

## 火山引擎接口信息

### 1. 用量查询接口（本次要接入的核心）

- **URL**：`https://console.volcengine.com/api/top/ark/cn-beijing/2024-01-01/GetCodingPlanUsage`
- **方法**：POST
- **Content-Type**：`application/json`
- **请求正文**：`{}`
- **Referer（来路）**：`https://console.volcengine.com/ark/region:cn-beijing/subscription/coding-plan`
- **鉴权头**：`x-csrf-token: <Web csrf Token>`
  - 该 token **不是**用户填写的 API Key，是火山引擎控制台的 Web CSRF Token，需单独配置。
  - 建议字段命名：**Web csrf Token**（待最终确认大小写/空格形式）。

**响应示例：**

```json
{
    "ResponseMetadata": {
        "RequestId": "20260622155136A1015B4927FBD44554CE",
        "Action": "GetCodingPlanUsage",
        "Version": "2024-01-01",
        "Service": "ark",
        "Region": "cn-beijing"
    },
    "Result": {
        "Status": "Running",
        "UpdateTimestamp": 1782114696,
        "QuotaUsage": [
            { "Level": "session",  "Percent": 2.4590175,         "ResetTimestamp": 1782130855 },
            { "Level": "weekly",   "Percent": 1.4308822,         "ResetTimestamp": 1782662400 },
            { "Level": "monthly",  "Percent": 16.025877866666665,"ResetTimestamp": 1784303999 }
        ]
    }
}
```

**字段映射：**
- `Result.QuotaUsage[]` 数组，每项含 `Level` / `Percent` / `ResetTimestamp`。
- `Percent` 为浮点数（非整数），与 BigModel 的整型 `percentage` 不同——解析与显示需支持小数。
- `ResetTimestamp` 为秒级 Unix 时间戳（BigModel 的 `nextResetTime` 为毫秒级）——**单位不同，需注意换算**。
- `Result.Status`（如 `Running`）可选作展示。
- `ResponseMetadata.RequestId` 可记入日志便于排障。

### 2. 套餐类型查询接口（本次预定义扩展点，不实际请求）

- **URL**：`https://console.volcengine.com/api/top/ark/cn-beijing/2024-01-01/ListSubscribeTrade`
- **方法**：POST
- **请求正文**：`{"ResourceTypes":["CodingPlan"],"ResourceNames":[""],"BizInfos":["lite","pro"]}`
- **响应示例：**

```json
{
    "ResponseMetadata": { ... "Action": "ListSubscribeTrade" ... },
    "Result": {
        "InfoList": [
            {
                "ResourceType": "CodingPlan",
                "ResourceName": "",
                "BizInfo": "pro",
                "PayType": "pre",
                "Status": "Running",
                "InstanceID": "tsi-20260617112740-7sh8f",
                "StartTime": "2026-06-17T03:28:12Z",
                "EndTime": "2026-10-17T15:59:59Z",
                "EnableAutoRenew": false,
                "Quantity": 1,
                "Period": "monthly"
            }
        ]
    }
}
```

**本次范围**：仅在代码/配置中预定义该接口的扩展点，**不实际发起请求，不在界面显示 lite/pro**。后续可据此显示套餐类型。

## UI 行映射（已确认：方案 A）

火山引擎 `QuotaUsage` 三档映射到现有 3 行槽位，**行标签保持原样不变**（MCP / Hour5 / Weekly）：

| 火山引擎 `Level` | 对应 UI 行 |
|------------------|-----------|
| `session`  | Mcp 行     |
| `weekly`   | Hour5 行   |
| `monthly`  | Weekly 行  |

> 与 BigModel 的语义差异：BigModel 区分 MCP 与 5 小时 Token 窗口，火山引擎不区分 MCP；火山引擎的月度限额也是 Token 级。复用槽位但语义不同，标签暂不改（如后续要通用化可再讨论）。

## 待解决问题（封存原因所在）

1. **鉴权方式未确定（核心阻塞）**：`console.volcengine.com` 控制台接口通常依赖浏览器登录 Cookie 维持会话，`x-csrf-token` 仅防 CSRF。仅带 token 不带 Cookie 可能返回 401/403。需明确：
   - 是否仅需 `x-csrf-token` 即可通？
   - 还是需要额外拷贝整条 Cookie 串？若需要，配置需新增"Cookie"字段。
   - 恢复实现前应先用浏览器抓包验证最小鉴权要素。

2. **窗口标题主百分比取值**：BigModel 下标题取 `Hour5 ?? Mcp`。火山引擎三档（session/weekly/monthly）下取哪一档作为窗口标题主百分比未定。

3. **百分比小数精度**：火山引擎 `Percent` 为浮点（如 `2.4590175`），界面显示保留几位小数未定（BigModel 是整型直接显示 `N%`）。

4. **Web csrf Token 字段命名最终形式**：`Web csrf Token` / `WebCsrfToken` / `Web CSRF Token` 待定。

## 恢复实现时的接入点清单

- `AppConfig.cs`：新增字段存储 `Web csrf Token`（及可能的 Cookie）。
- `ConfigService.cs`：加密存储新字段（已有 AES 机制，自动覆盖）。
- `MainPage.xaml`：配置面板新增 `Web csrf Token` 输入框（Entry，明文或密码态待定）。
- `MainPage.xaml.cs`：
  - `QueryUsageAsync` 第 349 行的分发逻辑扩展：`ApiUrl` 含 `ark.cn-beijing.volces.com` 或 `volcengine.com` 时走火山引擎分支。
  - 新增火山引擎用量解析，映射到 `UsageInfo`（`Mcp`/`Hour5`/`Weekly`）。
- `LLMService.cs`：新增 `QueryVolcengineUsageAsync(...)`，构造 POST `{}`、带 `x-csrf-token`、`Referer`、`Content-Type: application/json`，解析 `Result.QuotaUsage`。
- `AppResources.resx` / `.en.resx`：新增 `Web csrf Token` 等多语言文案。
- 注意时间戳单位差异（秒 vs 毫秒）与百分比类型差异（浮点 vs 整型）。
