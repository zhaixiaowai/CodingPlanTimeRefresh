import 'package:codingplan_refresh/models/usage_info.dart';

/// 解析 BigModel 配额 API 响应。
///
/// T1 桩化：返回 null（旧的 `UsageInfo`/`LimitInfo` 类型已移除，统一改为
/// `UsageResult`/`UsageItem`，归类逻辑由 T2 重写）。T2 会删除本文件。
UsageResult? parseBigmodelUsage(String jsonBody) {
  return null;
}
