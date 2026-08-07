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
import 'character_intro_page.dart';
import 'character_intro_settings_page.dart';
import 'group_chat_create_page.dart';
import '../widgets/app_snack_bar.dart';

class CharListPage extends StatefulWidget {
  const CharListPage({super.key});

  @override
  State<CharListPage> createState() => _CharListPageState();
}

class _CharListPageState extends State<CharListPage> {
  late Future<List<CharacterSummary>> _charactersFuture;

  @override
  void initState() {
    super.initState();
    _charactersFuture = _loadCharacters();
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
        message += '，跳过同名 ${batch.skippedCharacterCount} 个';
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
        final single = await CharacterService.instance.importBatch(
          files: [(name: picked.name, bytes: bytes)],
        );
        await _refresh();
        if (!mounted) return;
        if (single.characterCount == 1) {
          AppTopNotice.show(context, '已导入角色：${picked.name}');
        } else if (single.skippedCharacterCount > 0) {
          AppTopNotice.show(context, '已存在同名角色，已跳过');
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
        message += '，跳过同名 ${batch.skippedCharacterCount} 个';
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

  Future<void> _onCreateChat(CharacterSummary summary) async {
    final record = await CharacterService.instance.loadById(summary.id);
    if (record == null) {
      return;
    }
    final userName = _selectedUserName();
    final opening = ChatDisplaySanitizer.extractOpeningMessages(
      ChatOpeningMessageBuilder.build(
        characterCardData: record.cardJson,
        characterName: summary.name,
        userName: userName,
      ),
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

  Widget _buildCharacterImage(String path, Color color) {
    Widget fallback() {
      return Container(
        color: color.withValues(alpha: 0.35),
        child: const Center(
          child: Icon(Icons.person, size: 120, color: Colors.white24),
        ),
      );
    }

    if (path.isEmpty) {
      return fallback();
    }

    final provider = _imageProviderForPath(path)!;

    return Image(
      image: provider,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.5),
      height: double.infinity,
      errorBuilder: (_, _, _) => fallback(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('角色管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'AI 通读角色介绍',
            onPressed: _onShowIntroForAny,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '角色介绍 AI 设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CharacterIntroSettingsPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: '新建群聊',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const GroupChatCreatePage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导入',
            onPressed: _onImport,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建',
            onPressed: _onCreate,
          ),
        ],
      ),
      body: FutureBuilder<List<CharacterSummary>>(
        future: _charactersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final characters = snapshot.data ?? const <CharacterSummary>[];
          if (characters.isEmpty) {
            return const Center(
              child: Text('还没有角色，先导入一张角色卡吧'),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                // 竖版 16:9（9:16）书架封面：宽:高 ≈ 0.62
                childAspectRatio: 0.62,
              ),
              itemCount: characters.length,
              itemBuilder: (context, index) {
                final character = characters[index];
                final color = _summaryColor(character);
                return _CharacterCard(
                  name: character.name,
                  description: character.description,
                  color: color,
                  image: _buildCharacterImage(character.thumbnailPath, color),
                  onEdit: () async {
                    await _openEditor(character.id);
                    await _refresh();
                  },
                  onExport: () => _onExport(character),
                  onDelete: () => _onDelete(character),
                  onShowIntro: () => _onShowIntroduction(character),
                  // 点击卡片 = 直接开始聊天
                  onTap: () => _onCreateChat(character),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.name,
    required this.description,
    required this.color,
    required this.image,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    required this.onShowIntro,
    required this.onTap,
  });

  final String name;
  final String description;
  final Color color;
  final Widget image;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onShowIntro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showActionsMenu(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 封面：角色色 + 头像铺满
              Container(color: color),
              Positioned.fill(child: image),
              // 底部渐变压暗保证名字可读
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 46,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),
              // 底部名字条
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 长按提示（轻量）
                    Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 长按菜单：开始聊天 / 导出 / AI 通读 / 删除。
  Future<void> _showActionsMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('编辑角色：$name'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI 通读介绍'),
              onTap: () => Navigator.of(context).pop('intro'),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导出'),
              onTap: () => Navigator.of(context).pop('export'),
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
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null) {
      return;
    }
    switch (action) {
      case 'edit':
        onEdit();
      case 'intro':
        onShowIntro();
      case 'export':
        onExport();
      case 'delete':
        onDelete();
    }
  }
}

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
