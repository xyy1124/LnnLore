import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/error_handler.dart';
import 'core/service_locator.dart';
import 'data/app_settings.dart';
import 'pages/chat_page.dart';
import 'services/version_check_service.dart';

/// 全局导航 key：用于在启动检查等场景弹出提示。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 注册全局错误处理：避免 release 模式红屏，统一记录未捕获异常
  ErrorWidget.builder = buildAppErrorWidget;
  registerGlobalErrorHandlers();

  // 通过 DI 容器统一注册并初始化所有 service（顺序见 service_locator.dart）
  await setupServiceLocator();

  runApp(const MyApp());

  // 特别版：启动后异步检查 GitHub 新版本（不阻塞启动）
  _checkForUpdateOnLaunch();
}

/// 特别版：启动时自动检查新版本，发现新版本时弹出提示。
/// 节流：距上次成功检查不足 1 小时则跳过（避免每次启动都请求 GitHub API）。
Future<void> _checkForUpdateOnLaunch() async {
  try {
    final service = VersionCheckService.instance;
    if (!await service.isEnabled()) {
      return;
    }
    final lastChecked = await service.getLastChecked();
    if (lastChecked != null &&
        DateTime.now().difference(lastChecked) < const Duration(hours: 1)) {
      return;
    }
    final latestTag = await service.fetchLatestTag();
    if (latestTag == null) {
      return;
    }
    // 上游锚点比较：上游发布的新版本高于 fork 时的版本即提示，
    // 与本地特别版号（1.4.0-special.5）体系独立。
    if (!VersionCheckService.isUpstreamUpdateAvailable(latestTag)) {
      return;
    }
    final navigatorState = appNavigatorKey.currentState;
    if (navigatorState == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(navigatorState.context);
    if (messenger == null) {
      return;
    }
    final owner = await service.getOwner();
    final repo = await service.getRepo();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '上游已发布新版本：$latestTag'
          '（特别版基于 ${VersionCheckService.baselineUpstreamVersion}，可前来获取更新）',
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '查看',
          onPressed: () async {
            try {
              await launchUrl(
                Uri.parse('https://github.com/$owner/$repo/releases'),
                mode: LaunchMode.externalApplication,
              );
            } on Object {
              // 打开失败静默处理
            }
          },
        ),
      ),
    );
  } on Object {
    // 检查失败静默处理，不影响使用
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: appSettingsNotifier,
      builder: (context, settings, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'LnnLore',
          themeMode: settings.colorMode.themeMode,
          theme: buildAppTheme(settings, Brightness.light),
          darkTheme: buildAppTheme(settings, Brightness.dark),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          home: const ChatPage(),
        );
      },
    );
  }
}
