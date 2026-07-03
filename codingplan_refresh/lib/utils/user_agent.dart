import 'dart:io' show Platform;

// 对外 HTTP 请求的 User-Agent，仅用量查询用（触发模型不改 UA，用 dart:io 默认）。

/// 是否 macOS（平台判定单一来源，避免多处分别判定导致指纹失配）。
bool get _isMacOS => Platform.isMacOS;

/// 用量查询（智谱/火山方舟 quota 接口）——伪装为浏览器，按平台切换避免 UA 与
/// 客户端 OS 指纹矛盾（macOS 发 Windows UA 是 bot 信号）。
String get kBrowserUserAgent => _isMacOS
    ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36'
    : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';

/// 用量查询的浏览器伴随头（仅 UA 会被 Cloudflare 判 bot，需补 Accept/Sec-Fetch
/// 等浏览器特征头让指纹自洽）。值取浏览器 fetch 跨站 API 调用的典型集合。
Map<String, String> get kBrowserHeaders => {
      'User-Agent': kBrowserUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
    };
