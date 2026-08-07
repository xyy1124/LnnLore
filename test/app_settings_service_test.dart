import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/data/app_settings.dart';
import 'package:pocket_inn/services/app_settings_service.dart';
import 'package:pocket_inn/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pocket_inn_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (methodCall) async {
          return tempDir.path;
        });
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.initialize();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppSettingsService 思维链约束开关持久化', () {
    test('默认值为开启', () async {
      final settings = await AppSettingsService.instance.load();
      expect(settings.enableThinkingChainGuard, isTrue);
    });

    test('save 后 load 往返保持关闭状态', () async {
      await AppSettingsService.instance.save(
        const AppSettings().copyWith(enableThinkingChainGuard: false),
      );
      final loaded = await AppSettingsService.instance.load();
      expect(loaded.enableThinkingChainGuard, isFalse);
    });

    test('save 后 load 往返保持开启状态', () async {
      await AppSettingsService.instance.save(
        const AppSettings().copyWith(enableThinkingChainGuard: true),
      );
      final loaded = await AppSettingsService.instance.load();
      expect(loaded.enableThinkingChainGuard, isTrue);
    });

    test('updateAppSettings 切换开关并通知监听器', () async {
      var notified = false;
      void listener() => notified = true;
      appSettingsNotifier.addListener(listener);
      updateAppSettings(enableThinkingChainGuard: false);
      expect(appSettingsNotifier.value.enableThinkingChainGuard, isFalse);
      expect(notified, isTrue);
      appSettingsNotifier.removeListener(listener);
      // 恢复默认，避免影响其他测试
      updateAppSettings(enableThinkingChainGuard: true);
    });
  });
}
