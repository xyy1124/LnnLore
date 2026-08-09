import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/character_service.dart';
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
  });
}
