import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:codingplan_refresh/models/usage_info.dart';
import 'package:codingplan_refresh/services/usage_provider.dart';

/// 火山方舟用量：通过本地 arkcli 子进程查询 `arkcli usage plan`，10s 超时。
/// runner 抽象便于测试注入（生产用默认 _realRunner 调 Process.start，超时 kill 子进程）。
typedef ArkRunner = Future<String> Function({required List<String> args, required Duration timeout});

class VolcArkUsageProvider implements UsageProvider {
  final ArkRunner runner;
  VolcArkUsageProvider({ArkRunner? runner}) : runner = runner ?? _realRunner;

  static Future<String> _realRunner({required List<String> args, required Duration timeout}) async {
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
      final stdout = await proc.stdout.transform(utf8.decoder).join().timeout(
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
    //    若返回 refresh_token invalid（arkcli 的 STS 临时凭证未落地），延迟 1s 重试一次。
    final first = await _runSafe(['usage', 'plan']);
    final usageStdout = await _maybeRetryOnRefreshToken(first, ['usage', 'plan']);
    if (usageStdout.isError) {
      return UsageResult('火山方舟', [], usageStdout.error!);
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

  /// 若调用结果含 refresh_token invalid 错误，延迟 1s 重试一次（arkcli 的 STS
  /// 临时凭证偶发未落地，重试通常即恢复）。否则原样返回。
  Future<_RunResult> _maybeRetryOnRefreshToken(
      _RunResult first, List<String> args) async {
    final errText = first.isError
        ? first.error!
        : _extractError(first.value ?? '');
    if (!errText.contains('The request parameter refresh_token is invalid')) {
      return first;
    }
    await Future.delayed(const Duration(seconds: 1));
    return _runSafe(args);
  }

  /// 从 usage plan stdout 提取 ok:false 的 error.message（用于判 refresh_token 错误）。
  String _extractError(String stdout) {
    try {
      final doc = jsonDecode(stdout) as Map<String, dynamic>;
      if (doc['ok'] == false) {
        final err = doc['error'];
        if (err is Map) return err['message'] as String? ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// 调用 arkcli 子命令，统一处理异常 → (error 不为 null 即失败)。
  Future<_RunResult> _runSafe(List<String> args) async {
    try {
      final stdout =
          await runner(args: args, timeout: const Duration(seconds: 10));
      return _RunResult(stdout);
    } on ProcessException catch (e) {
      final msg = e.message;
      if (msg.contains('命令找不到') ||
          msg.contains('命令不存在') ||
          msg.contains('not found') ||
          msg.contains('系统找不到') ||
          e.toString().contains('No such file') ||
          e.errorCode == 2) {
        return _RunResult.withError('arkcli 未安装，参考 README');
      }
      return _RunResult.withError(msg.isEmpty ? '查询失败，未找到数据' : msg);
    } on TimeoutException {
      return _RunResult.withError('查询超时');
    } catch (_) {
      return _RunResult.withError('查询失败，未找到数据');
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
        final msg = err is Map ? (err['message'] as String? ?? '查询失败，未找到数据') : '查询失败，未找到数据';
        return _ParsedUsage('火山方舟', '', const [], msg);
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
        usageItems.add(UsageItem(key, percent.toDouble(), resetAt is int ? resetAt : null));
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
