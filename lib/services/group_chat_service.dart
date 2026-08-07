import 'dart:math';

import '../models/group_chat_session.dart';
import 'chat_database_service.dart';
import 'storage_service.dart';

/// 群聊会话服务（特别版）。
///
/// 群聊列表存于 `group_chats.json`（结构 `{version, groups[]}`）。
/// 群聊的聊天消息复用现有 chat_messages 表，
/// 通过 `chat_sessions.character_id = 'group:&lt;id&gt;'` 关联。
class GroupChatService {
  GroupChatService._();

  static final GroupChatService instance = GroupChatService._();

  static const String _filename = 'group_chats.json';
  static const int _dataVersion = 1;

  /// 加载全部群聊。
  Future<List<GroupChatSession>> loadAll() async {
    final storage = StorageService.instance;

    final data = await storage.readJsonMap(_filename);
    if (data == null) {
      return [];
    }

    try {
      final version = data['version'] as int? ?? 1;
      if (version != _dataVersion) {
        return [];
      }
      final groupsList = data['groups'] as List<dynamic>? ?? [];
      return groupsList
          .map(
            (json) => GroupChatSession.fromJson(
              json as Map<String, dynamic>,
            ),
          )
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _saveAll(List<GroupChatSession> groups) async {
    await StorageService.instance.writeJsonMap(_filename, {
      'version': _dataVersion,
      'groups': groups.map((g) => g.toJson()).toList(),
    });
  }

  /// 按 id 加载群聊。
  Future<GroupChatSession?> loadById(String id) async {
    final groups = await loadAll();
    for (final group in groups) {
      if (group.id == id) {
        return group;
      }
    }
    return null;
  }

  /// 创建群聊。
  Future<GroupChatSession> create({
    required String title,
    required List<String> characterIds,
    /// 回复模式（特别版）：rotation 轮流制 / everyone 全员回复
    String replyMode = 'rotation',
  }) async {
    final groups = await loadAll();
    final group = GroupChatSession(
      id: generateId(),
      title: title,
      characterIds: characterIds,
      replyMode: replyMode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    groups.add(group);
    await _saveAll(groups);
    return group;
  }

  /// 更新群聊（标题/成员/轮转游标）。
  Future<void> update(GroupChatSession group) async {
    final groups = await loadAll();
    final index = groups.indexWhere((g) => g.id == group.id);
    if (index == -1) {
      return;
    }
    groups[index] = group.copyWith(updatedAt: DateTime.now());
    await _saveAll(groups);
  }

  /// 删除群聊（同时删除关联的聊天会话；数据库未就绪时忽略级联删除）。
  Future<void> delete(String id) async {
    final groups = await loadAll();
    groups.removeWhere((g) => g.id == id);
    await _saveAll(groups);
    try {
      await ChatDatabaseService.instance.deleteSessionsByCharacterId(
        'group:$id',
      );
    } on Object {
      // 数据库未初始化等情况下，仅删除群组记录
    }
  }

  /// 获取下一位回复的角色 id（轮转），并推进游标。
  ///
  /// 游标 [turnIndex] 始终指向"当前发言人"：初始为 0（第一人），
  /// 每次调用返回**下一位**并将游标推进到该位。
  Future<String?> nextTurnCharacterId(String groupId) async {
    final group = await loadById(groupId);
    if (group == null || group.characterIds.isEmpty) {
      return null;
    }
    final nextIndex =
        (group.turnIndex + 1) % group.characterIds.length;
    final next = group.characterIds[nextIndex];
    await update(
      group.copyWith(turnIndex: nextIndex),
    );
    return next;
  }

  /// 生成唯一ID。
  String generateId() {
    final random = Random().nextInt(0xFFFFFF).toRadixString(16);
    return 'group-${DateTime.now().millisecondsSinceEpoch}-$random';
  }
}
