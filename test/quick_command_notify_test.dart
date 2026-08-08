// v74 回归测试：快捷指令变化通知——
// QuickCommandService add/update/delete 后 notifyListeners，
// 聊天页缓存列表能及时重载（不再等下次进页面）
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/quick_command.dart';
import 'package:pocket_inn/services/quick_command_service.dart';
import 'package:pocket_inn/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pocket_inn_test_qc_');
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
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('v74 QuickCommandService 变化通知', () {
    test('add 后触发 notifyListeners', () async {
      final service = QuickCommandService.instance;
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.add(
        QuickCommand(
          id: 'test-new-1',
          name: '测试指令',
          prompt: '测试内容',
          order: 99,
          type: QuickCommandType.direct,
        ),
      );
      service.removeListener(listener);
      expect(notified, greaterThanOrEqualTo(1), reason: 'add 后应通知监听者');
    });

    test('update 后触发 notifyListeners', () async {
      final service = QuickCommandService.instance;
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.update(
        QuickCommand(
          id: 'test-new-1',
          name: '测试指令-改',
          prompt: '修改内容',
          order: 99,
          type: QuickCommandType.direct,
        ),
      );
      service.removeListener(listener);
      expect(notified, greaterThanOrEqualTo(1), reason: 'update 后应通知监听者');
    });

    test('delete 后触发 notifyListeners', () async {
      final service = QuickCommandService.instance;
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);

      await service.delete('test-new-1');
      service.removeListener(listener);
      expect(notified, greaterThanOrEqualTo(1), reason: 'delete 后应通知监听者');
    });

    test('add 后 loadAll 能立即读到新指令（无缓存）', () async {
      final service = QuickCommandService.instance;
      await service.add(
        QuickCommand(
          id: 'test-new-2',
          name: '即时指令',
          prompt: '即时内容',
          order: 98,
          type: QuickCommandType.prompt,
        ),
      );
      final commands = await service.loadAll();
      expect(
        commands.any((c) => c.id == 'test-new-2'),
        isTrue,
        reason: 'add 后 loadAll 应立即返回新指令',
      );
      await service.delete('test-new-2');
    });

    test('notifyListeners 可被多次监听（多页面缓存同时刷新）', () async {
      final service = QuickCommandService.instance;
      var listenerACount = 0;
      var listenerBCount = 0;
      void listenerA() => listenerACount++;
      void listenerB() => listenerBCount++;

      service.addListener(listenerA);
      service.addListener(listenerB);
      await service.add(
        QuickCommand(
          id: 'test-new-3',
          name: '多监听',
          prompt: '内容',
          order: 97,
          type: QuickCommandType.direct,
        ),
      );
      service.removeListener(listenerA);
      service.removeListener(listenerB);
      await service.delete('test-new-3');

      expect(listenerACount, greaterThanOrEqualTo(1));
      expect(listenerBCount, greaterThanOrEqualTo(1));
    });
  });
}
