import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/character_card.dart';
import '../models/world_book.dart';
import 'archive_import_service.dart';
import 'chat_database_service.dart';
import 'png_character_card_codec.dart';
import 'storage_service.dart';
import 'world_book_service.dart';

class CharacterService {
  CharacterService._();

  static final CharacterService instance = CharacterService._();

  static const String _indexFilename = 'characters_index.json';
  static const String _charactersDir = 'characters';
  static const int _dataVersion = 1;

  late String _charactersPath;
  late String _dataPath;
  late String _imagesPath;
  late String _thumbnailsPath;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final dataDir = StorageService.instance.dataDir;
    _charactersPath = '$dataDir/$_charactersDir';
    _dataPath = '$_charactersPath/data';
    _imagesPath = '$_charactersPath/images';
    _thumbnailsPath = '$_charactersPath/thumbnails';

    for (final path in [
      _charactersPath,
      _dataPath,
      _imagesPath,
      _thumbnailsPath,
    ]) {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    _initialized = true;
  }

  void _checkInitialized() {
    if (!_initialized) {
      throw StateError('CharacterService 未初始化，请先调用 initialize()');
    }
  }

  String _relativizePath(String path) {
    if (path.isEmpty) return path;
    final dataDir = StorageService.instance.dataDir;
    if (path.startsWith('$dataDir/')) return path.substring(dataDir.length + 1);
    return path;
  }

  String _resolvePath(String path) {
    if (path.isEmpty) return path;
    final dataDir = StorageService.instance.dataDir;
    if (path.startsWith(dataDir)) return path;
    return '$dataDir/$path';
  }

