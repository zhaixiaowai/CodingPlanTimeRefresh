import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'models/app_config.dart';
import 'services/config_service.dart';
import 'services/llm_service.dart';
import 'services/localization_service.dart';
import 'services/log_service.dart';
import 'platform/window_controller.dart';
import 'platform/single_instance.dart';
import 'ui/main_page.dart';

/// 单窗口入口（方案 B：设置改为窗口内原地切换视图，不再用多窗口）。
///
/// 单实例检测 → 加载配置 → 初始化窗口（固定尺寸/居中/置顶/失焦半透/无系统标题栏）
/// → runApp。设置按钮在 MainPage 内原地切到 ConfigPanel 视图，无需 desktop_multi_window。
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 单实例（Windows 互斥体检测；已有实例则退出）
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
    // 启动宽度按当前语言（统一英文版宽度 expandedWidth=260）。
    width: ConfigService.widthForLanguage(l10n.current),
    height: ConfigService.expandedHeight,
    alwaysOnTop: config.isAlwaysOnTop,
  );

  runApp(
    _App(
      config: config,
      configService: configService,
      llm: llm,
      log: log,
      l10n: l10n,
      window: window,
    ),
  );
}

Future<Directory> _resolveDataDir() async {
  // 旧版 Windows 用 %APPDATA%/CodingPlanTimeRefresh。
  // path_provider 的 getApplicationSupportPath 在 Windows 上指向
  // %APPDATA%\<publisher>\<app>，需显式拼到旧路径以保证兼容。
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    final dir = Directory(
      '$appData${Platform.pathSeparator}CodingPlanTimeRefresh',
    );
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
  const _App({
    required this.config,
    required this.configService,
    required this.llm,
    required this.log,
    required this.l10n,
    required this.window,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Coding Plan Time Refresh',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF2D2D30),
      ),
      home: MainPage(
        config: config,
        configService: configService,
        llm: llm,
        log: log,
        l10n: l10n,
        window: window,
      ),
    );
  }
}
