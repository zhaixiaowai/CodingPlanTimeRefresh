import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/usage_provider.dart';

/// 火山方舟用量：通过本地 arkcli 子进程查询 `arkcli usage plan`，10s 超时。
/// runner 抽象便于测试注入（生产用默认 _realRunner 调 Process.start，超时 kill 子进程）。
typedef ArkRunner =
    Future<String> Function({
      required List<String> args,
      required Duration timeout,
    });

class VolcArkUsageProvider implements UsageProvider {
  final ArkRunner runner;
  VolcArkUsageProvider({ArkRunner? runner}) : runner = runner ?? _realRunner;

  static Future<String> _realRunner({
    required List<String> args,
    required Duration timeout,
  }) async {
    // Windows 上 arkcli 是 .cmd；走 runInShell 让 shell 解析。
    // 用 Process.start 而非 Process.run，以便超时时 process.kill 真正杀子进程（Process.run 无句柄，超时会留僵尸 arkcli）。
    //
    // 局限说明（runInShell:true）：经 cmd.exe 启动 arkcli（.cmd → node 子进程），
    // proc.kill(sigkill) 仅杀 cmd.exe shell，arkcli 的 node 子进程可能成孤儿。
    // dart:io 无 Job Object 绑定能力，无法可靠杀整棵子进程树。超时是罕见路径
    // （10s），kill 仍做（比不 kill 强，至少 shell 被杀、stdout 管道关闭）；
    // 下线前评估平台插件方案（如 process_group / windows_task_scheduler）。
    final proc = await Process.start('arkcli', args, runInShell: true);
    try {
      final stdout = await proc.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(
            timeout,
            onTimeout: () {
              // 见上文局限说明：仅杀 shell，arkcli node 子进程可能成孤儿。
              proc.kill(ProcessSignal.sigkill);
              throw TimeoutException('arkcli timeout', timeout);
            },
          );
      final exitCode = await proc.exitCode;
      if (exitCode != 0) {
        // 进程失败（含超时杀掉）：stderr 当失败描述
        final stderr = await proc.stderr.transform(utf8.decoder).join();
        throw ProcessException('arkcli', args, stderr);
      }
      return stdout;
    } catch (_) {
      // 异常路径也确保 kill（proc.kill 对已退出进程是 no-op）
      proc.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }

  @override
  Future<UsageResult> query() async {
    // 1) 用量百分比：arkcli usage plan。
    //    若返回 refresh_token invalid（arkcli 登录凭证过期），直接当作错误返回并提示
    //    用户重新 arkcli auth login（详见 README），不再自动重试——token 真过期时
    //    重试无效，反而让用量查询多等 1s。由 _parseUsage 把该错误转成友好提示。
    final usageStdout = await _runSafe(['usage', 'plan']);
    if (usageStdout.isError) {
      // error 路径（arkcli 非零退出+stderr → ProcessException → _runSafe 透传原始 msg）
      // 也走友好转换，避免 refresh_token 失效走 stderr 时用户看到原始英文错误。
      return UsageResult('火山方舟', [], _friendlyMsg(usageStdout.error!));
    }
    final parsed = _parseUsage(usageStdout.value!);

    // 2) 等级（Pro/Team…）：arkcli plans get → 找 scope==edition（usage plan 的
    //    edition）那条的 tier。失败/格式不符 → fallback 用 edition 拼标题。
    final tier = await _fetchTierForScope(parsed.edition);
    final title = tier != null
        ? '火山方舟 ${tier[0].toUpperCase()}${tier.substring(1)}'
        : parsed.title;
    return UsageResult(title, parsed.items, parsed.errorMessage);
  }

  /// 把原始错误消息转友好提示：refresh_token 失效 → 指引重新登录；空 → 兜底文案。
  /// query 的 error 路径（stderr/ProcessException）与 _parseUsage 的 ok:false 路径共用，
  /// 确保无论 arkcli 把 refresh_token 错误走 stdout 还是 stderr 都转中文友好提示。
  String _friendlyMsg(String msg) {
    if (msg.contains('The request parameter refresh_token is invalid')) {
      return 'tokenExpired';
    }
    // 非空原始错误（arkcli/API 返回的具体信息）原样透传（UI 层 l10n.t 未命中返回自身）；
    // 空则兜底 queryFailed key。
    return msg.isEmpty ? 'queryFailed' : msg;
  }

  /// 调用 arkcli 子命令，统一处理异常 → (error 不为 null 即失败)。
  Future<_RunResult> _runSafe(List<String> args) async {
    try {
      final stdout = await runner(
        args: args,
        timeout: const Duration(seconds: 10),
      );
      return _RunResult(stdout);
    } on ProcessException catch (e) {
      final msg = e.message;
      if (msg.contains('命令找不到') ||
          msg.contains('命令不存在') ||
          msg.contains('not found') ||
          msg.contains('系统找不到') ||
          e.toString().contains('No such file') ||
          e.errorCode == 2) {
        return _RunResult.withError('arkcliNotInstalled');
      }
      // 非空 stderr（具体错误）原样透传；空兜底 queryFailed key。
      return _RunResult.withError(msg.isEmpty ? 'queryFailed' : msg);
    } on TimeoutException {
      return _RunResult.withError('queryTimeout');
    } catch (_) {
      return _RunResult.withError('queryFailed');
    }
  }

  /// 查 arkcli plans get，返回 scope==[scope] 那条的 tier；未找到/格式不符返回 null。
  /// [scope] 来自 usage plan 的 edition（如 personal/team/enterprise），不硬编码。
  Future<String?> _fetchTierForScope(String? scope) async {
    if (scope == null || scope.isEmpty) return null;
    final res = await _runSafe(['plans', 'get']);
    if (res.isError) return null;
    try {
      final doc = jsonDecode(res.value!) as Map<String, dynamic>;
      if (doc['ok'] == false) return null;
      final plans = doc['plans'];
      if (plans is! List) return null;
      for (final p in plans) {
        if (p is! Map<String, dynamic>) continue;
        if (p['scope'] == scope) {
          final tier = p['tier'];
          if (tier is String && tier.isNotEmpty) return tier;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 解析 usage plan stdout → (title, items, errorMessage)。title 用 edition 兜底
  /// （调用方 query 会用 plans get 的 tier 覆盖）。
  _ParsedUsage _parseUsage(String stdout) {
    try {
      final doc = jsonDecode(stdout) as Map<String, dynamic>;
      if (doc['ok'] == false) {
        final err = doc['error'];
        final msg = err is Map ? (err['message'] as String? ?? '') : '';
        // refresh_token 失效（arkcli 登录凭证过期）等错误统一走 _friendlyMsg 转友好提示。
        return _ParsedUsage('火山方舟', '', const [], _friendlyMsg(msg));
      }
      final items = doc['items'] as List;
      if (items.isEmpty) {
        return const _ParsedUsage('火山方舟', '', [], '查询失败，未找到数据');
      }
      final first = items[0] as Map<String, dynamic>;
      final edition = first['edition'] as String? ?? '';
      final title = edition.isEmpty
          ? '火山方舟'
          : '火山方舟 ${edition[0].toUpperCase()}${edition.substring(1)}';
      final periods = first['periods'] as List? ?? [];
      final usageItems = <UsageItem>[];
      for (final p in periods) {
        if (p is! Map<String, dynamic>) continue;
        final label = p['label'] as String?;
        final percent = p['percent'];
        final resetAt = p['reset_at'];
        if (label == null || percent is! num) continue;
        final key = {
          'session': 'token5h',
          'weekly': 'tokenWeekly',
          'monthly': 'tokenMonthly',
        }[label];
        if (key == null) continue;
        usageItems.add(
          UsageItem(key, percent.toDouble(), resetAt is int ? resetAt : null),
        );
      }
      if (usageItems.isEmpty) {
        return _ParsedUsage(title, edition, const [], '查询失败，未找到数据');
      }
      return _ParsedUsage(title, edition, usageItems, null);
    } catch (_) {
      return const _ParsedUsage('火山方舟', '', [], '查询失败，未找到数据');
    }
  }
}

/// 一次 arkcli 子命令调用的结果（value 或 error 二选一）。
class _RunResult {
  final String? value;
  final String? error;
  _RunResult(this.value) : error = null;
  _RunResult.withError(this.error) : value = null;
  bool get isError => error != null;
}

/// usage plan 的解析中间结果（tier 由 query 另查 plans get 覆盖 title）。
class _ParsedUsage {
  final String title;
  final String edition; // usage plan 的 edition，用作 plans get 的 scope 匹配键
  final List<UsageItem> items;
  final String? errorMessage;
  const _ParsedUsage(this.title, this.edition, this.items, this.errorMessage);
}
