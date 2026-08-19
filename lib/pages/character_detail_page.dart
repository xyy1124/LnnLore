import 'dart:io';

import 'package:flutter/material.dart';

import '../models/character_card.dart';
import '../services/character_service.dart';
import '../theme/chat_reading_theme.dart';

/// 只读角色详情页（v99）：上方封面 + 角色名，下方只读角色卡原始设定
/// （description/personality/scenario/system_prompt/post_history_instructions/
/// creator_notes），空字段隐藏；备用开场白、世界书、标签等在编辑页查看，
/// 不塞进详情页。开始聊天走调用方注入的 [onStartChat]（复用列表页完整
/// 聊天创建流程）。
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

  @override
  void initState() {
    super.initState();
    _recordFuture = CharacterService.instance.loadById(widget.characterId);
  }

  Future<void> _retry() async {
    setState(() {
      _recordFuture = CharacterService.instance.loadById(widget.characterId);
    });
    await _recordFuture;
  }

  @override
  Widget build(BuildContext context) {
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
            onStartChat: widget.onStartChat,
            readingTheme: context.chatReadingTheme,
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
    required this.onStartChat,
    required this.readingTheme,
  });

  final CharacterCardRecord record;
  final VoidCallback onStartChat;
  final ChatReadingTheme readingTheme;

  String _field(Map<String, dynamic> data, String key) =>
      (data[key] as String? ?? '').trim();

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

    // 详情页只放角色设定；备用开场/世界书/标签等在编辑页查看。
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
        // 身份头部：左上角封面 + 旁边角色名
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 110,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _CoverImage(path: record.thumbnailPath),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: readingTheme.sidebarPrimaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
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
            _SettingSection(
              title: section.$1,
              text: section.$2,
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
