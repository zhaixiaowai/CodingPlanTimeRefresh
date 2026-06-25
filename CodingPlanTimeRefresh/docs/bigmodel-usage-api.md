# 智谱 BigModel 用量查询接口

## Endpoint

`GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`

## Headers

- `Authorization: {API Key}` (直接填 key，不带 Bearer 前缀)
- `Content-Type: application/json` (可选)

## 响应示例

```json
{
  "code": 200,
  "success": true,
  "data": {
    "limits": [
      {
        "type": "TIME_LIMIT",
        "percentage": 10,
        "nextResetTime": 1740000000,
        "unit": 3,
        "number": 5
      },
      {
        "type": "TOKENS_LIMIT",
        "percentage": 15,
        "nextResetTime": 1740000000,
        "unit": 3,
        "number": 5
      },
      {
        "type": "TOKENS_LIMIT",
        "percentage": 30,
        "nextResetTime": 1740000000,
        "unit": 5,
        "number": 1
      }
    ],
    "level": "pro"
  }
}
```

## 字段说明

- `data.limits[].type` — 类型
  - `"TIME_LIMIT"` — MCP 消耗信息
  - `"TOKENS_LIMIT"` — Token 消耗信息
- `data.limits[].percentage` — 当前使用百分比 (0-100)
- `data.limits[].nextResetTime` — 下次重置时间戳 (秒级)
- `data.limits[].unit` — 时间单位
  - `3` — 小时数，具体小时数由 `number` 字段指定
  - `5` 且 `number==1` — 月度
- `data.limits[].number` — 具体数值
- `data.level` — 套餐等级 (lite/pro/max 等)

## 维度识别规则

| 维度 | type | unit | number | 说明 |
|------|------|------|--------|------|
| MCP | TIME_LIMIT | - | - | MCP 调用消耗 |
| 5小时 | TOKENS_LIMIT | 3 | 5 | 5 小时内 Token 消耗 |
| 周/月 | TOKENS_LIMIT | 非(3,5) | - | TOKENS_LIMIT 中除 5 小时外的那个即为周限制 |

## 套餐差异

- 老套餐 (2月12日前): 通常只有一个 TOKENS_LIMIT (5小时额度)
- 新套餐: 会有两个 TOKENS_LIMIT (第一个是5小时，第二个是每周额度)，以及一个 TIME_LIMIT (MCP 消耗)
