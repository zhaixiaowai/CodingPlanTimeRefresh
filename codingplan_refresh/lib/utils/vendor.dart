// 厂商识别（按 LLM API URL 域名判定）。
//
// 单一事实源：`main_page._providerFor`（选 UsageProvider）与
// `config_panel`（厂商显示名 + 是否展示 AK/SK 输入框）共用本判定，
// 避免域名变更时多处不同步导致「设置面板识别但用量查询不识别」的割裂。

/// 火山方舟 LLM API 主机段（用户在设置中填的 chat endpoint）。
/// 注意：用量查询走另一个域名 `ark.cn-beijing.volcengineapi.com`，
/// 见 `VolcArkUsageProvider._host`。
const volcArkApiUrlHost = 'ark.cn-beijing.volces.com';

/// [apiUrl] 是否火山方舟 provider。
bool isVolcArk(String apiUrl) => apiUrl.contains(volcArkApiUrlHost);
