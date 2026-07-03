import 'dart:io' show Platform;
import 'dart:math' show Random;

// 对外 HTTP 请求的 User-Agent 与伪装头，按用途区分。

/// 触发大模型（chat completions 流式调用）——伪装为 claude-cli
/// （真实抓包提取的可公用 UA 串）。
const String kLlmUserAgent = 'claude-cli/2.1.198 (external, cli)';

/// 是否 macOS（平台判定单一来源，避免浏览器 UA 与 X-Stainless-OS 等多处分别
/// 判定导致指纹失配，修 V10）。
bool get _isMacOS => Platform.isMacOS;

/// 用量查询（智谱/火山方舟 quota 接口）——伪装为浏览器，按平台切换避免 UA 与
/// 客户端 OS 指纹矛盾（macOS 发 Windows UA 是 bot 信号）。
String get kBrowserUserAgent => _isMacOS
    ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36'
    : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';

/// 用量查询的浏览器伴随头（仅 UA 会被 Cloudflare 判 bot，需补 Accept/Sec-Fetch
/// 等浏览器特征头让指纹自洽，修 V7）。值取浏览器 fetch 跨站 API 调用的典型集合。
Map<String, String> get kBrowserHeaders => {
      'User-Agent': kBrowserUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
    };

/// claude-cli 伪装专用请求头（真实抓包提取；X-Claude-Code-Session-Id 与
/// X-Stainless-Retry-Count 由调用方传入，保证重试同 Session-Id + 递增 retry-count，
/// 修 V1；UA/Authorization/Content-Type 由调用方设）。
///
/// 注意伪装策略固有限制（V2，接受）：本应用调智谱/火山方舟 OpenAI 兼容接口
/// （Bearer 鉴权 + OpenAI body + 厂商 model），与真实 claude-cli（x-api-key +
/// Anthropic body 调 api.anthropic.com）存在协议层矛盾，无法通过改头消除——
/// 网络层 UA+Stainless 头判定为 claude-cli 流量是主要目的，后端忽略未知头。
Map<String, String> claudeCliHeaders({
  required String sessionId,
  int retryCount = 0,
}) => {
      'X-Claude-Code-Session-Id': sessionId,
      'X-Stainless-Lang': 'js',
      'X-Stainless-Runtime': 'node',
      'X-Stainless-Runtime-Version': 'v26.3.0',
      'X-Stainless-Package-Version': '0.94.0',
      // 与 llm_service 实际 120s 超时一致（修 V3，原 600 与实际差 5 倍）。
      'X-Stainless-Timeout': '120',
      // OS 按平台（修 V4：macOS 用 'MacOS' 首字母大写，与 Windows/Linux 约定一致）。
      'X-Stainless-OS': _isMacOS ? 'MacOS' : 'Windows',
      // Arch 按平台（修 V5：Apple Silicon Mac 主流 arm64，Windows x64）。
      'X-Stainless-Arch': _isMacOS ? 'arm64' : 'x64',
      'X-Stainless-Retry-Count': '$retryCount',
      'anthropic-version': '2023-06-01',
      'anthropic-beta': _kAnthropicBeta,
      'anthropic-dangerous-direct-browser-access': 'true',
      'x-app': 'cli',
    };

const String _kAnthropicBeta =
    'claude-code-20250219,interleaved-thinking-2025-05-14,redact-thinking-2026-02-12,'
    'thinking-token-count-2026-05-13,context-management-2025-06-27,'
    'prompt-caching-scope-2026-01-05,mid-conversation-system-2026-04-07,effort-2025-11-24';

/// 生成随机 UUID v4（用于 X-Claude-Code-Session-Id，每次请求新值，模拟
/// claude-cli 每会话不同 ID，避免固定值被指纹）。重试时由调用方复用同值（修 V1）。
String randomUuid() {
  final rand = Random();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // 版本位 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // 变体位 10xx
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
