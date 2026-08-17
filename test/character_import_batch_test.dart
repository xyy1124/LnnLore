import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pocket_inn/services/character_service.dart';
import 'package:pocket_inn/services/chat_database_service.dart';
import 'package:pocket_inn/services/storage_service.dart';
import 'package:pocket_inn/services/world_book_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert' as convert;

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

const String _charCardJson = '''
{
  "spec": "chara_card_v2",
  "spec_version": "2.0",
  "data": {
    "name": "测试角色",
    "description": "测试描述",
    "personality": "测试性格",
    "scenario": "测试场景",
    "first_mes": "你好",
    "mes_example": ""
  }
}
''';

const String _worldBookJson = '''
{
  "name": "测试世界书",
  "entries": {
    "0": {
      "keys": ["测试关键词"],
      "content": "测试条目内容",
      "enabled": true,
      "comment": ""
    }
  }
}
''';

/// 1x1 透明 PNG（真实有效的 png 字节，用于头像配对测试）。
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

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
    await CharacterService.instance.initialize();
    await WorldBookService.instance.initialize();
  });

  tearDownAll(() async {
    // v80：删除角色会初始化 ChatDatabaseService，先关 DB 释放文件锁，
    // 否则 tearDownAll 删 tempDir 时 Windows 报 errno 32
    await ChatDatabaseService.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await StorageService.instance.clearAllData();
    // clearAllData 删除了数据目录，而 CharacterService 幂等初始化会跳过
    // 重建，这里手动重建所需的子目录
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

  Uint8List _bytes(String text) =>
      Uint8List.fromList(utf8.encode(text));

  group('CharacterService.importBatch', () {
    test('角色卡 json 导入成功', () async {
      final result = await CharacterService.instance.importBatch(
        files: [
          (name: '角色A.json', bytes: _bytes(_charCardJson)),
        ],
      );
      expect(result.characterCount, 1);
      expect(result.worldBookCount, 0);
      expect(result.failures, isEmpty);
    });

    test('世界书 json 自动分辨导入', () async {
      final result = await CharacterService.instance.importBatch(
        files: [
          (name: '世界书A.json', bytes: _bytes(_worldBookJson)),
        ],
      );
      expect(result.worldBookCount, 1);
      expect(result.characterCount, 0);
    });

    test('文件夹模式（includeStandaloneWorldBooks=false）忽略独立世界书 json', () async {
      // 独立世界书 json 在文件夹通读时不应导入（避免无关 json 误导入）
      final result = await CharacterService.instance.importBatch(
        files: [
          (name: '世界书A.json', bytes: _bytes(_worldBookJson)),
        ],
        includeStandaloneWorldBooks: false,
      );
      expect(result.worldBookCount, 0);
      expect(result.characterCount, 0);
      expect(result.failures, isEmpty);
    });

    test('世界书 entries 数组形式（兼容）自动分辨导入', () async {
      const arrayFormJson = '''
{
  "name": "数组世界书",
  "entries": [
    {
      "keys": ["关键词"],
      "content": "数组条目",
      "enabled": true,
      "comment": ""
    }
  ]
}
''';
      final result = await CharacterService.instance.importBatch(
        files: [
          (name: '数组世界书.json', bytes: _bytes(arrayFormJson)),
        ],
      );
      expect(result.worldBookCount, 1);
      expect(result.characterCount, 0);
    });

    test('同名角色跳过', () async {
      await CharacterService.instance.importBatch(
        files: [
          (name: '角色A.json', bytes: _bytes(_charCardJson)),
        ],
      );
      final result = await CharacterService.instance.importBatch(
        files: [
          (name: '角色A.json', bytes: _bytes(_charCardJson)),
        ],
      );
      // 同名改为覆盖：第二次导入更新而非跳过
      expect(result.characterCount, 1);
      expect(result.skippedCharacterCount, 0);
    });

    test('json 角色卡与同名 png 配对不报错', () async {
      final result = await CharacterService.instance.importBatch(
        files: [
          (name: '角色A.json', bytes: _bytes(_charCardJson)),
          // 普通 png（非角色卡）作为头像候选
          (
            name: '角色A.png',
            bytes: Uint8List.fromList(convert.base64Decode(_tinyPngBase64)),
          ),
        ],
      );
      expect(result.characterCount, 1);
      expect(result.failures, isEmpty);
    });

    test('无法识别的 json 记为失败', () async {
      final result = await CharacterService.instance.importBatch(
        files: [
          (name: '未知.json', bytes: _bytes('{"foo": "bar"}')),
        ],
      );
      expect(result.characterCount, 0);
      expect(result.worldBookCount, 0);
      expect(result.failures, isNotEmpty);
    });
  });

  group('v78 character_book 非数字 key 兼容', () {
    test('entries 用 UUID 字符串 key 不崩溃且正常导入', () async {
      final card = jsonDecode(_charCardJson) as Map<String, dynamic>;
      final data = card['data'] as Map<String, dynamic>;
      data['character_book'] = {
        'name': '测试书',
        'entries': {
          'entry_abc': {
            'keys': ['关键词1'],
            'content': '条目内容1',
            'enabled': true,
          },
          'entry_def': {
            'keys': ['关键词2'],
            'content': '条目内容2',
            'enabled': true,
          },
        },
      };
      final result = await CharacterService.instance.importBatch(
        files: [(name: 'UUID书.json', bytes: _bytes(jsonEncode(card)))],
      );
      expect(result.characterCount, 1);
      expect(result.failures, isEmpty);
      // 内嵌世界书自动创建（2 条非数字 key 条目全部保留）
      final summaries = await CharacterService.instance.loadAllSummaries();
      final record = await CharacterService.instance.loadById(summaries.single.id);
      expect(record, isNotNull);
      final worldBooks = await WorldBookService.instance.loadAll();
      expect(
        worldBooks.where((b) => b.entries.length == 2),
        isNotEmpty,
      );
    });
  });

  group('v78 findSameNameConflicts 同名预检', () {
    test('已存在同名角色时返回冲突名单', () async {
      await CharacterService.instance.importBatch(
        files: [(name: '角色A.json', bytes: _bytes(_charCardJson))],
      );
      final conflicts = await CharacterService.instance.findSameNameConflicts(
        [(name: '角色A副本.json', bytes: _bytes(_charCardJson))],
      );
      expect(conflicts, ['测试角色']);
    });

    test('无同名角色时返回空列表', () async {
      final otherCard = jsonDecode(_charCardJson) as Map<String, dynamic>;
      (otherCard['data'] as Map<String, dynamic>)['name'] = '另一个角色';
      final conflicts = await CharacterService.instance.findSameNameConflicts(
        [(name: '新卡.json', bytes: _bytes(jsonEncode(otherCard)))],
      );
      expect(conflicts, isEmpty);
    });

    test('v79 同批次两张同名新卡 → 冲突列表包含该名（防止静默覆盖）', () async {
      final conflicts = await CharacterService.instance.findSameNameConflicts([
        (name: 'A.json', bytes: _bytes(_charCardJson)),
        (name: 'B.json', bytes: _bytes(_charCardJson)),
      ]);
      // 预检时两者都未持久化，但批内同名必须计入冲突
      expect(conflicts, ['测试角色']);
    });
  });

  group('v97 本地封面构图', () {
    Uint8List portraitBytes(int leftColor, int rightColor) {
      final image = img.Image(width: 1600, height: 800);
      img.fill(image, color: img.ColorRgb8(rightColor, 0, 255 - rightColor));
      img.fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 799,
        y2: 799,
        color: img.ColorRgb8(leftColor, 0, 255 - leftColor),
      );
      return Uint8List.fromList(img.encodePng(image));
    }

    test('调整构图不修改原图，普通编辑保留构图，新图重置', () async {
      final initialImage = portraitBytes(255, 0);
      await CharacterService.instance.importBatch(
        files: [
          (name: '测试角色.json', bytes: _bytes(_charCardJson)),
          (name: '测试角色.png', bytes: initialImage),
        ],
      );
      final summary = (await CharacterService.instance.loadAllSummaries()).single;
      final initial = await CharacterService.instance.loadById(summary.id);
      expect(initial, isNotNull);
      final originalBefore = await File(initial!.originalImagePath).readAsBytes();

      await CharacterService.instance.updateThumbnailCrop(
        id: initial.id,
        focusX: 0.1,
        focusY: 0.5,
        scale: 1.6,
      );
      final cropped = await CharacterService.instance.loadById(initial.id);
      expect(cropped!.thumbnailFocusX, 0.1);
      expect(cropped.thumbnailFocusY, 0.5);
      expect(cropped.thumbnailScale, 1.6);
      expect(await File(cropped.originalImagePath).readAsBytes(), originalBefore);

      await CharacterService.instance.updateCard(
        id: cropped.id,
        cardJson: cropped.cardJson,
      );
      final afterTextEdit = await CharacterService.instance.loadById(cropped.id);
      expect(afterTextEdit!.thumbnailFocusX, 0.1);
      expect(afterTextEdit.thumbnailFocusY, 0.5);
      expect(afterTextEdit.thumbnailScale, 1.6);

      final replacementPath = '${tempDir.path}/replacement.png';
      await File(replacementPath).writeAsBytes(portraitBytes(0, 255));
      await CharacterService.instance.updateCard(
        id: cropped.id,
        cardJson: cropped.cardJson,
        imageSourcePath: replacementPath,
      );
      final afterImageEdit = await CharacterService.instance.loadById(cropped.id);
      expect(afterImageEdit!.thumbnailFocusX, 0.5);
      expect(afterImageEdit.thumbnailFocusY, 0.5);
      expect(afterImageEdit.thumbnailScale, 1.0);
    });
  });

  group('v79 独立世界书非数字 key 兼容', () {
    test('UUID/字符串 key 的独立世界书导入不崩溃', () async {
      final wb = {
        'name': '独立世界书',
        'entries': {
          'entry_abc': {
            'keys': ['关键词1'],
            'content': '条目内容1',
            'enabled': true,
          },
          'entry_def': {
            'keys': ['关键词2'],
            'content': '条目内容2',
            'enabled': true,
          },
        },
      };
      final result = await CharacterService.instance.importBatch(
        files: [(name: '独立.json', bytes: _bytes(jsonEncode(wb)))],
      );
      expect(result.worldBookCount, 1);
      expect(result.failures, isEmpty);
    });
  });

  group('v80 世界书引用检查', () {
    Map<String, dynamic> _cardWithBook() {
      final card = jsonDecode(_charCardJson) as Map<String, dynamic>;
      final data = card['data'] as Map<String, dynamic>;
      data['character_book'] = {
        'name': '测试书',
        'entries': {
          '0': {'keys': ['k'], 'content': '内容', 'enabled': true},
        },
      };
      return card;
    }

    test('被角色使用的世界书禁止直接删除', () async {
      await CharacterService.instance.importBatch(
        files: [(name: '带书.json', bytes: _bytes(jsonEncode(_cardWithBook())))],
      );
      final books = await WorldBookService.instance.loadAll();
      expect(books, hasLength(1));
      await expectLater(
        WorldBookService.instance.delete(books.single.id),
        throwsA(isA<FormatException>()),
      );
      // 世界书仍在
      final after = await WorldBookService.instance.loadAll();
      expect(after, hasLength(1));
    });

    test('删除引用角色后私有世界书随之删除', () async {
      await CharacterService.instance.importBatch(
        files: [(name: '带书.json', bytes: _bytes(jsonEncode(_cardWithBook())))],
      );
      final summaries = await CharacterService.instance.loadAllSummaries();
      await CharacterService.instance.delete(summaries.single.id);
      final books = await WorldBookService.instance.loadAll();
      expect(books, isEmpty);
    });
  });
}
