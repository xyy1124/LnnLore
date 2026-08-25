import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/app_top_notice.dart';

import '../data/mock_user_settings.dart';
import '../data/preset_selection.dart';
import '../models/character_card.dart';
import '../services/archive_import_service.dart';
import '../services/chat_opening_message_builder.dart';
import '../services/character_service.dart';
import '../services/chat_display_sanitizer.dart';
import '../services/folder_import_service.dart';
import 'chat_page.dart';
import 'char_edit_page.dart';
import 'character_detail_page.dart';
import 'character_intro_page.dart';
import 'character_intro_settings_page.dart';
import 'character_thumbnail_crop_page.dart';
import 'group_chat_create_page.dart';
import '../theme/chat_reading_theme.dart';

class CharListPage extends StatefulWidget {
  const CharListPage({super.key});

  @override
  State<CharListPage> createState() => _CharListPageState();
}

enum CharacterLibrarySort { updatedAt, name }

enum _CharacterMoreAction { intro, introSettings, groupChat }

@visibleForTesting
List<CharacterSummary> filterAndSortCharacterSummaries(
  List<CharacterSummary> characters, {
  required String query,
  required CharacterLibrarySort sort,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final visible = characters.where((character) {
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return character.name.toLowerCase().contains(normalizedQuery) ||
        character.description.toLowerCase().contains(normalizedQuery);
  }).toList();
  switch (sort) {
    case CharacterLibrarySort.updatedAt:
      visible.sort((a, b) {
        final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    case CharacterLibrarySort.name:
      visible.sort((a, b) => a.name.compareTo(b.name));
  }
  return visible;
}

class _CharListPageState extends State<CharListPage> {
  late Future<List<CharacterSummary>> _charactersFuture;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  CharacterLibrarySort _sort = CharacterLibrarySort.updatedAt;

  @override
  void initState() {
    super.initState();
    _charactersFuture = _loadCharacters();
    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim();
      if (nextQuery != _query) {
        setState(() => _query = nextQuery);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<List<CharacterSummary>> _loadCharacters() {
    return CharacterService.instance.loadAllSummaries();
  }

  Future<void> _refresh() async {
    final future = _loadCharacters();
    setState(() {
      _charactersFuture = future;
    });
    await future;
  }

  Future<void> _onImport() async {
    // 特别版：导入方式选择（文件/压缩包 或 文件夹直接导入）
    final choice = await showModalBottomSheet<_ImportChoice>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('选择文件夹导入'),
                subtitle: const Text('自动读取文件夹中的角色卡与世界书'),
                onTap: () => Navigator.pop(context, _ImportChoice.folder),
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('选择文件/压缩包'),
                subtitle: const Text('多选 json/png/zip 文件'),
                onTap: () => Navigator.pop(context, _ImportChoice.files),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) {
      return;
    }
    if (choice == _ImportChoice.folder) {
      await _onImportFolder();
    } else {
      await _onImportFiles();
    }
  }

  /// v78：同名角色覆盖确认框——导入将覆盖同名角色的卡内容、头像与
  /// 内嵌世界书（聊天记录保留），用户确认后才继续。
  Future<bool?> _confirmOverwriteSameName(List<String> names) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检测到同名角色'),
        content: Text(
          '以下角色已存在，继续导入将覆盖其卡内容、头像与内嵌世界书'
          '（聊天记录保留）：\n\n${names.join('、')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    );
  }

  /// 文件夹直接导入（Android SAF）。
  Future<void> _onImportFolder() async {
    try {
      final folderResult = await FolderImportService.instance
          .pickFolderAndReadFiles();
      if (folderResult == null || !mounted) {
        return; // 用户取消
      }
      // 文件夹内可能含 zip：先解压再统一自动分辨导入
      final expanded = await ArchiveImportService.instance.expandArchives(
        folderResult.files,
      );
      // v78：同名角色覆盖确认（覆盖卡内容/头像/内嵌世界书，聊天记录保留）
      final conflicts = await CharacterService.instance
          .findSameNameConflicts(expanded);
      if (conflicts.isNotEmpty) {
        final proceed = await _confirmOverwriteSameName(conflicts);
        if (proceed != true || !mounted) {
          return; // 用户取消，不导入
        }
      }
      final batch = await CharacterService.instance.importBatch(
        files: expanded,
        // 文件夹通读只收角色卡：世界书走角色卡内嵌的 character_book
        // 自动创建关联（与单文件导入一致），独立 json 不再当世界书，
        // 避免备份/配置等无关 json 被误导入
        includeStandaloneWorldBooks: false,
      );
      await _refresh();
      if (!mounted) {
        return;
      }
      final parts = <String>[
        if (batch.characterCount > 0) '角色卡 ${batch.characterCount} 个',
        if (batch.worldBookCount > 0) '世界书 ${batch.worldBookCount} 个',
      ];
      var message = '导入完成：${parts.isEmpty ? '0 个' : parts.join('、')}';
      if (batch.skippedCharacterCount > 0) {
        // v78：同名行为是覆盖（保留聊天记录），文案与真实行为一致
        message += '，更新同名角色 ${batch.skippedCharacterCount} 个';
      }
      if (folderResult.truncated) {
        message += '，内容过多已截断';
      }
      if (batch.failures.isNotEmpty) {
        message += '，失败 ${batch.failures.length} 个';
        debugPrint('文件夹导入失败项：${batch.failures.join('；')}');
      }
      AppTopNotice.show(context, message);
    } catch (e) {
      if (!mounted) {
        return;
      }
      final message = e.toString().contains('MissingPluginException')
          ? '当前平台不支持文件夹导入，请使用"选择文件/压缩包"（zip）'
          : '文件夹导入失败：$e';
      AppTopNotice.show(context, message);
    }
  }

  /// 多选文件/压缩包导入。
  Future<void> _onImportFiles() async {
    try {
      // 特别版：支持多选与 zip 压缩包（自动分辨角色卡/世界书）
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'png', 'zip'],
        allowMultiple: true,
        dialogTitle: '导入角色卡 / 世界书 / 压缩包',
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      // 单文件：保留原有冲突选择流程
      if (result.files.length == 1 &&
          !result.files.first.name.toLowerCase().endsWith('.zip')) {
        final picked = result.files.first;
        final bytes = picked.bytes ??
            (picked.path != null
                ? await File(picked.path!).readAsBytes()
                : null);
        if (bytes == null) return;
        // v78：同名角色覆盖确认（覆盖卡内容/头像/内嵌世界书，聊天记录保留）
        final conflicts = await CharacterService.instance
            .findSameNameConflicts([(name: picked.name, bytes: bytes)]);
        if (conflicts.isNotEmpty) {
          final proceed = await _confirmOverwriteSameName(conflicts);
          if (proceed != true || !mounted) {
            return; // 用户取消，不导入
          }
        }
        final single = await CharacterService.instance.importBatch(
          files: [(name: picked.name, bytes: bytes)],
        );
        await _refresh();
        if (!mounted) return;
        if (single.characterCount == 1) {
          AppTopNotice.show(context, '已导入角色：${picked.name}');
        } else if (single.skippedCharacterCount > 0) {
          AppTopNotice.show(context, '已更新同名角色：${picked.name}');
        } else if (single.worldBookCount == 1) {
          AppTopNotice.show(context, '已导入世界书：${picked.name}');
        } else if (single.failures.isNotEmpty) {
          AppTopNotice.show(context, '导入失败：${single.failures.first}',
              type: AppNoticeType.error,);
        } else {
          AppTopNotice.show(context, '未识别到角色卡，已跳过');
        }
        return;
      }

      // 批量/压缩包：解压后自动分辨导入
      final pickedEntries = <ImportFileEntry>[];
      for (final picked in result.files) {
        final bytes = picked.bytes ??
            (picked.path != null
                ? await File(picked.path!).readAsBytes()
                : null);
        if (bytes != null) {
          pickedEntries.add((name: picked.name, bytes: bytes));
        }
      }
      final expanded = await ArchiveImportService.instance.expandArchives(
        pickedEntries,
      );
      // v78：同名角色覆盖确认（覆盖卡内容/头像/内嵌世界书，聊天记录保留）
      final conflicts = await CharacterService.instance
          .findSameNameConflicts(expanded);
      if (conflicts.isNotEmpty) {
        final proceed = await _confirmOverwriteSameName(conflicts);
        if (proceed != true || !mounted) {
          return; // 用户取消，不导入
        }
      }
      final batch = await CharacterService.instance.importBatch(
        files: expanded,
        // 与文件夹导入一致：只收角色卡，世界书走角色卡内嵌的
        // character_book 自动创建关联（json/png 均如此）
        includeStandaloneWorldBooks: false,
      );
      await _refresh();
      if (!mounted) return;

      final parts = <String>[
        if (batch.characterCount > 0) '角色卡 ${batch.characterCount} 个',
        if (batch.worldBookCount > 0) '世界书 ${batch.worldBookCount} 个',
      ];
      var message = '导入完成：${parts.isEmpty ? '0 个' : parts.join('、')}';
      if (batch.skippedCharacterCount > 0) {
        // v78：同名行为是覆盖（保留聊天记录），文案与真实行为一致
        message += '，更新同名角色 ${batch.skippedCharacterCount} 个';
      }
      if (batch.failures.isNotEmpty) {
        message += '，失败 ${batch.failures.length} 个';
        debugPrint('批量导入失败项：${batch.failures.join('；')}');
      }
      AppTopNotice.show(context, message);
    } catch (e) {
      if (!mounted) return;
      AppTopNotice.show(context, '导入失败：$e', type: AppNoticeType.error);
    }
  }

  Future<void> _onCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RoleEditPage(
          characterData: CharacterService.instance.buildEmptyCard(),
          closeAfterSave: true,
          initialWorldBookId: null,
          onSave: (payload) async {
            await CharacterService.instance.createFromCard(
              cardJson: payload.cardJson,
              imageSourcePath: payload.imageSourcePath,
              selectedWorldBookId: payload.selectedWorldBookId,
            );
          },
        ),
      ),
    );

    if (created == true) {
      await _refresh();
    }
  }

  Future<void> _onAdjustThumbnail(CharacterSummary summary) async {
    final record = await CharacterService.instance.loadById(summary.id);
    if (record == null || !mounted) {
      return;
    }
    if (record.originalImagePath.isEmpty ||
        !await File(record.originalImagePath).exists()) {
      if (mounted) {
        AppTopNotice.show(context, '该角色没有可调整的原始封面');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final crop = await Navigator.of(context).push<ThumbnailCropValue>(
      MaterialPageRoute(
        builder: (_) => CharacterThumbnailCropPage(
          imagePath: record.originalImagePath,
          initialFocusX: record.thumbnailFocusX,
          initialFocusY: record.thumbnailFocusY,
          initialScale: record.thumbnailScale,
          characterName: record.name,
        ),
      ),
    );
    if (crop == null || !mounted) {
      return;
    }
    try {
      await CharacterService.instance.updateThumbnailCrop(
        id: summary.id,
        focusX: crop.focusX,
        focusY: crop.focusY,
        scale: crop.scale,
      );
      await _refresh();
      if (mounted) {
        AppTopNotice.show(context, '封面构图已更新');
      }
    } catch (error) {
      if (mounted) {
        AppTopNotice.show(context, '调整封面失败：$error', type: AppNoticeType.error);
      }
    }
  }

  Future<void> _onExport(CharacterSummary summary) async {
    final record = await CharacterService.instance.loadById(summary.id);
    if (record == null || !mounted) return;

    final format = await showModalBottomSheet<_ExportFormat>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.data_object_outlined),
                title: const Text('导出为 JSON'),
                onTap: () => Navigator.pop(context, _ExportFormat.json),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('导出为 PNG'),
                onTap: () => Navigator.pop(context, _ExportFormat.png),
              ),
            ],
          ),
        );
      },
    );

    if (format == null || !mounted) return;

    final outputPath = switch (format) {
      _ExportFormat.json => await CharacterService.instance.exportToJsonFile(
        record,
      ),
      _ExportFormat.png => await CharacterService.instance.exportToPngFile(
        record,
      ),
    };

    if (outputPath == null || !mounted) return;
    AppTopNotice.show(context, '导出成功：$outputPath');
  }

  Future<void> _onDelete(CharacterSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除角色'),
          content: Text('确定删除 ${summary.name} 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await CharacterService.instance.delete(summary.id);
    await _refresh();
    if (!mounted) return;
    AppTopNotice.show(context, '已删除角色：${summary.name}');
  }

  /// 打开角色 AI 通读介绍页（加载完整角色卡与配套世界书）。
  Future<void> _onShowIntroduction(CharacterSummary summary) async {
    try {
      final record = await CharacterService.instance.loadById(summary.id);
      if (record == null || !mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CharacterIntroPage(
            character: record,
            worldBookId: record.worldBookId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppTopNotice.show(context, '加载角色失败：$error',
          type: AppNoticeType.error,);
    }
  }

  Future<void> _openEditor(String characterId) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _CharacterEditorLoader(characterId: characterId),
      ),
    );
  }

  /// 顶部通读按钮：弹出角色选择后进入 AI 通读介绍页。
  Future<void> _onShowIntroForAny() async {
    List<CharacterSummary> characters;
    try {
      characters = await _charactersFuture;
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppTopNotice.show(context, '加载角色列表失败：$error',
          type: AppNoticeType.error,);
      return;
    }
    if (!mounted) {
      return;
    }
    if (characters.isEmpty) {
      AppTopNotice.show(context, '还没有角色，先导入一张角色卡吧');
      return;
    }
    final selected = await showModalBottomSheet<CharacterSummary>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: characters.length,
          itemBuilder: (context, index) {
            final character = characters[index];
            return ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: _summaryColor(character),
                backgroundImage: character.thumbnailPath.isNotEmpty
                    ? FileImage(File(character.thumbnailPath))
                    : null,
                child: character.thumbnailPath.isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(character.name),
              onTap: () => Navigator.of(context).pop(character),
            );
          },
        ),
      ),
    );
    if (selected != null && mounted) {
      await _onShowIntroduction(selected);
    }
  }

  /// v98：点击卡片进入只读角色详情页；开始聊天由详情页按钮调用共享
  /// 命令 [startChatFor]（即原 _onCreateChat），不在本页直接进聊天。
  Future<void> _openCharacterDetail(CharacterSummary summary) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CharacterDetailPage(
          characterId: summary.id,
          initialSummary: summary,
          onStartChat: () => _onCreateChat(summary),
        ),
      ),
    );
  }

  Future<void> _onCreateChat(CharacterSummary summary) async {
    final record = await CharacterService.instance.loadById(summary.id);
    if (record == null) {
      return;
    }
    final userName = _selectedUserName();
    final built = ChatOpeningMessageBuilder.buildWithOpeningName(
      characterCardData: record.cardJson,
      characterName: summary.name,
      userName: userName,
    );
    final opening = ChatDisplaySanitizer.extractOpeningMessages(
      built.messages,
      // v71：传卡 JSON 剥离开场消息末尾的纯文本状态栏
      // （first_mes 自带"场景：…\n好感：30/100"时正文不再残留）
      cardJson: record.cardJson,
    );
    final openingMessages = opening.messages;
    final openingStatusHtml = opening.specialStatusHtml;
    final worldBookIds = record.worldBookId != null
        ? [record.worldBookId!]
        : const <String>[];
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute(
        builder: (context) => ChatPage.draft(
          characterId: summary.id,
          title: summary.name,
          selectedUserSettingId: selectedUserSettingIdNotifier.value,
          selectedPresetId: selectedPresetIdNotifier.value,
          selectedWorldBookIds: worldBookIds,
          openingAssistantMessages: openingMessages,
          openingStatusHtml: openingStatusHtml,
          openingName: built.openingName,
        ),
      ),
      (_) => false,
    );
  }

  String _selectedUserName() {
    final settings = userSettingsNotifier.value;
    if (settings.isEmpty) {
      return '默认用户';
    }
    final targetId = selectedUserSettingIdNotifier.value;
    if (targetId != null) {
      for (final item in settings) {
        if (item.id == targetId) {
          return item.name;
        }
      }
    }
    return settings.first.name;
  }

  Color _fallbackSummaryColor(CharacterSummary summary) {
    const palette = [
      Color(0xFF2E7D32),
      Color(0xFF1565C0),
      Color(0xFF7B1FA2),
      Color(0xFFB56576),
      Color(0xFF264653),
      Color(0xFFE76F51),
    ];
    return palette[summary.id.hashCode.abs() % palette.length];
  }

  Color _summaryColor(CharacterSummary summary) {
    final colorValue = summary.cardColorValue;
    if (colorValue != null) {
      return Color(colorValue);
    }
    return _fallbackSummaryColor(summary);
  }

  ImageProvider? _imageProviderForPath(String path) {
    if (path.isEmpty) {
      return null;
    }
    return path.startsWith('assets/')
        ? AssetImage(path) as ImageProvider
        : FileImage(File(path));
  }

  List<CharacterSummary> _visibleCharacters(
    List<CharacterSummary> characters,
  ) => filterAndSortCharacterSummaries(
    characters,
    query: _query,
    sort: _sort,
  );

  String _relativeUpdatedAt(DateTime? value) {
    if (value == null) return '未记录';
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return '刚刚更新';
    if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
    if (difference.inDays < 1) return '${difference.inHours} 小时前';
    if (difference.inDays < 7) return '${difference.inDays} 天前';
    return '${value.month}/${value.day}';
  }

  Future<void> _showMoreActions(_CharacterMoreAction action) async {
    switch (action) {
      case _CharacterMoreAction.intro:
        await _onShowIntroForAny();
      case _CharacterMoreAction.introSettings:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CharacterIntroSettingsPage(),
          ),
        );
      case _CharacterMoreAction.groupChat:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GroupChatCreatePage()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readingTheme = context.chatReadingTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
          tooltip: '返回',
        ),
        title: const Text('角色'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索角色',
            onPressed: () => _searchFocusNode.requestFocus(),
          ),
          PopupMenuButton<_CharacterMoreAction>(
            tooltip: '更多角色工具',
            onSelected: _showMoreActions,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _CharacterMoreAction.intro,
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('AI 通读角色介绍'),
                ),
              ),
              PopupMenuItem(
                value: _CharacterMoreAction.introSettings,
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('角色介绍 AI 设置'),
                ),
              ),
              PopupMenuItem(
                value: _CharacterMoreAction.groupChat,
                child: ListTile(
                  leading: Icon(Icons.group_outlined),
                  title: Text('新建群聊'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<CharacterSummary>>(
        future: _charactersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CharacterLibraryState(
              icon: Icons.error_outline_rounded,
              title: '角色库加载失败',
              detail: '${snapshot.error}',
              primaryLabel: '重试',
              onPrimary: _refresh,
            );
          }

          final characters = snapshot.data ?? const <CharacterSummary>[];
          final visible = _visibleCharacters(characters);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: '搜索角色名称或简介',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    tooltip: '清除搜索',
                                    onPressed: _searchController.clear,
                                  ),
                            filled: true,
                            fillColor: readingTheme.composerSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: readingTheme.composerBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: readingTheme.composerBorder,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _onImport,
                                icon: const Icon(Icons.file_download_outlined),
                                label: const Text('导入角色卡'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _onCreate,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('新建'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              characters.isEmpty
                                  ? '角色库'
                                  : '共 ${characters.length} 张角色卡',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const Spacer(),
                            PopupMenuButton<CharacterLibrarySort>(
                              tooltip: '排序方式',
                              onSelected: (sort) => setState(() => _sort = sort),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: readingTheme.choiceSurface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: readingTheme.statusBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sort_rounded,
                                      size: 16,
                                      color: readingTheme.choiceForeground,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _sort == CharacterLibrarySort.updatedAt
                                          ? '最近更新'
                                          : '名称',
                                      style: TextStyle(
                                        color: readingTheme.choiceForeground,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: CharacterLibrarySort.updatedAt,
                                  child: Text('最近更新'),
                                ),
                                PopupMenuItem(
                                  value: CharacterLibrarySort.name,
                                  child: Text('按名称'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (characters.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CharacterLibraryState(
                      icon: Icons.person_add_alt_1_outlined,
                      title: '还没有角色',
                      detail: '导入角色卡，或从空白角色开始创建。',
                      primaryLabel: '导入角色卡',
                      onPrimary: _onImport,
                      secondaryLabel: '新建角色',
                      onSecondary: _onCreate,
                    ),
                  )
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CharacterLibraryState(
                      icon: Icons.search_off_rounded,
                      title: '没有找到角色',
                      detail: '尝试其他名称或简介关键词。',
                      primaryLabel: '清除搜索',
                      onPrimary: _searchController.clear,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final columns = (constraints.crossAxisExtent / 210)
                            .floor()
                            .clamp(2, 5);
                        return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.78,
                              ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final character = visible[index];
                            return _CharacterLibraryCard(
                              summary: character,
                              color: _summaryColor(character),
                              relativeUpdatedAt: _relativeUpdatedAt(
                                character.updatedAt,
                              ),
                              imageProvider: _imageProviderForPath(
                                character.thumbnailPath,
                              ),
                              onTap: () => _openCharacterDetail(character),
                              onEdit: () async {
                                await _openEditor(character.id);
                                await _refresh();
                              },
                              onAdjustThumbnail: () =>
                                  _onAdjustThumbnail(character),
                              onExport: () => _onExport(character),
                              onDelete: () => _onDelete(character),
                              onShowIntro: () => _onShowIntroduction(character),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CharacterLibraryState extends StatelessWidget {
  const _CharacterLibraryState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 44,
                color: context.chatReadingTheme.composerAccent,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
                  if (secondaryLabel != null && onSecondary != null)
                    OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterLibraryCard extends StatelessWidget {
  const _CharacterLibraryCard({
    required this.summary,
    required this.color,
    required this.relativeUpdatedAt,
    required this.imageProvider,
    required this.onTap,
    required this.onEdit,
    required this.onAdjustThumbnail,
    required this.onExport,
    required this.onDelete,
    required this.onShowIntro,
  });

  final CharacterSummary summary;
  final Color color;
  final String relativeUpdatedAt;
  final ImageProvider? imageProvider;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onAdjustThumbnail;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onShowIntro;

  @override
  Widget build(BuildContext context) {
    final readingTheme = context.chatReadingTheme;
    final description = summary.description.trim();
    return Semantics(
      button: true,
      label: '${summary.name}，$relativeUpdatedAt 更新',
      child: Material(
        color: readingTheme.sidebarSurface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _showActionsMenu(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: readingTheme.statusBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(7),
                      topRight: Radius.circular(7),
                    ),
                    child: imageProvider == null
                        ? ColoredBox(
                            color: color.withValues(alpha: 0.22),
                            child: Icon(
                              Icons.person_outline_rounded,
                              size: 42,
                              color: color,
                            ),
                          )
                        : Image(
                            image: imageProvider!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: color.withValues(alpha: 0.22),
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 36,
                                color: color,
                              ),
                            ),
                          ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: readingTheme.sidebarPrimaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Expanded(
                          child: Text(
                            description.isEmpty ? '暂无角色简介' : description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: readingTheme.sidebarSecondaryText,
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                        Text(
                          relativeUpdatedAt,
                          style: TextStyle(
                            color: readingTheme.sidebarTimestamp,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActionsMenu(BuildContext context) async {
    final action = await showModalBottomSheet<_CharacterCardAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('开始聊天'),
              onTap: () => Navigator.of(context).pop(_CharacterCardAction.chat),
            ),
            ListTile(
              leading: const Icon(Icons.crop_free_rounded),
              title: const Text('调整封面构图'),
              onTap: () => Navigator.of(context).pop(_CharacterCardAction.crop),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑角色'),
              onTap: () => Navigator.of(context).pop(_CharacterCardAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI 通读介绍'),
              onTap: () => Navigator.of(context).pop(_CharacterCardAction.intro),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导出'),
              onTap: () => Navigator.of(context).pop(_CharacterCardAction.export),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(_CharacterCardAction.delete),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case _CharacterCardAction.chat:
        onTap();
      case _CharacterCardAction.crop:
        onAdjustThumbnail();
      case _CharacterCardAction.edit:
        onEdit();
      case _CharacterCardAction.intro:
        onShowIntro();
      case _CharacterCardAction.export:
        onExport();
      case _CharacterCardAction.delete:
        onDelete();
      case null:
        return;
    }
  }
}

enum _CharacterCardAction { chat, crop, edit, intro, export, delete }

enum _ExportFormat { json, png }

class _CharacterEditorLoader extends StatelessWidget {
  const _CharacterEditorLoader({required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CharacterCardRecord?>(
      future: CharacterService.instance.loadById(characterId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final record = snapshot.data;
        if (record == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('角色不存在或加载失败')),
          );
        }

        return RoleEditPage(
          characterData: record.cardJson,
          imagePath: record.originalImagePath,
          initialWorldBookId: record.worldBookId,
          onSave: (payload) => CharacterService.instance.updateCard(
            id: record.id,
            cardJson: payload.cardJson,
            imageSourcePath: payload.imageSourcePath,
            removeImage: payload.removeImage,
            selectedWorldBookId: payload.selectedWorldBookId,
          ),
        );
      },
    );
  }
}

/// 导入方式选择。
enum _ImportChoice { folder, files }
