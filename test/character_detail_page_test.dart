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
  List<String> greetings = const [],
  List<String> tags = const [],
  Map<String, dynamic>? characterBook,
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
      'alternate_greetings': greetings,
      'tags': tags,
      'character_book': characterBook ?? {'entries': {}, 'extensions': {}},
      'extensions': {},
    },
  };
}

Map<String, dynamic> _bookWithEntries() {
  return {
    'name': '测试世界书',
    'entries': {
      '0': {
        'key': ['启用条目'],
        'content': '启用条目内容',
        'enabled': true,
        'comment': '条目一',
        'order': 100,
      },
      '1': {
        'key': ['禁用条目'],
        'content': '禁用条目内容',
        'enabled': false,
        'comment': '条目二',
        'order': 50,
      },
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
        // Windows 短暂文件锁：temp 目录由系统清理，忽略
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

  // createFromCard performs real file IO, so it must run inside runAsync
  // (testWidgets bodies execute in FakeAsync).
  Future<CharacterCardRecord> _createCard(
    WidgetTester tester,
    Map<String, dynamic> cardJson,
  ) {
    return tester.runAsync(
      () => CharacterService.instance.createFromCard(cardJson: cardJson),
    ).then((record) => record!);
  }

  void _useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> _pumpDetail(
    WidgetTester tester,
    String characterId, {
    VoidCallback? onStartChat,
  }) async {
    _useTallViewport(tester);
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

  // Real file IO completes only while runAsync runs; poll until the target
  // text renders instead of assuming a fixed delay is enough.
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
    testWidgets('renders identity, setting sections, and start chat',
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
          tags: const ['仙侠', '反派'],
          greetings: const ['备用开场一', '备用开场二'],
        ),
      );

      var chatCalls = 0;
      await _pumpDetail(tester, record.id, onStartChat: () => chatCalls++);

      expect(find.text('测试角色'), findsWidgets);
      expect(find.text('角色描述'), findsOneWidget);
      expect(find.text('角色描述文本'), findsWidgets);
      expect(find.text('性格'), findsOneWidget);
      expect(find.text('场景'), findsOneWidget);
      expect(find.text('系统提示'), findsOneWidget);
      expect(find.text('作者备注'), findsOneWidget);
      expect(find.text('仙侠'), findsOneWidget);
      expect(find.text('开始聊天'), findsOneWidget);

      await tester.tap(find.text('开始聊天'));
      expect(chatCalls, 1);
    });

    testWidgets('hides empty sections and shows placeholder when all empty',
        (tester) async {
      final record = await _createCard(tester, _card(name: '空白角色'));

      await _pumpDetail(tester, record.id);

      expect(find.text('这张角色卡没有可阅读的设定文本。'), findsOneWidget);
      expect(find.text('角色描述'), findsNothing);
      expect(find.text('开始聊天'), findsOneWidget);
    });

    testWidgets('alternate greetings collapse with count', (tester) async {
      final record = await _createCard(
        tester,
        _card(name: '问候角色', greetings: const ['开场A', '开场B', '开场C']),
      );

      await _pumpDetail(tester, record.id);

      expect(find.text('备用开场白'), findsOneWidget);
      expect(find.text('3 条可用'), findsOneWidget);
      expect(find.textContaining('开场A'), findsNothing);
    });

    testWidgets('world book lists only enabled entries in stored order',
        (tester) async {
      final record = await _createCard(
        tester,
        _card(
          name: '世界书角色',
          description: '描述',
          characterBook: _bookWithEntries(),
        ),
      );

      await _pumpDetail(tester, record.id);

      expect(find.text('测试世界书'), findsOneWidget);
      await tester.tap(find.text('测试世界书'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('条目一'), findsOneWidget);
      expect(find.text('条目二'), findsNothing);
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

      _useTallViewport(tester);
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
