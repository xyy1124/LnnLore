import 'package:flutter/material.dart';

import '../data/preset_selection.dart';
import '../models/character_card.dart';
import '../models/group_chat_session.dart';
import '../services/character_service.dart';
import '../services/group_chat_service.dart';
import 'chat_page.dart';

/// 创建群聊页（特别版）。
///
/// 从角色列表多选成员（至少 2 个），创建群聊并进入聊天页。
class GroupChatCreatePage extends StatefulWidget {
  const GroupChatCreatePage({super.key});

  @override
  State<GroupChatCreatePage> createState() => _GroupChatCreatePageState();
}

class _GroupChatCreatePageState extends State<GroupChatCreatePage> {
  List<CharacterSummary> _characters = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _creating = false;

  /// 特别版：群聊回复模式（轮流制 / 全员回复）。
  GroupChatReplyMode _replyMode = GroupChatReplyMode.rotation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final characters = await CharacterService.instance.loadAllSummaries();
    if (!mounted) {
      return;
    }
    setState(() {
      _characters = characters;
      _loading = false;
    });
  }

  Future<void> _onCreate() async {
    if (_selectedIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择 2 个角色')),
      );
      return;
    }
    setState(() {
      _creating = true;
    });

    try {
      final selected = _characters
          .where((c) => _selectedIds.contains(c.id))
          .toList();
      final group = await GroupChatService.instance.create(
        title: selected.map((c) => c.name).join(' × '),
        characterIds: selected.map((c) => c.id).toList(),
        replyMode: _replyMode.value,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatPage.draft(
            groupId: group.id,
            groupTitle: group.title,
            groupCharacterIds: group.characterIds,
            // 特别版：群聊继承当前全局选中的预设——上下文上限（如 1M）
            // 与单聊保持一致，否则群聊会回退到模型默认窗口（128K）
            selectedPresetId: selectedPresetIdNotifier.value,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建群聊失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群聊'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _onCreate,
            child: Text(
              _creating ? '创建中…' : '创建（${_selectedIds.length}）',
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _characters.isEmpty
          ? const Center(child: Text('还没有角色，请先导入角色卡'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _characters.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  // 特别版：回复模式选择
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '回复模式',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<GroupChatReplyMode>(
                            segments: const [
                              ButtonSegment(
                                value: GroupChatReplyMode.rotation,
                                icon: Icon(Icons.compare_arrows),
                                label: Text('轮流回复'),
                              ),
                              ButtonSegment(
                                value: GroupChatReplyMode.everyone,
                                icon: Icon(Icons.groups),
                                label: Text('全员回复'),
                              ),
                            ],
                            selected: {_replyMode},
                            onSelectionChanged: (selection) {
                              setState(() {
                                _replyMode = selection.first;
                              });
                            },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _replyMode == GroupChatReplyMode.rotation
                                ? '你发一条消息，当前轮到的角色回复，然后自动切换到下一位（可手动指定发言人）'
                                : '你发一条消息，所有成员按顺序自动依次回复，一次看全员反应',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final character = _characters[index - 1];
                final selected = _selectedIds.contains(character.id);
                return Card(
                  child: CheckboxListTile(
                    value: selected,
                    title: Text(character.name),
                    subtitle: Text(
                      character.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondary: CircleAvatar(
                      backgroundColor: Color(
                        (character.cardColorValue ?? 0xFFE76F51) & 0xFFFFFFFF,
                      ),
                      child: Text(character.name.characters.first),
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedIds.add(character.id);
                        } else {
                          _selectedIds.remove(character.id);
                        }
                      });
                    },
                  ),
                );
              },
            ),
    );
  }
}