  Future<List<CharacterSummary>> loadAllSummaries() async {
    _checkInitialized();

    final data = await StorageService.instance.readJsonMap(_indexFilename);
    if (data == null) {
      return [];
    }

    final version = data['version'] as int? ?? _dataVersion;
    if (version != _dataVersion) {
      return [];
    }

    final dataDir = StorageService.instance.dataDir;
    final items = data['characters'] as List<dynamic>? ?? const [];
    final summaries =
        items
            .map(
              (item) {
                final parsed = CharacterSummary.fromJson(
                  Map<String, dynamic>.from(item as Map),
                );
                if (parsed.thumbnailPath.isNotEmpty &&
                    !parsed.thumbnailPath.startsWith(dataDir)) {
                  return CharacterSummary(
                    id: parsed.id,
                    name: parsed.name,
                    thumbnailPath: '$dataDir/${parsed.thumbnailPath}',
                    description: parsed.description,
                    cardColorValue: parsed.cardColorValue,
                    updatedAt: parsed.updatedAt,
                  );
                }
                return parsed;
              },
            )
            .toList()
          ..sort((a, b) {
            final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

    var changed = false;
    final hydrated = <CharacterSummary>[];
    for (final summary in summaries) {
      if (summary.cardColorValue != null || summary.thumbnailPath.isEmpty) {
        hydrated.add(summary);
        continue;
      }
      final colorValue = await _deriveSummaryColorValue(summary.thumbnailPath);
      hydrated.add(
        CharacterSummary(
          id: summary.id,
          name: summary.name,
          thumbnailPath: summary.thumbnailPath,
          description: summary.description,
          cardColorValue: colorValue,
          updatedAt: summary.updatedAt,
        ),
      );
      changed = true;
    }

    if (changed) {
      await _saveSummaries(hydrated);
    }

    return hydrated;
  }

  Future<CharacterCardRecord?> loadById(String id) async {
    _checkInitialized();

    final file = File('$_dataPath/$id.json');
    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final parsed = CharacterCardRecord.fromJson(json);
      return parsed.copyWith(
        originalImagePath: _resolvePath(parsed.originalImagePath),
        thumbnailPath: _resolvePath(parsed.thumbnailPath),
      );
    } catch (_) {
      return null;
    }
  }

  Future<CharacterCardRecord> createEmpty() async {
    _checkInitialized();

    final id = _generateId();
    final emptyRecord = CharacterCardRecord(
      id: id,
      cardJson: normalizeToV2Card(const {
        'data': {
          'name': '新角色',
          'description': '',
          'personality': '',
          'scenario': '',
          'first_mes': '',
          'mes_example': '',
          'creator_notes': '',
          'system_prompt': '',
          'post_history_instructions': '',
          'alternate_greetings': <String>[],
          'tags': <String>[],
          'character_book': {'entries': {}, 'extensions': {}},
          'extensions': {},
        },
      }),
      originalImagePath: '',
      thumbnailPath: '',
      updatedAt: DateTime.now(),
    );

    await save(emptyRecord);
    return emptyRecord;
  }

  Map<String, dynamic> buildEmptyCard() {
    return normalizeToV2Card(const {
      'data': {
        'name': '',
        'description': '',
        'personality': '',
        'scenario': '',
        'first_mes': '',
        'mes_example': '',
        'creator_notes': '',
        'system_prompt': '',
        'post_history_instructions': '',
        'alternate_greetings': <String>[],
        'tags': <String>[],
        'character_book': {'entries': [], 'extensions': {}},
        'extensions': {},
      },
    });
  }

  Future<CharacterCardRecord> createFromCard({
    required Map<String, dynamic> cardJson,
    String? imageSourcePath,
    String? selectedWorldBookId,
  }) async {
    _checkInitialized();

    final id = _generateId();
    final prepared = await _prepareCardForStorage(
      cardJson,
      existingWorldBookId: selectedWorldBookId,
    );

    final imageData = await _prepareImageAssets(
      id: id,
      imageSourcePath: imageSourcePath,
      currentOriginalImagePath: '',
      currentThumbnailPath: '',
      currentCardColorValue: null,
    );

    final record = CharacterCardRecord(
      id: id,
      cardJson: prepared.cardJson,
      originalImagePath: imageData.originalImagePath,
      thumbnailPath: imageData.thumbnailPath,
      worldBookId: prepared.worldBookId,
      characterBookExtensions: prepared.characterBookExtensions,
      cardColorValue: imageData.cardColorValue,
      updatedAt: DateTime.now(),
    );

    await save(record);
    return record.copyWith(
      originalImagePath: _resolvePath(record.originalImagePath),
      thumbnailPath: _resolvePath(record.thumbnailPath),
    );
  }

  Future<void> clearAllData() async {
    _checkInitialized();

    await StorageService.instance.deleteJsonFile(_indexFilename);

    final dir = Directory(_charactersPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    for (final path in [
      _charactersPath,
      _dataPath,
      _imagesPath,
      _thumbnailsPath,
    ]) {
      await Directory(path).create(recursive: true);
    }
  }

  Future<void> save(CharacterCardRecord record) async {
    _checkInitialized();

    final normalizedCard = normalizeToV2Card(record.cardJson);
    final storedRecord = record.copyWith(
      cardJson: normalizedCard,
      updatedAt: DateTime.now(),
    );

    final toStore = storedRecord.copyWith(
      originalImagePath: _relativizePath(storedRecord.originalImagePath),
      thumbnailPath: _relativizePath(storedRecord.thumbnailPath),
    );

    final file = File('$_dataPath/${record.id}.json');
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert(toStore.toJson());
    await file.writeAsString(content);

    final summaries = await loadAllSummaries();
    final summary = toStore.toSummary();
    final index = summaries.indexWhere((item) => item.id == record.id);
    if (index >= 0) {
      summaries[index] = summary;
    } else {
      summaries.add(summary);
    }
    await _saveSummaries(summaries);
  }

  Future<void> delete(String id) async {
    _checkInitialized();

    final record = await loadById(id);
    await ChatDatabaseService.instance.initialize();
    await ChatDatabaseService.instance.deleteSessionsByCharacterId(id);

    if (record != null) {
      await _deleteIfExists(File('$_dataPath/$id.json'));
      if (record.originalImagePath.isNotEmpty) {
        await _deleteIfExists(File(record.originalImagePath));
      }
      if (record.thumbnailPath.isNotEmpty) {
        await _deleteIfExists(File(record.thumbnailPath));
      }
      if (record.worldBookId != null && record.worldBookId!.isNotEmpty) {
        // v80：共享世界书不误删——只有不再被其他角色引用时才删除
        // （此前无条件删 worldBookId 关联的世界书，多个角色共享时
        // 会误伤其他角色的世界书）
        final referencing = await WorldBookService.instance
            .findReferencingCharacters(
          record.worldBookId!,
          exceptCharacterId: id,
        );
        if (referencing.isEmpty) {
          await WorldBookService.instance.delete(record.worldBookId!);
        }
      }
    }

    final summaries = await loadAllSummaries();
    summaries.removeWhere((item) => item.id == id);
    await _saveSummaries(summaries);
  }

  /// 批量导入（特别版）：自动分辨角色卡（json/png）与世界书（ST json），
  /// json 角色卡与同 basename 的 png 自动配对为头像；同名角色自动跳过；
  /// 支持 zip 解压后的文件列表（解压由 [ArchiveImportService] 完成）。
  ///
  /// [includeStandaloneWorldBooks] 为 false 时（文件夹通读场景）只导入
  /// 角色卡文件，不再尝试把独立 json 当作世界书导入——避免把备份/配置
  /// v78：导入前预检——返回 [files] 中与现有角色**同名**的角色名列表
  /// （用于 UI 覆盖确认：同名导入实际会覆盖卡内容/头像/内嵌世界书，
  /// 聊天记录保留）。
  Future<List<String>> findSameNameConflicts(
    List<ImportFileEntry> files,
  ) async {
    final conflicts = <String>{};
    // v79：批内同名也计入冲突——同批次两张同名新卡时，预检阶段两者
    // 都未持久化（旧逻辑查不到已有角色），导入时第二张会静默覆盖
    // 第一张，绕过覆盖确认。
    final seenInBatch = <String>{};
    for (final entry in files) {
      final ext = ArchiveImportService.extensionOf(entry.name);
      Map<String, dynamic>? cardJson;
      if (ext == 'png') {
        if (!ArchiveImportService.hasSafePngDimensions(entry.bytes)) {
          continue;
        }
        final embedded = PngCharacterCardCodec.decodeCard(entry.bytes);
        if (embedded != null) {
          cardJson = tryNormalizeCharacterCardJson(embedded);
        }
      } else if (ext == 'json') {
        final json = ArchiveImportService.tryDecodeJson(
          utf8.decode(entry.bytes, allowMalformed: true),
        );
        if (json != null && looksLikeCharacterCardJson(json)) {
          cardJson = json;
        }
      }
      if (cardJson == null) {
        continue;
      }
      final name = _characterNameFromCard(cardJson);
      if (name.isEmpty) {
        continue;
      }
      final existing = await _findSameNameCharacter(name);
      if (existing != null || seenInBatch.contains(name)) {
        conflicts.add(name);
      }
      seenInBatch.add(name);
    }
    final sorted = conflicts.toList()..sort();
    return sorted;
  }

  /// 等无关 json 误导入；角色卡内嵌的 character_book 世界书不受影响，
  /// 仍由 [_prepareCardForStorage] 自动创建并关联（与单文件导入一致）。
  Future<BatchImportResult> importBatch({
    required List<ImportFileEntry> files,
    bool includeStandaloneWorldBooks = true,
  }) async {
    _checkInitialized();

    var characterCount = 0;
    var skippedCharacterCount = 0;
    var worldBookCount = 0;
    final failures = <String>[];

    // 第一遍：收集 png（角色卡 png 或普通头像），basename 大小写不敏感
    final avatarByBase = <String, Uint8List>{};
    for (final entry in files) {
      if (ArchiveImportService.extensionOf(entry.name) == 'png') {
        final base = ArchiveImportService.basenameWithoutExtension(
          entry.name,
        ).toLowerCase();
        avatarByBase.putIfAbsent(base, () => entry.bytes);
      }
    }

    for (final entry in files) {
      final ext = ArchiveImportService.extensionOf(entry.name);
      final base = ArchiveImportService.basenameWithoutExtension(entry.name);
      try {
        if (ext == 'png') {
          // 优先尝试角色卡 png（内嵌卡 JSON）；先做尺寸预算检查，
          // 防止恶意 png 在解码时耗尽内存
          if (!ArchiveImportService.hasSafePngDimensions(entry.bytes)) {
            continue;
          }
          final embedded = PngCharacterCardCodec.decodeCard(entry.bytes);
          if (embedded != null) {
            final cardJson = tryNormalizeCharacterCardJson(embedded);
            if (cardJson != null) {
              final imported = await _importCharacter(
                cardJson,
                imageBytes: entry.bytes,
              );
              if (imported) {
                characterCount++;
              } else {
                skippedCharacterCount++;
              }
            } else {
              failures.add('${entry.name}: 无法解析角色卡');
            }
          }
          // 普通 png：仅作为头像候选，不单独处理
          continue;
        }
        if (ext == 'json') {
          final text = utf8.decode(entry.bytes, allowMalformed: true);
          final json = ArchiveImportService.tryDecodeJson(text);
          if (json == null) {
            failures.add('${entry.name}: 不是有效的 JSON 文件');
            continue;
          }
          if (looksLikeCharacterCardJson(json)) {
            final avatar = avatarByBase[base.toLowerCase()];
            final imported = await _importCharacter(
              json,
              imageBytes: avatar,
            );
            if (imported) {
              characterCount++;
            } else {
              skippedCharacterCount++;
            }
            continue;
          }
          // 独立世界书 json：仅在 includeStandaloneWorldBooks 时尝试
          // （文件夹通读只收角色卡，避免无关 json 误导入）
          if (!includeStandaloneWorldBooks) {
            continue;
          }
          // 尝试按世界书解析（SillyTavern 结构；兼容 entries 数组形式）
          try {
            final normalizedJson = _normalizeWorldBookJson(json);
            final worldBook = WorldBook.fromSillyTavernJson(normalizedJson);
            if (worldBook.entries.isEmpty) {
              failures.add('${entry.name}: 世界书没有条目');
              continue;
            }
            await WorldBookService.instance.importFromJson(
              normalizedJson,
              name: base.isEmpty ? worldBook.name : base,
            );
            worldBookCount++;
          } on Object catch (error) {
            failures.add('${entry.name}: 无法识别（$error）');
          }
        }
      } on Object catch (error) {
        failures.add('${entry.name}: $error');
      }
    }

    return BatchImportResult(
      characterCount: characterCount,
      skippedCharacterCount: skippedCharacterCount,
      worldBookCount: worldBookCount,
      failures: failures,
    );
  }

  /// 单条角色导入：同名跳过；[imageBytes] 为头像（角色卡 png 或配对头像）。
  Future<bool> _importCharacter(
    Map<String, dynamic> cardJson, {
    Uint8List? imageBytes,
  }) async {
    final importedName = _characterNameFromCard(cardJson);
    if (importedName.isNotEmpty) {
      final existing = await _findSameNameCharacter(importedName);
      if (existing != null) {
        // 同名覆盖：保留原 id（会话关联不断），替换卡内容与世界书
        return _overwriteCharacter(
          existing.id,
          cardJson,
          imageBytes: imageBytes,
        );
      }
    }

    final prepared = await _prepareCardForStorage(
      cardJson,
      existingWorldBookId: null,
    );
    final id = _generateId();

    String originalImagePath = '';
    String thumbnailPath = '';
    if (imageBytes != null) {
      // 特别版：头像超预算不再丢弃——降采样到安全尺寸后保存，
      // 保证"不管多大都能加载成功"（解码前检查防 OOM）
      imageBytes = _ensureSafeImageBytes(imageBytes);
    }
    if (imageBytes != null) {
      originalImagePath = await _storeOriginalImage(id, imageBytes);
      thumbnailPath = await _storeThumbnail(id, imageBytes);
    }

    final record = CharacterCardRecord(
      id: id,
      cardJson: prepared.cardJson,
      originalImagePath: originalImagePath,
      thumbnailPath: thumbnailPath,
      worldBookId: prepared.worldBookId,
      characterBookExtensions: prepared.characterBookExtensions,
      cardColorValue: await _deriveSummaryColorValue(thumbnailPath),
      updatedAt: DateTime.now(),
    );
    await save(record);
    return true;
  }

  /// 同名覆盖：保留原 id（会话关联不断），替换卡内容、头像与世界书。
  /// 新卡内嵌世界书会覆盖写入原世界书 id；无内嵌时保留旧世界书关联。
  Future<bool> _overwriteCharacter(
    String existingId,
    Map<String, dynamic> cardJson, {
    Uint8List? imageBytes,
  }) async {
    final existing = await loadById(existingId);
    final prepared = await _prepareCardForStorage(
      cardJson,
      existingWorldBookId: existing?.worldBookId,
    );

    String originalImagePath = existing?.originalImagePath ?? '';
    String thumbnailPath = existing?.thumbnailPath ?? '';
    if (imageBytes != null) {
      // 特别版：超预算头像降采样后替换（不因图大丢失立绘）
      imageBytes = _ensureSafeImageBytes(imageBytes);
    }
    if (imageBytes != null) {
      // 新头像替换旧图（删除旧文件防残留）
      if (existing != null) {
        if (existing.originalImagePath.isNotEmpty) {
          await _deleteIfExists(File(existing.originalImagePath));
        }
        if (existing.thumbnailPath.isNotEmpty) {
          await _deleteIfExists(File(existing.thumbnailPath));
        }
      }
      originalImagePath = await _storeOriginalImage(existingId, imageBytes);
      thumbnailPath = await _storeThumbnail(existingId, imageBytes);
    }

    final record = CharacterCardRecord(
      id: existingId,
      cardJson: prepared.cardJson,
      originalImagePath: originalImagePath,
      thumbnailPath: thumbnailPath,
      worldBookId: prepared.worldBookId,
      characterBookExtensions: prepared.characterBookExtensions,
      cardColorValue: await _deriveSummaryColorValue(thumbnailPath),
      updatedAt: DateTime.now(),
    );
    await save(record);
    return true;
  }

  /// 世界书 JSON 规范化：SillyTavern 标准为 entries 映射（{"0": {...}}），
  /// 兼容部分工具导出的数组形式（[{...}]），统一为索引映射。
  static String _normalizeWorldBookJson(Map<String, dynamic> json) {
    final entries = json['entries'];
    if (entries is List) {
      final normalizedMap = <String, dynamic>{};
      for (var i = 0; i < entries.length; i++) {
        normalizedMap['$i'] = entries[i];
      }
      return jsonEncode({...json, 'entries': normalizedMap});
    }
    return jsonEncode(json);
  }

  Future<String?> exportToJsonFile(CharacterCardRecord record) async {
    _checkInitialized();

    final outputPath = await _pickExportPath('${record.name}.json', [
      'json',
    ], '导出角色卡 JSON');
    if (outputPath == null) {
      return null;
    }

    final characterBook = await _buildCharacterBookForExport(record);
    final content = record.exportJsonString(characterBook: characterBook);
    return _saveExportBytes(
      outputPath: outputPath,
      defaultName: '${record.name}.json',
      allowedExtensions: const ['json'],
      title: '导出角色卡 JSON',
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
  }

  Future<String?> exportToPngFile(CharacterCardRecord record) async {
    _checkInitialized();

    final outputPath = await _pickExportPath('${record.name}.png', [
      'png',
    ], '导出角色卡 PNG');
    if (outputPath == null) {
      return null;
    }

    final imageBytes = await _loadExportImage(record);
    final characterBook = await _buildCharacterBookForExport(record);
    final cardJson = record.exportJsonString(characterBook: characterBook);
    final pngBytes = PngCharacterCardCodec.embedCard(imageBytes, cardJson);
    return _saveExportBytes(
      outputPath: outputPath,
      defaultName: '${record.name}.png',
      allowedExtensions: const ['png'],
      title: '导出角色卡 PNG',
      bytes: pngBytes,
      type: FileType.image,
    );
  }

  Future<void> updateCard({
    required String id,
    required Map<String, dynamic> cardJson,
    String? imageSourcePath,
    bool removeImage = false,
    String? selectedWorldBookId,
  }) async {
    _checkInitialized();

    final existing = await loadById(id);
    if (existing == null) {
      throw StateError('角色不存在: $id');
    }

    final prepared = await _prepareCardForStorage(
      cardJson,
      existingWorldBookId: selectedWorldBookId,
    );
    final imageData = await _prepareImageAssets(
      id: id,
      imageSourcePath: imageSourcePath,
      removeImage: removeImage,
      currentOriginalImagePath: existing.originalImagePath,
      currentThumbnailPath: existing.thumbnailPath,
      currentCardColorValue: existing.cardColorValue,
    );

    await save(
      existing.copyWith(
        cardJson: prepared.cardJson,
        originalImagePath: imageData.originalImagePath,
        thumbnailPath: imageData.thumbnailPath,
        worldBookId: prepared.worldBookId,
        characterBookExtensions: prepared.characterBookExtensions,
        cardColorValue: imageData.clearCardColorValue
            ? null
            : (imageData.cardColorValue ?? existing.cardColorValue),
      ),
    );
  }

  Future<CharacterSummary?> _findSameNameCharacter(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return null;
    }

    final summaries = await loadAllSummaries();
    for (final summary in summaries) {
      if (summary.name.trim() == normalizedName) {
        return summary;
      }
    }
    return null;
  }

  String _characterNameFromCard(Map<String, dynamic> cardJson) {
    final normalized = normalizeToV2Card(cardJson);
    final data = normalized['data'];
    if (data is Map) {
      return (data['name'] as String? ?? '').trim();
    }
    return '';
  }

  Future<void> _saveSummaries(List<CharacterSummary> summaries) async {
    final dataDir = StorageService.instance.dataDir;
    final items = summaries.map((item) {
      final json = item.toJson();
      final path = json['thumbnailPath'] as String;
      if (path.isNotEmpty && path.startsWith(dataDir)) {
        json['thumbnailPath'] = path.substring(dataDir.length + 1);
      }
      return json;
    }).toList();
    final data = {
      'version': _dataVersion,
      'characters': items,
    };
    await StorageService.instance.writeJsonMap(_indexFilename, data);
  }

  Map<String, dynamic> _normalizeCharacterBook(Object? value) {
    final map = value is Map<String, dynamic>
        ? Map<String, dynamic>.from(value)
        : value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
    final entries = _normalizeCharacterBookEntries(map['entries']);
    final extensionsValue = map['extensions'];
    final extensions = extensionsValue is Map<String, dynamic>
        ? Map<String, dynamic>.from(extensionsValue)
        : extensionsValue is Map
        ? Map<String, dynamic>.from(extensionsValue)
        : <String, dynamic>{};

    return {'entries': entries, 'extensions': extensions, 'name': map['name']};
  }

  Future<Map<String, dynamic>> _buildCharacterBookForExport(
    CharacterCardRecord record,
  ) async {
    if (record.worldBookId != null) {
      final book = await WorldBookService.instance.loadById(
        record.worldBookId!,
      );
      if (book != null) {
        return {
          'name': book.name,
          'entries': book.entries
              .map((entry) => _exportCharacterBookEntry(entry))
              .toList(),
          'extensions': record.characterBookExtensions,
        };
      }
    }

    final sourceBook = _normalizeCharacterBook(
      record.cardData['character_book'],
    );
    return {
      'name': sourceBook['name'],
      'entries': (sourceBook['entries'] as Map<String, dynamic>).values
          .toList(),
      'extensions': record.characterBookExtensions,
    };
  }

  Future<_PreparedCharacterCard> _prepareCardForStorage(
    Map<String, dynamic> cardJson, {
    required String? existingWorldBookId,
  }) async {
    final normalized = normalizeToV2Card(cardJson);
    final data = Map<String, dynamic>.from(normalized['data'] as Map);
    final characterBook = _normalizeCharacterBook(data['character_book']);
    final entries = Map<String, dynamic>.from(characterBook['entries'] as Map);
    final extensions = Map<String, dynamic>.from(
      characterBook['extensions'] as Map? ?? const {},
    );

    String? worldBookId;
    if (entries.isNotEmpty) {
      final bookName =
          ((characterBook['name'] as String?)?.trim().isNotEmpty ?? false)
          ? characterBook['name'] as String
          : '${data['name'] ?? '角色'}-世界书';
      final worldBook = WorldBook(
        id: existingWorldBookId ?? WorldBookService.instance.generateId(),
        name: bookName,
        description: '从角色卡导入',
        colorValue: 0xFF4B6CB7,
        entries: _worldBookEntriesFromCharacterBook(characterBook),
        updatedAt: DateTime.now(),
      );
      await WorldBookService.instance.save(worldBook);
      worldBookId = worldBook.id;
    } else if (existingWorldBookId != null && existingWorldBookId.isNotEmpty) {
      worldBookId = existingWorldBookId;
    }

    final strippedData = Map<String, dynamic>.from(data)
      ..['character_book'] = {
        'entries': <String, dynamic>{},
        'extensions': extensions,
      };

    return _PreparedCharacterCard(
      cardJson: {
        'spec': normalized['spec'],
        'spec_version': normalized['spec_version'],
        'data': strippedData,
      },
      worldBookId: worldBookId,
      characterBookExtensions: extensions,
    );
  }

  List<WorldBookEntry> _worldBookEntriesFromCharacterBook(
    Map<String, dynamic> characterBook,
  ) {
    final entries = Map<String, dynamic>.from(characterBook['entries'] as Map);
    // v78：key 排序兼容非数字字符串（UUID/entry_x 等第三方工具导出）——
    // 此前强制 int.parse 会抛 FormatException 导致整卡导入失败。
    final sortedKeys = entries.keys.toList()
      ..sort((a, b) {
        final an = int.tryParse(a);
        final bn = int.tryParse(b);
        if (an != null && bn != null) {
          return an.compareTo(bn);
        }
        if (an != null) {
          return -1;
        }
        if (bn != null) {
          return 1;
        }
        return a.compareTo(b);
      });

    return [
      for (final key in sortedKeys)
        _worldBookEntryFromCharacterBookEntry(
          Map<String, dynamic>.from(entries[key] as Map),
          key,
        ),
    ];
  }

  WorldBookEntry _worldBookEntryFromCharacterBookEntry(
    Map<String, dynamic> entry,
    String fallbackId,
  ) {
    final extensions = entry['extensions'] is Map
        ? Map<String, dynamic>.from(entry['extensions'] as Map)
        : <String, dynamic>{};

    final positionValue = entry['position'];
    final position = positionValue is int
        ? positionValue
        : positionValue == 'after_char'
        ? 1
        : 0;

    return WorldBookEntry(
      id: 'entry-${entry['id'] ?? fallbackId}',
      key:
          (entry['key'] as List<dynamic>? ??
                  entry['keys'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      keysecondary:
          (entry['keysecondary'] as List<dynamic>? ??
                  entry['secondary_keys'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      content: entry['content'] as String? ?? '',
      comment: entry['comment'] as String? ?? '',
      constant: entry['constant'] as bool? ?? false,
      selective: entry['selective'] as bool? ?? false,
      selectiveLogic:
          entry['selectiveLogic'] as int? ??
          extensions['selectiveLogic'] as int? ??
          0,
      order: entry['order'] as int? ?? entry['insertion_order'] as int? ?? 100,
      position: position,
      depth: entry['depth'] as int? ?? extensions['depth'] as int? ?? 4,
      sticky: entry['sticky'] as int? ?? extensions['sticky'] as int? ?? 0,
      cooldown:
          entry['cooldown'] as int? ?? extensions['cooldown'] as int? ?? 0,
      delay: entry['delay'] as int? ?? extensions['delay'] as int? ?? 0,
      isEnabled:
          entry['enabled'] as bool? ?? !(entry['disable'] as bool? ?? false),
      extensions: {
        ...extensions,
        if (entry['use_regex'] != null) 'use_regex': entry['use_regex'],
      },
    );
  }

  Map<String, dynamic> _normalizeCharacterBookEntries(Object? entriesValue) {
    if (entriesValue is Map<String, dynamic>) {
      return Map<String, dynamic>.from(entriesValue);
    }
    if (entriesValue is Map) {
      return Map<String, dynamic>.from(entriesValue);
    }
    if (entriesValue is List) {
      final result = <String, dynamic>{};
      for (var i = 0; i < entriesValue.length; i++) {
        final item = entriesValue[i];
        if (item is Map) {
          result[i.toString()] = Map<String, dynamic>.from(item);
        }
      }
      return result;
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _exportCharacterBookEntry(WorldBookEntry entry) {
    final extensions = Map<String, dynamic>.from(entry.extensions);
    final position = entry.position == 1 ? 'after_char' : 'before_char';

    return {
      'keys': entry.key,
      'content': entry.content,
      'extensions': {
        ...extensions,
        'selectiveLogic': entry.selectiveLogic,
        'position': entry.position,
        'depth': entry.depth,
        'role': extensions['role'] ?? 0,
        'match_whole_words': extensions['match_whole_words'] ?? true,
        'probability': extensions['probability'] ?? 100,
        'useProbability': extensions['useProbability'] ?? true,
        'sticky': entry.sticky,
        'cooldown': entry.cooldown,
        'delay': entry.delay,
        'exclude_recursion': extensions['exclude_recursion'] ?? false,
        'prevent_recursion': extensions['prevent_recursion'] ?? false,
        'delay_until_recursion': extensions['delay_until_recursion'] ?? false,
        'group': extensions['group'] ?? '',
        'group_override': extensions['group_override'] ?? false,
        'group_weight': extensions['group_weight'] ?? 100,
        'use_group_scoring': extensions['use_group_scoring'] ?? false,
        'scan_depth': extensions['scan_depth'] ?? 2,
        'case_sensitive': extensions['case_sensitive'] ?? false,
        'automation_id': extensions['automation_id'] ?? '',
        'vectorized': extensions['vectorized'] ?? false,
      },
      'enabled': entry.isEnabled,
      'insertion_order': entry.order,
      'id': _parseExportEntryId(entry.id),
      'name': entry.comment,
      'comment': entry.comment,
      'selective': entry.selective,
      'secondary_keys': entry.keysecondary,
      'case_sensitive': extensions['case_sensitive'] ?? false,
      'constant': entry.constant,
      'position': position,
      'display_index': _parseExportEntryId(entry.id) + 1,
    };
  }

  int _parseExportEntryId(String rawId) {
    final digits = RegExp(r'(\d+)$').firstMatch(rawId)?.group(1);
    return int.tryParse(digits ?? '') ?? 0;
  }

  Future<String?> _pickExportPath(
    String defaultName,
    List<String> allowedExtensions,
    String title,
  ) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return FilePicker.platform.saveFile(
        dialogTitle: title,
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
    }

    return defaultName;
  }

  Future<String?> _saveExportBytes({
    required String outputPath,
    required String defaultName,
    required List<String> allowedExtensions,
    required String title,
    required Uint8List bytes,
    FileType type = FileType.custom,
  }) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await File(outputPath).writeAsBytes(bytes);
      return outputPath;
    }

    return FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: defaultName,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
  }

  /// 特别版：把头像字节降到安全尺寸（超预算时降采样 ≤2048 后重编码）。
  /// 返回 null 表示无法处理（解码失败/降采样后仍超限），调用方丢弃头像。
  Uint8List? _ensureSafeImageBytes(Uint8List imageBytes) {
    if (ArchiveImportService.hasSafePngDimensions(imageBytes)) {
      return imageBytes;
    }
    // 解码前绝对硬上限：超过严格预算（8192/33M 像素）的异常超大图
    // 直接放弃头像，绝不裸解码（防 OOM 崩溃）。
    if (!ArchiveImportService.hasSafePngDimensions(
      imageBytes,
      maxDimension: ArchiveImportService.maxPngDimension,
      maxPixels: ArchiveImportService.maxPngPixels,
    )) {
      return null;
    }
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        return null;
      }
      final resized = decoded.width > 2048 || decoded.height > 2048
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height
                  ? 2048
                  : (2048 * decoded.width / decoded.height).round().clamp(
                      1,
                      2048,
                    ).toInt(),
            )
          : decoded;
      final encoded = img.encodePng(resized, level: 6);
      if (!ArchiveImportService.hasSafePngDimensions(encoded)) {
        return null;
      }
      return encoded;
    } catch (_) {
      return null;
    }
  }

  Future<String> _storeOriginalImage(String id, Uint8List imageBytes) async {
    final relPath = '$_charactersDir/images/$id.png';
    final absPath = '$_imagesPath/$id.png';
    await File(absPath).writeAsBytes(imageBytes);
    await _evictCachedFileImage(absPath);
    return relPath;
  }

  Future<String> _storeThumbnail(String id, Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return '';
    }

    // 特别版：缩略图加大到 1024（书架式封面/聊天头像放大显示不糊）
    final resized = img.copyResizeCropSquare(decoded, size: 1024);
    final encoded = img.encodePng(resized, level: 6);
    final relPath = '$_charactersDir/thumbnails/$id.png';
    final absPath = '$_thumbnailsPath/$id.png';
    await File(absPath).writeAsBytes(encoded);
    await _evictCachedFileImage(absPath);
    return relPath;
  }

  Future<_PreparedImageAssets> _prepareImageAssets({
    required String id,
    required String? imageSourcePath,
    bool removeImage = false,
    required String currentOriginalImagePath,
    required String currentThumbnailPath,
    int? currentCardColorValue,
  }) async {
    if (removeImage) {
      if (currentOriginalImagePath.isNotEmpty) {
        await _deleteIfExists(File(currentOriginalImagePath));
      }
      if (currentThumbnailPath.isNotEmpty) {
        await _deleteIfExists(File(currentThumbnailPath));
      }
      return const _PreparedImageAssets(
        originalImagePath: '',
        thumbnailPath: '',
      );
    }

    if (imageSourcePath == null || imageSourcePath.trim().isEmpty) {
      return _PreparedImageAssets(
        originalImagePath: currentOriginalImagePath,
        thumbnailPath: currentThumbnailPath,
        cardColorValue: currentCardColorValue,
      );
    }

    final sourceFile = File(imageSourcePath);
    if (!await sourceFile.exists()) {
      return _PreparedImageAssets(
        originalImagePath: currentOriginalImagePath,
        thumbnailPath: currentThumbnailPath,
        cardColorValue: currentCardColorValue,
      );
    }

    final bytes = await sourceFile.readAsBytes();
    // 特别版：png 尺寸预算保护——导入路径保持严格预算；
    // 编辑页立绘（用户自选文件）放宽预算，超限大图降采样保存
    // 而非丢弃（修复"立绘设置后保存丢失"）。
    final safeForPortrait = ArchiveImportService.hasSafePngDimensions(
      bytes,
      maxDimension: ArchiveImportService.maxPngDimensionPortrait,
      maxPixels: ArchiveImportService.maxPngPixelsPortrait,
    );
    if (safeForPortrait) {
      final originalImagePath = await _storeOriginalImage(id, bytes);
      final thumbnailPath = await _storeThumbnail(id, bytes);

      return _PreparedImageAssets(
        originalImagePath: originalImagePath,
        thumbnailPath: thumbnailPath,
        cardColorValue: await _deriveSummaryColorValue(thumbnailPath),
      );
    }
    // 超放宽预算（异常超大图）：尝试降采样保存，失败则保留原图。
    // 解码前加严格硬上限（8192/33M 像素）——超过绝不裸解码（防 OOM）。
    if (!ArchiveImportService.hasSafePngDimensions(
      bytes,
      maxDimension: ArchiveImportService.maxPngDimension,
      maxPixels: ArchiveImportService.maxPngPixels,
    )) {
      return _PreparedImageAssets(
        originalImagePath: currentOriginalImagePath,
        thumbnailPath: currentThumbnailPath,
        cardColorValue: currentCardColorValue,
      );
    }
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final resized = decoded.width > 2048 || decoded.height > 2048
            ? img.copyResize(
                decoded,
                width: decoded.width >= decoded.height
                    ? 2048
                    : (2048 * decoded.width / decoded.height).round().clamp(
                        1,
                        2048,
                      ).toInt(),
              )
            : decoded;
        final resizedBytes = img.encodePng(resized, level: 6);
        if (ArchiveImportService.hasSafePngDimensions(resizedBytes)) {
          final originalImagePath = await _storeOriginalImage(
            id,
            resizedBytes,
          );
          final thumbnailPath = await _storeThumbnail(id, resizedBytes);
          return _PreparedImageAssets(
            originalImagePath: originalImagePath,
            thumbnailPath: thumbnailPath,
            cardColorValue: await _deriveSummaryColorValue(thumbnailPath),
          );
        }
      }
    } catch (_) {
      // 解码失败：保留原图
    }
    return _PreparedImageAssets(
      originalImagePath: currentOriginalImagePath,
      thumbnailPath: currentThumbnailPath,
      cardColorValue: currentCardColorValue,
    );
  }

  Future<Uint8List> _loadExportImage(CharacterCardRecord record) async {
    final exportImagePath = _resolvePath(record.originalImagePath);
    if (exportImagePath.isNotEmpty) {
      final file = File(exportImagePath);
      if (await file.exists()) {
        return file.readAsBytes();
      }
    }

    final fallback = img.Image(width: 512, height: 768);
    img.fill(fallback, color: img.ColorRgb8(24, 28, 36));
    return Uint8List.fromList(img.encodePng(fallback));
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await _evictCachedFileImage(file.path);
      await file.delete();
    }
  }

  Future<void> _evictCachedFileImage(String path) async {
    if (path.isEmpty) {
      return;
    }
    await FileImage(File(path)).evict();
  }

  Future<int?> _deriveSummaryColorValue(String imagePath) async {
    if (imagePath.isEmpty) {
      return null;
    }

    final absPath = _resolvePath(imagePath);
    final provider = absPath.startsWith('assets/')
        ? AssetImage(absPath) as ImageProvider
        : FileImage(File(absPath));

    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: provider,
        brightness: Brightness.light,
      );
      return _ensureReadableCardColor(scheme.primary).toARGB32();
    } catch (_) {
      return null;
    }
  }

  Color _ensureReadableCardColor(Color color) {
    if (color.computeLuminance() <= 0.35) {
      return color;
    }
    return Color.alphaBlend(const Color(0x47000000), color);
  }

  String _generateId() => 'char-${DateTime.now().millisecondsSinceEpoch}';
}

