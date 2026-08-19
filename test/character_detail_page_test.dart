import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pocket_inn/models/character_card.dart';
import 'package:pocket_inn/pages/character_detail_page.dart';
import 'package:pocket_inn/pages/char_list_page.dart';
import 'package:pocket_inn/pages/chat_page.dart';
import 'package:pocket_inn/services/character_service.dart';
import 'package:pocket_inn/services/chat_database_service.dart';
import 'package:pocket_inn/services/storage_service.dart';
import 'package:pocket_inn/services/world_book_service.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

Map<String, dynamic> _card({
  required String name,
  String description = '',
  String personality = '',
  String scenario = '',
  String systemPrompt = '',
  String postHistory = '',
  String creatorNotes = '',
}) {
  return {
    'spec': 'chara_card_v2',
    'spec_version': '2.0',
    'data': {
      'name': name,
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': '你好。',
      'mes_example': '',
      'creator_notes': creatorNotes,
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistory,
      'alternate_greetings': <String>[],
      'tags': <String>[],
      'character_book': {'entries': {}, 'extensions': {}},
      'extensions': {},
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pocket_inn_detail_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (methodCall) async {
          return tempDir.path;
        });
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.initialize();
    await CharacterService.instance.initialize();
    await WorldBookService.instance.initialize();
  });

  tearDownAll(() async {
    await ChatDatabaseService.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Windows 短暂文件锁；临时目录由系统清理
      }
    }
  });

  setUp(() async {
    await StorageService.instance.clearAllData();
    final dataDir = StorageService.instance.dataDir;
    for (final path in [
      'characters',
      'characters/data',
      'characters/images',
      'characters/thumbnails',
      'world_books',
    ]) {
      await Directory('$dataDir/$path').create(recursive: true);
    }
  });

  // createFromCard performs real file IO, so it must run inside runAsync.
  Future<CharacterCardRecord> _createCard(
    WidgetTester tester,
    Map<String, dynamic> cardJson,
  ) {
    return tester.runAsync(
      () => CharacterService.instance.createFromCard(cardJson: cardJson),
    ).then((record) => record!);
  }

  Future<void> _pumpDetail(
    WidgetTester tester,
    String characterId, {
    VoidCallback? onStartChat,
  }) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CharacterDetailPage(
            characterId: characterId,
            onStartChat: onStartChat ?? () {},
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
  }

  Future<void> _waitForText(WidgetTester tester, String text) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('等待文本超时: $text');
  }

  group('CharacterDetailPage', () {
    testWidgets('shows name, start chat, and authored setting sections',
        (tester) async {
      final record = await _createCard(
        tester,
        _card(
          name: '测试角色',
          description: '角色描述文本',
          personality: '性格文本',
          scenario: '场景文本',
          systemPrompt: '系统提示文本',
          creatorNotes: '作者备注文本',
        ),
      );

      var chatCalls = 0;
      await _pumpDetail(tester, record.id, onStartChat: () => chatCalls++);

      expect(find.text('测试角色'), findsWidgets);
      expect(find.text('角色描述文本'), findsOneWidget);
      expect(find.text('性格'), findsNothing);
      expect(find.text('场景'), findsNothing);
      expect(find.text('系统提示'), findsNothing);
      expect(find.text('作者备注'), findsNothing);
      expect(find.text('开始聊天'), findsOneWidget);

      await tester.tap(find.text('开始聊天'));
      expect(chatCalls, 1);
    });

    testWidgets('empty description leaves only identity and start chat',
        (tester) async {
      final record = await _createCard(tester, _card(name: '空白角色'));

      await _pumpDetail(tester, record.id);

      expect(find.text('空白角色'), findsWidgets);
      expect(find.text('角色描述'), findsNothing);
      expect(find.text('这张角色卡没有可阅读的设定文本。'), findsNothing);
      expect(find.text('开始聊天'), findsOneWidget);
    });

    testWidgets('record load failure shows retry', (tester) async {
      await _pumpDetail(tester, 'missing-id');

      expect(find.text('角色加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('character list navigation', () {
    testWidgets('card tap opens detail page instead of chat directly',
        (tester) async {
      await _createCard(tester, _card(name: '导航角色'));

      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(home: CharListPage()));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();

      expect(find.text('导航角色'), findsOneWidget);

      await tester.tap(find.text('导航角色'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _waitForText(tester, '开始聊天');

      expect(find.byType(CharacterDetailPage), findsOneWidget);
      expect(find.byType(ChatPage), findsNothing);
      expect(find.text('开始聊天'), findsOneWidget);
    });
  });
}
