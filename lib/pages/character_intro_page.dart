import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../models/character_card.dart';
import '../models/world_book.dart';
import '../services/character_intro_service.dart';
import '../services/world_book_service.dart';
import '../widgets/chat_markdown_body.dart';

/// 角色 AI 通读介绍页（特别版）。
///
/// 通读角色卡与配套世界书，展示 AI 生成的角色简介与玩法说明。
class CharacterIntroPage extends StatefulWidget {
  const CharacterIntroPage({
    super.key,
    required this.character,
    this.worldBookId,
  });

  final CharacterCardRecord character;
  final String? worldBookId;

  @override
  State<CharacterIntroPage> createState() => _CharacterIntroPageState();
}

class _CharacterIntroPageState extends State<CharacterIntroPage> {
  String? _introduction;
  String? _error;
  bool _loading = true;
  WorldBook? _worldBook;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _introduction = null;
    });

    try {
      final worldBookId = widget.worldBookId;
      WorldBook? worldBook;
      if (worldBookId != null && worldBookId.isNotEmpty) {
        worldBook = await WorldBookService.instance.loadById(worldBookId);
      }
      final text = await CharacterIntroService.instance.generateIntroduction(
        character: widget.character,
        worldBook: worldBook,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _introduction = text;
        _worldBook = worldBook;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.character.name} · 角色介绍')),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('AI 正在通读角色卡与世界书…'),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text('生成失败：$_error'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_worldBook != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '已通读世界书：${_worldBook!.name}'
                            '（${_worldBook!.entries.where((e) => e.isEnabled).length} 个条目）',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ValueListenableBuilder<AppSettings>(
                        valueListenable: appSettingsNotifier,
                        builder: (context, settings, _) {
                          final colorScheme = Theme.of(context).colorScheme;
                          return ChatMarkdownBody(
                            text: _introduction ?? '',
                            settings: settings,
                            textColor: colorScheme.onSurface,
                            inlineCodeColor: colorScheme.primary,
                            codeBlockColor: colorScheme.primaryContainer,
                            selectable: true,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _generate,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新生成'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
