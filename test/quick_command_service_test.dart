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

  setUp(() async {
    await StorageService.instance.clearAllData();
  });

  group('QuickCommandService', () {
    test('首次使用返回内置默认快捷指令（含分类）', () async {
      final commands = await QuickCommandService.instance.loadAll();
      expect(commands.length, 6);
      expect(commands.map((c) => c.name), contains('继续'));
      expect(commands.map((c) => c.name), contains('时间流逝'));
      expect(commands.map((c) => c.name), contains('下一场景'));
      expect(commands.map((c) => c.name), contains('旁白'));
      expect(commands.map((c) => c.name), contains('详细描写'));
      expect(commands.map((c) => c.name), contains('摄像机视角'));
      expect(commands.every((c) => c.prompt.isNotEmpty), isTrue);
      // 分类：直接发送 vs 询问后发送
      expect(
        commands.firstWhere((c) => c.name == '继续').type,
        QuickCommandType.direct,
      );
      expect(
        commands.firstWhere((c) => c.name == '时间流逝').type,
        QuickCommandType.prompt,
      );
      expect(
        commands.firstWhere((c) => c.name == '旁白').type,
        QuickCommandType.prompt,
      );
    });

    test('添加/加载往返保持自定义指令', () async {
      final service = QuickCommandService.instance;
      await service.add(
        QuickCommand(
          id: service.generateId(),
          name: '自定义指令',
          prompt: '自定义提示词内容',
          order: 99,
        ),
      );
      final commands = await service.loadAll();
      final added = commands.firstWhere(
        (c) => c.name == '自定义指令',
      );
      expect(added.prompt, '自定义提示词内容');
    });

    test('更新与删除', () async {
      final service = QuickCommandService.instance;
      final id = service.generateId();
      await service.add(
        QuickCommand(id: id, name: '旧名', prompt: '旧提示词'),
      );
      await service.update(
        QuickCommand(id: id, name: '新名', prompt: '新提示词'),
      );
      var commands = await service.loadAll();
      expect(commands.any((c) => c.name == '新名'), isTrue);

      await service.delete(id);
      commands = await service.loadAll();
      expect(commands.any((c) => c.id == id), isFalse);
    });

    test('旧 JSON 缺 type 字段时回退为直接发送（兼容）', () async {
      await StorageService.instance.writeJsonMap('quick_commands.json', {
        'version': 1,
        'commands': [
          {'id': 'legacy-1', 'name': '旧指令', 'prompt': '旧提示词', 'order': 0},
        ],
      });
      final commands = await QuickCommandService.instance.loadAll();
      expect(commands.length, 1);
      expect(commands.first.type, QuickCommandType.direct);
    });

    test('插入型（insert）保存/加载往返与 fromValue 兼容', () async {
      final service = QuickCommandService.instance;
      await service.add(
        QuickCommand(
          id: 'insert-1',
          name: '插入地点',
          prompt: '地点：',
          order: 7,
          type: QuickCommandType.insert,
        ),
      );
      final commands = await service.loadAll();
      final inserted = commands.firstWhere((c) => c.id == 'insert-1');
      expect(inserted.type, QuickCommandType.insert);
      // fromValue：新值 / 缺失 / 未知均安全
      expect(QuickCommandType.fromValue('insert'), QuickCommandType.insert);
      expect(QuickCommandType.fromValue(null), QuickCommandType.direct);
      expect(QuickCommandType.fromValue('unknown'), QuickCommandType.direct);
    });

    test('保存后按 order 排序', () async {
      final service = QuickCommandService.instance;
      await service.saveAll([
        QuickCommand(
          id: 'b',
          name: 'B',
          prompt: 'p',
          order: 1,
        ),
        QuickCommand(
          id: 'a',
          name: 'A',
          prompt: 'p',
          order: 0,
        ),
      ]);
      final commands = await service.loadAll();
      expect(commands.first.name, 'A');
      expect(commands.last.name, 'B');
    });

    test('删光全部指令后不重新播种默认指令', () async {
      final service = QuickCommandService.instance;
      final commands = await service.loadAll();
      for (final command in commands) {
        await service.delete(command.id);
      }
      final afterDelete = await service.loadAll();
      expect(afterDelete, isEmpty);
      // 再次添加自定义指令不会被默认指令混入
      await service.add(
        QuickCommand(
          id: service.generateId(),
          name: '唯一指令',
          prompt: 'p',
        ),
      );
      final afterAdd = await service.loadAll();
      expect(afterAdd.length, 1);
      expect(afterAdd.first.name, '唯一指令');
    });

    test('损坏的 JSON 文件回退默认指令不崩溃', () async {
      // 直接写入损坏内容模拟写入中断
      final storage = StorageService.instance;
      await storage.writeJsonMap('quick_commands.json', {
        'version': 1,
        'commands': [
          {'id': 123, 'name': 'broken'}, // 缺 prompt 且 id 类型错误
          'not-a-map',
        ],
      });
      final commands = await QuickCommandService.instance.loadAll();
      expect(commands.length, 6);
      expect(commands.map((c) => c.name), contains('继续'));
    });
  });
}
