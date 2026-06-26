import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 单实例：Windows 用命名互斥体（复刻旧版 CodingPlanTimeRefresh_SingleInstance）。
///
/// mutex 是 OS 内核命名对象——不监听端口、不触防火墙，进程退出 OS 自动释放。
/// macOS/Linux 暂不强制单实例（return true 放行）。
///
/// 实现说明：
/// - win32 6.x 包不再生成 `CreateMutex`/`OpenMutex` 绑定，故通过 `DynamicLibrary`
///   直接解析 kernel32.dll 的 `OpenMutexW` / `CreateMutexW`。
/// - **不依赖 GetLastError**：Dart runtime 可能在 native 调用返回与读取
///   last-error 之间插入其他 Win32 调用把 last-error 清掉（win32 包注释明确提到
///   这点）。改用「OpenMutexW 探测」+「CreateMutexW 占位」两段式，纯看 handle
///   是否为 NULL，稳定可靠。
/// - 互斥体名 `CodingPlanTimeRefresh_SingleInstance` 与 brief/旧版保持一致。
class SingleInstance {
  static const _mutexName = 'CodingPlanTimeRefresh_SingleInstance';

  // OpenMutexW(DWORD dwDesiredAccess, BOOL bInheritHandle, LPCWSTR lpName)
  //   -> HANDLE（已存在则返回句柄，否则 NULL）
  // SYNCHRONIZE(0x00100000) 是等待互斥体所需的最低访问权；用 `MUTEX_ALL_ACCESS`
  // 在普通用户会话里会因权限不足失败，故只用 SYNCHRONIZE。
  static final _OpenMutexW = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
          Pointer Function(Uint32, Int32, Pointer<Uint16>),
          Pointer Function(int, int, Pointer<Uint16>)>('OpenMutexW',
          isLeaf: true);

  // CreateMutexW(LPSECURITY_ATTRIBUTES, BOOL bInitialOwner, LPCWSTR lpName)
  //   -> HANDLE（创建或打开已有；返回非 NULL 即视为本进程持有）
  // native 侧第三参用 Pointer<Uint16>（wchar_t*）：ffi lookupFunction 的 native
  // 签名要求指针元素为 native 类型（Utf16 是 Dart 概念，不能用于 native 签名）。
  static final _CreateMutexW = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
          Pointer Function(Pointer, Int32, Pointer<Uint16>),
          Pointer Function(Pointer, int, Pointer<Uint16>)>('CreateMutexW',
          isLeaf: true);

  /// 返回 true=当前是首实例可继续；false=已有实例（仅 Windows 检测），应退出。
  bool ensure() {
    if (!Platform.isWindows) return true;

    // 用 Arena 自动回收 toNativeUtf16 分配的 native 内存。
    return using((Arena arena) {
      final name = _mutexName.toNativeUtf16(allocator: arena).cast<Uint16>();

      // 1) 先尝试打开已有互斥体——若成功，说明已有实例在跑。
      //    SYNCHRONIZE = 0x00100000；bInheritHandle=FALSE(0)。
      final existing = _OpenMutexW(0x00100000, 0, name);
      if (existing.address != 0) {
        // 已有实例持有同名互斥体，本进程应退出。
        return false;
      }

      // 2) 探测失败（NULL）→ 本进程为首实例，创建互斥体占位。
      //    bInitialOwner=TRUE(1)：本进程持有，进程退出时 OS 自动释放。
      final handle = _CreateMutexW(nullptr, 1, name);
      return handle.address != 0;
    });
  }
}
