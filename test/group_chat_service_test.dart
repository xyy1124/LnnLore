import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/group_chat_session.dart';
import 'package:pocket_inn/services/group_chat_service.dart';
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

  group('GroupChatService', () {
    test('创建并加载群聊', () async {      final service = GroupChatService.instance;
      final group = await service.create(
        title: 'A × B',
        characterIds: ['char-a', 'char-b', 'char-c'],
      );
      expect(group.sessionCharacterId, 'group:${group.id}');
      expect(isGroupChatCharacterId(group.sessionCharacterId), isTrue);
      expect(parseGroupChatId(group.sessionCharacterId), group.id);

      final loaded = await service.loadById(group.id);
      expect(loaded, isNotNull);
      expect(loaded!.characterIds, ['char-a', 'char-b', 'char-c']);
    });

    test('创建时可指定回复模式（全员回复）并持久化', () async {
      final group = await GroupChatService.instance.create(
        title: 'G',
        characterIds: ['a', 'b'],
        replyMode: 'everyone',
      );
      final loaded = await GroupChatService.instance.loadById(group.id);
      expect(loaded, isNotNull);
      expect(loaded!.parsedReplyMode, GroupChatReplyMode.everyone);
    });

    test('旧数据缺 replyMode 字段回退轮流制', () async {
      // 先创建（含 replyMode），再手动移除该字段模拟旧数据
      final created = await GroupChatService.instance.create(
        title: 'G',
        characterIds: ['a', 'b'],
        replyMode: 'everyone',
      );
      final storage = StorageService.instance;
      final data = await storage.readJsonMap('group_chats.json');
      expect(data, isNotNull);
      final groups = (data!['groups'] as List).cast<Map<String, dynamic>>();
      for (final g in groups) {
        g.remove('replyMode');
      }
      await storage.writeJsonMap('group_chats.json', {
        'version': 1,
        'groups': groups,
      });
      final all = await GroupChatService.instance.loadAll();
      expect(all.any((g) => g.id == created.id), isTrue);
      for (final g in all) {
        expect(g.parsedReplyMode, GroupChatReplyMode.rotation);
      }
    });

    test('轮转游标依次返回成员并循环', () async {
      final service = GroupChatService.instance;
      final group = await service.create(
        title: 'G',
        characterIds: ['char-a', 'char-b', 'char-c'],
      );

      // 游标 0 = 当前发言人 a；每次调用返回下一位并推进
      expect(await service.nextTurnCharacterId(group.id), 'char-b');
      expect(await service.nextTurnCharacterId(group.id), 'char-c');
      expect(await service.nextTurnCharacterId(group.id), 'char-a');
      // 循环
      expect(await service.nextTurnCharacterId(group.id), 'char-b');
      // 游标已推进，持久化后恢复的"当前发言人"应为最后返回者
      final loaded = await service.loadById(group.id);
      expect(
        loaded!.characterIds[loaded.turnIndex % loaded.characterIds.length],
        'char-b',
      );
    });

    test('删除群聊后 loadById 返回 null', () async {
      final service = GroupChatService.instance;
      final group = await service.create(
        title: 'G',
        characterIds: ['char-a', 'char-b'],
      );
      await service.delete(group.id);
      expect(await service.loadById(group.id), isNull);
    });

    test('空成员群聊轮转返回 null', () async {
      final service = GroupChatService.instance;
      final group = await service.create(title: 'G', characterIds: []);
      expect(await service.nextTurnCharacterId(group.id), isNull);
    });
  });
}