class CharacterImportException implements Exception {
  const CharacterImportException(this.message);

  final String message;

  @override
  String toString() => 'CharacterImportException: $message';
}

class CharacterImportResult {
  const CharacterImportResult({required this.record, this.merged = false});

  final CharacterCardRecord record;
  final bool merged;
}

/// 特别版：批量导入结果汇总。
class BatchImportResult {
  const BatchImportResult({
    required this.characterCount,
    required this.skippedCharacterCount,
    required this.worldBookCount,
    required this.failures,
  });

  /// 成功导入的角色卡数量。
  final int characterCount;

  /// 因同名而跳过的角色卡数量。
  final int skippedCharacterCount;

  /// 成功导入的世界书数量。
  final int worldBookCount;

  /// 失败项（文件名 + 原因）。
  final List<String> failures;

  bool get hasFailure => failures.isNotEmpty;
}

enum CharacterImportConflictChoice { createNew, merge, cancel }

class _PreparedCharacterCard {
  const _PreparedCharacterCard({
    required this.cardJson,
    required this.worldBookId,
    required this.characterBookExtensions,
  });

  final Map<String, dynamic> cardJson;
  final String? worldBookId;
  final Map<String, dynamic> characterBookExtensions;
}

class _PreparedImageAssets {
  const _PreparedImageAssets({
    required this.originalImagePath,
    required this.thumbnailPath,
    this.cardColorValue,
  });

  final String originalImagePath;
  final String thumbnailPath;
  final int? cardColorValue;

  bool get clearCardColorValue =>
      cardColorValue == null && thumbnailPath.isEmpty;
}
