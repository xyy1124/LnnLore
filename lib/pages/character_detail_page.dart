import 'dart:io';

import 'package:flutter/material.dart';

import '../models/character_card.dart';
import '../models/world_book.dart';
import '../services/character_service.dart';
import '../services/world_book_service.dart';
import '../theme/chat_reading_theme.dart';

/// 只读角色详情页（v98）。
///
/// 点击角色库卡片进入：头部展示 4:3 封面 + 角色名，下方按语义顺序阅读
/// 角色卡原始设定（description/personality/scenario/system_prompt/
/// post_history_instructions/creator_notes），空字段全部隐藏；备用开场白
/// 与关联世界书作为可折叠的次级资料。开始聊天必须走调用方注入的
/// [onStartChat]（复用列表页的完整聊天创建流程），本页不复制聊天逻辑。
class CharacterDetailPage extends StatefulWidget {
  const CharacterDetailPage({
    super.key,
    required this.characterId,
    required this.onStartChat,
    this.initialSummary,
  });

  final String characterId;

  /// 聊天创建命令（由列表页注入，内部完成完整记录加载、开场构建与
  /// pushAndRemoveUntil 导航），本页只负责调用。
  final VoidCallback onStartChat;

  /// 可选快速头部数据；最终内容以异步加载的完整记录为准。
  final CharacterSummary? initialSummary;

  @override
  State<CharacterDetailPage> createState() => _CharacterDetailPageState();
}

class _CharacterDetailPageState extends State<CharacterDetailPage> {
  late Future<CharacterCardRecord?> _recordFuture;
  WorldBook? _worldBook;
  bool _worldBookLoading = false;
  bool _worldBookFailed = false;

  @override
  void initState() {
    super.initState();
    _recordFuture = CharacterService.instance.loadById(widget.characterId);
    _recordFuture.then((record) {
      final worldBookId = record?.worldBookId;
      if (worldBookId == null || worldBookId.isEmpty) {
        return;
      }
      _loadWorldBook(worldBookId);
    });
  }

  Future<void> _loadWorldBook(String worldBookId) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _worldBookLoading = true;
      _worldBookFailed = false;
    });
    try {
      final book = await WorldBookService.instance.loadById(worldBookId);
      if (!mounted) {
        return;
      }
      setState(() {
        _worldBook = book;
        _worldBookLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _worldBookFailed = true;
        _worldBookLoading = false;
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      _recordFuture = CharacterService.instance.loadById(widget.characterId);
    });
    await _recordFuture;
  }

  @override
  Widget build(BuildContext context) {
    final readingTheme = context.chatReadingTheme;
    final initialName = widget.initialSummary?.name ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(initialName.isEmpty ? '角色详情' : initialName),
      ),
      body: FutureBuilder<CharacterCardRecord?>(
        future: _recordFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final record = snapshot.data;
          if (record == null) {
            return _DetailLoadError(onRetry: _retry);
          }
          return _DetailContent(
            record: record,
            worldBook: _worldBook,
            worldBookLoading: _worldBookLoading,
            worldBookFailed: _worldBookFailed,
            onStartChat: widget.onStartChat,
            readingTheme: readingTheme,
          );
        },
      ),
    );
  }
}

