/// 设置窗口打开器抽象：隔离多窗口实现（生产用 desktop_multi_window，测试用 fake）。
///
/// 主窗口点「设置」调 [open] 创建独立设置窗口并进入模态；设置窗口关闭时经 [onClosed]
/// 回传「是否有保存」布尔，主窗口据此决定是否 reload 配置。设置窗口本身不持有
/// AppConfig 引用，唯一数据媒介是 config.dat 文件（见设计 spec §3/§5）。
abstract class SettingsWindowOpener {
  /// 创建并显示设置窗口（独立 OS 窗口）。主窗口在调用后自行进入模态遮罩态。
  Future<void> open();

  /// 注册关闭回调。[saved]=true 表示用户在设置窗口点了保存（已写盘）；
  /// false 表示取消/异常关闭。回调在主窗口 engine 触发。
  void onClosed(void Function(bool saved) cb);
}
