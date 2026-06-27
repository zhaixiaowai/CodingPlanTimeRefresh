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
    try {
      final stdout = await runner(args: ['usage', 'plan'], timeout: const Duration(seconds: 10));
      return _parse(stdout);
    } on ProcessException catch (e) {
      final msg = e.message;
      // arkcli 未安装（命令找不到）
      if (msg.contains('命令找不到') ||
          msg.contains('命令不存在') ||
          msg.contains('not found') ||
          msg.contains('系统找不到') ||
          e.toString().contains('No such file') ||
          e.errorCode == 2) {
        return const UsageResult('火山方舟', [], 'arkcli 未安装，参考 README');
      }
      // 进程失败但 arkcli 存在（如未登录）→ 直接回显 message
      return UsageResult('火山方舟', [], msg.isEmpty ? '查询失败，未找到数据' : msg);
    } on TimeoutException {
      return const UsageResult('火山方舟', [], '查询超时');
    } catch (_) {
      return const UsageResult('火山方舟', [], '查询失败，未找到数据');
    }
  }

  UsageResult _parse(String stdout) {
    try {
      final doc = jsonDecode(stdout) as Map<String, dynamic>;
      // ok:false → error.message
      if (doc['ok'] == false) {
        final err = doc['error'];
        final msg = err is Map ? (err['message'] as String? ?? '查询失败，未找到数据') : '查询失败，未找到数据';
        return UsageResult('火山方舟', [], msg);
      }
      final items = doc['items'] as List;
      if (items.isEmpty) return const UsageResult('火山方舟', [], '查询失败，未找到数据');
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
      if (usageItems.isEmpty) return UsageResult(title, [], '查询失败，未找到数据');
      return UsageResult(title, usageItems, null);
    } catch (_) {
      return const UsageResult('火山方舟', [], '查询失败，未找到数据');
    }
  }
}