class _DetailLoadError extends StatelessWidget {
  const _DetailLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: context.chatReadingTheme.composerAccent,
            ),
            const SizedBox(height: 14),
            Text(
              '角色加载失败',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('角色可能已被删除，或本地数据暂时不可用。'),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.record,
    required this.worldBook,
    required this.worldBookLoading,
    required this.worldBookFailed,
    required this.onStartChat,
    required this.readingTheme,
  });

  final CharacterCardRecord record;
  final WorldBook? worldBook;
  final bool worldBookLoading;
  final bool worldBookFailed;
  final VoidCallback onStartChat;
  final ChatReadingTheme readingTheme;

  String _field(Map<String, dynamic> data, String key) =>
      (data[key] as String? ?? '').trim();

  List<String> _stringList(Map<String, dynamic> data, String key) =>
      (data[key] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

  String _relativeUpdatedAt(DateTime? value) {
    if (value == null) return '';
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) return '刚刚更新';
    if (difference.inHours < 1) return '${difference.inMinutes} 分钟前更新';
    if (difference.inDays < 1) return '${difference.inHours} 小时前更新';
    if (difference.inDays < 7) return '${difference.inDays} 天前更新';
    return '${value.month}/${value.day} 更新';
  }

  @override
  Widget build(BuildContext context) {
    final data = record.cardData;
    final name = record.name;
    final description = _field(data, 'description');
    final personality = _field(data, 'personality');
    final scenario = _field(data, 'scenario');
    final systemPrompt = _field(data, 'system_prompt');
    final postHistory = _field(data, 'post_history_instructions');
    final creatorNotes = _field(data, 'creator_notes');
    final tags = _stringList(data, 'tags');
    final greetings = _stringList(data, 'alternate_greetings');
    final updatedText = _relativeUpdatedAt(record.updatedAt);

    final settingSections = <(String, String)>[
      ('角色描述', description),
      ('性格', personality),
      ('场景', scenario),
      ('系统提示', systemPrompt),
      ('对话后指令', postHistory),
      ('作者备注', creatorNotes),
    ].where((section) => section.$2.isNotEmpty).toList();

    final allSettingsEmpty = settingSections.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        // 身份头部：4:3 封面 + 名字/简介/标签/更新时间
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _CoverImage(path: record.thumbnailPath),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: readingTheme.sidebarPrimaryText,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: readingTheme.sidebarSecondaryText,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: readingTheme.composerToolSurface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: readingTheme.statusBorder,
                                ),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  color: readingTheme.sidebarSecondaryText,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (updatedText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        updatedText,
                        style: TextStyle(
                          color: readingTheme.sidebarTimestamp,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // 主操作：开始聊天
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: FilledButton.icon(
            onPressed: onStartChat,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('开始聊天'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ),
        const Divider(height: 1),
        if (allSettingsEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
            child: Text(
              '这张角色卡没有可阅读的设定文本。',
              style: TextStyle(
                color: readingTheme.sidebarSecondaryText,
                fontSize: 14,
              ),
            ),
          )
        else
          for (final section in settingSections) ...[
            _SettingSection(title: section.$1, text: section.$2, readingTheme: readingTheme),
            const Divider(height: 1),
          ],
        if (greetings.isNotEmpty) ...[
          _AlternateGreetingsSection(greetings: greetings, readingTheme: readingTheme),
          const Divider(height: 1),
        ],
        if (record.worldBookId != null && record.worldBookId!.isNotEmpty) ...[
          _WorldBookSection(
            worldBook: worldBook,
            loading: worldBookLoading,
            failed: worldBookFailed,
            readingTheme: readingTheme,
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final color = context.chatReadingTheme.composerToolSurface;
    if (path.isEmpty) {
      return ColoredBox(
        color: color,
        child: const Center(child: Icon(Icons.person_outline_rounded)),
      );
    }
    final provider = path.startsWith('assets/')
        ? AssetImage(path) as ImageProvider
        : FileImage(File(path));
    return Image(
      image: provider,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: color,
        child: const Center(child: Icon(Icons.person_outline_rounded)),
      ),
    );
  }
}

class _SettingSection extends StatelessWidget {
  const _SettingSection({
    required this.title,
    required this.text,
    required this.readingTheme,
  });

  final String title;
  final String text;
  final ChatReadingTheme readingTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: readingTheme.sidebarPrimaryText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            text,
            style: TextStyle(
              color: readingTheme.sidebarPrimaryText,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlternateGreetingsSection extends StatelessWidget {
  const _AlternateGreetingsSection({
    required this.greetings,
    required this.readingTheme,
  });

  final List<String> greetings;
  final ChatReadingTheme readingTheme;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      title: const Text('备用开场白'),
      subtitle: Text('${greetings.length} 条可用'),
      collapsedIconColor: readingTheme.sidebarSecondaryText,
      iconColor: readingTheme.sidebarSecondaryText,
      collapsedTextColor: readingTheme.sidebarPrimaryText,
      textColor: readingTheme.sidebarPrimaryText,
      children: [
        for (var i = 0; i < greetings.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(
              '${i + 1}. ${greetings[i]}',
              style: TextStyle(
                color: readingTheme.sidebarSecondaryText,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _WorldBookSection extends StatelessWidget {
  const _WorldBookSection({
    required this.worldBook,
    required this.loading,
    required this.failed,
    required this.readingTheme,
  });

  final WorldBook? worldBook;
  final bool loading;
  final bool failed;
  final ChatReadingTheme readingTheme;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      title: Text(worldBook?.name ?? '世界书'),
      subtitle: Text(
        worldBook == null
            ? (failed ? '关联世界书不可用' : '加载中…')
            : '${worldBook!.entries.length} 条条目',
      ),
      collapsedIconColor: readingTheme.sidebarSecondaryText,
      iconColor: readingTheme.sidebarSecondaryText,
      collapsedTextColor: readingTheme.sidebarPrimaryText,
      textColor: readingTheme.sidebarPrimaryText,
      children: [
        if (worldBook == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              failed ? '关联世界书暂时无法加载。' : '正在加载世界书…',
              style: TextStyle(
                color: readingTheme.sidebarSecondaryText,
                fontSize: 14,
              ),
            ),
          )
        else
          for (final entry in _visibleEntries(worldBook!))
            _WorldBookEntryDisclosure(entry: entry, readingTheme: readingTheme),
      ],
    );
  }

  List<WorldBookEntry> _visibleEntries(WorldBook book) {
    final enabled = book.entries.where((entry) => entry.isEnabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return enabled;
  }
}

class _WorldBookEntryDisclosure extends StatelessWidget {
  const _WorldBookEntryDisclosure({
    required this.entry,
    required this.readingTheme,
  });

  final WorldBookEntry entry;
  final ChatReadingTheme readingTheme;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.only(left: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
      title: Text(
        entry.title,
        style: TextStyle(
          color: readingTheme.sidebarPrimaryText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      collapsedIconColor: readingTheme.sidebarSecondaryText,
      iconColor: readingTheme.sidebarSecondaryText,
      collapsedTextColor: readingTheme.sidebarPrimaryText,
      textColor: readingTheme.sidebarPrimaryText,
      children: [
        SelectableText(
          entry.content,
          style: TextStyle(
            color: readingTheme.sidebarSecondaryText,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
