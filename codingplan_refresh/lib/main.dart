import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart'
    as dmw;
import 'models/app_config.dart';
import 'services/config_service.dart';
import 'services/llm_service.dart';
import 'services/localization_service.dart';
import 'services/log_service.dart';
import 'platform/window_controller.dart';
import 'platform/single_instance.dart';
import 'platform/settings_window_opener.dart';
import 'ui/main_page.dart';
import 'ui/settings_window.dart';

/// 多窗口入口：按当前 engine 的 arguments 分发到主窗口或设置窗口。
///
/// desktop_multi_window 0.3.0：每个子窗口是独立 Flutter engine，main() 在各 engine
/// 都会执行一次。先 `WindowController.fromCurrentEngine()` 取当前 engine 的 arguments
///（异步；无 Sync 版本——pub cache 源码确认），arguments == 'settings' 即设置窗口。
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 取当前 engine 控制器（主/子窗口 engine 都能取；arguments 为 '' 表示主窗口）。
  // 注意：这是 desktop_multi_window 的 WindowController（dmw 前缀），非本项目的
  // platform/window_controller.dart 封装类——两者同名。
  final currentEngine = await dmw.WindowController.fromCurrentEngine();

  // 子窗口 engine：arguments == 'settings' → 跑设置窗口。
  if (currentEngine.arguments == settingsWindowArguments) {
    await _runSettingsWindow(currentEngine);
    return;
  }

  // 主窗口 engine：单实例检测 + 原有启动流程。
  if (!SingleInstance().ensure()) {
    exit(0);
  }

  final dataDir = await _resolveDataDir();
  final configService = ConfigService(dataDir);
  final log = LogService(dataDir);
  final llm = LlmService(log);
  final l10n = LocalizationService();

  final config = configService.load();
  l10n.initialize(config.language);

  final window = WindowController();
  await window.setup(
    // 启动宽度按当前语言（l10n.initialize 已在上文解析 language）。
    width: ConfigService.widthForLanguage(l10n.current),
    // isCollapsed 字段已移除（多组改造）；启动默认展开态，T6 由窗口状态机决定高度。
    height: ConfigService.expandedHeight,
    alwaysOnTop: config.isAlwaysOnTop,
  );

  runApp(_App(
    config: config,
    configService: configService,
    llm: llm,
    log: log,
    l10n: l10n,
    window: window,
    settingsOpener: DesktopMultiWindowSettingsOpener(),
  ));
}

/// 设置窗口 engine 的启动流程：尺寸/居中/无系统标题栏由 window_manager 自管，
/// onSave/onCancel 经 [settingsChannel] 通知主窗口后 `windowManager.close()` 关自己。
///
/// [selfController] 是当前设置窗口 engine 的控制器（dmw.WindowController，
/// 用于 startDragging 等）。
Future<void> _runSettingsWindow(dmw.WindowController selfController) async {
  final dataDir = await _resolveDataDir();
  final configService = ConfigService(dataDir);
  final l10n = LocalizationService();
  l10n.initialize(configService.load().language);

  // 设置窗口尺寸/居中/无系统标题栏。desktop_multi_window 的 README「Integration with
  // window_manager」明确支持此用法（子窗口 engine 内 window_manager 对当前 engine
  // 的窗口生效）。hiddenAtLaunch 已隐藏，故这里 show 前先把窗口属性配好。
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(420, 560),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  // 设置窗口内拖动：复用主窗口 WindowController 子类（其 startDragging 走
  // windowManager.startDragging，对当前 engine 窗口生效）。
  final windowController = _SettingsWindowController();

  runApp(SettingsApp(
    configService: configService,
    l10n: l10n,
    windowController: windowController,
    onSave: (_) async {
      // 保存：写盘已由 SettingsApp 内 ConfigPanel 完成，这里仅通知主窗口后关自己。
      await settingsChannel.invokeMethod(
        settingsMethodOnClosed,
        {'saved': true},
      );
      await windowManager.close();
    },
    onCancel: () async {
      await settingsChannel.invokeMethod(
        settingsMethodOnClosed,
        {'saved': false},
      );
      await windowManager.close();
    },
  ));
}

/// 设置窗口内复用主窗口 [WindowController] 的拖动能力。
///
/// 主窗口 [WindowController.setup] 会做主窗口专属的尺寸/居中/失焦半透初始化，这里
/// **不调用 setup**（设置窗口尺寸已在 _runSettingsWindow 用 waitUntilReadyToShow 配好）。
/// 仅复用 startDragging（WindowListener mixin 无副作用）。
class _SettingsWindowController extends WindowController {
  // 故意不调 setup：设置窗口属性已由 windowManager.waitUntilReadyToShow 配置。
}

Future<Directory> _resolveDataDir() async {
  // 旧版 Windows 用 %APPDATA%/CodingPlanTimeRefresh。
  // path_provider 的 getApplicationSupportPath 在 Windows 上指向
  // %APPDATA%\<publisher>\<app>，需显式拼到旧路径以保证兼容。
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    final dir =
        Directory('$appData${Platform.pathSeparator}CodingPlanTimeRefresh');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
  // macOS：旧 MacCatalyst 的配置路径与 Flutter 原生 path_provider 的
  // getApplicationSupportDirectory 可能不同，当前直接回退默认目录。
  // 如需迁移旧配置，需在 Mac 上实测旧 config.dat 位置后补探测逻辑。
  final support = await getApplicationSupportDirectory();
  return support;
}

class _App extends StatelessWidget {
  final AppConfig config;
  final ConfigService configService;
  final LlmService llm;
  final LogService log;
  final LocalizationService l10n;
  final WindowController window;
  final SettingsWindowOpener settingsOpener;
  const _App({
    required this.config,
    required this.configService,
    required this.llm,
    required this.log,
    required this.l10n,
    required this.window,
    required this.settingsOpener,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Coding Plan Time Refresh',
      theme: ThemeData.dark()
          .copyWith(scaffoldBackgroundColor: const Color(0xFF2D2D30)),
      home: MainPage(
        config: config,
        configService: configService,
        llm: llm,
        log: log,
        l10n: l10n,
        window: window,
        settingsOpener: settingsOpener,
      ),
    );
  }
}
