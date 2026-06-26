import 'package:codingplan_refresh/models/usage_info.dart';

/// 用量查询抽象。每个 provider 一个实现。返回 UsageResult（成功 items 非空 / 失败 errorMessage）。
abstract class UsageProvider {
  Future<UsageResult> query();
}
