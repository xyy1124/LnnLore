import 'package:freezed_annotation/freezed_annotation.dart';

part 'group_chat_session.freezed.dart';
part 'group_chat_session.g.dart';

/// 群聊回复模式（特别版）。
enum GroupChatReplyMode {
  /// 轮流制：每条用户消息只由当前轮到的角色回复，然后自动切换。
  rotation('rotation'),

  /// 全员回复：用户消息后所有成员按顺序自动依次回复。
  everyone('everyone');

  const GroupChatReplyMode(this.value);

  final String value;

  static GroupChatReplyMode fromValue(String? value) {
    for (final mode in GroupChatReplyMode.values) {
      if (mode.value == value) {
        return mode;
      }
    }
    return GroupChatReplyMode.rotation;
  }
}

/// 群聊会话（特别版）。
///
/// 多个角色在同一会话中回复（默认轮流制，可在创建时选择全员回复）。
/// 群聊的聊天消息复用现有 chat_messages 表，
/// 通过 chat_sessions.character_id = 'group:<id>' 关联。
@freezed
abstract class GroupChatSession with _$GroupChatSession {
  const GroupChatSession._();

  const factory GroupChatSession({
    required String id,
    required String title,
    required List<String> characterIds,
    /// 下一位回复的角色索引（轮转游标）
    @Default(0) int turnIndex,
    /// 回复模式（特别版）：rotation 轮流制 / everyone 全员回复
    @Default('rotation') String replyMode,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _GroupChatSession;

  factory GroupChatSession.fromJson(Map<String, dynamic> json) =>
      _$GroupChatSessionFromJson(json);

  /// 会话的 character_id 标记（用于 chat_sessions 表关联）。
  String get sessionCharacterId => 'group:$id';

  /// 回复模式（解析后的枚举）。
  GroupChatReplyMode get parsedReplyMode =>
      GroupChatReplyMode.fromValue(replyMode);
}

/// 判断 character_id 是否为群聊标记。
bool isGroupChatCharacterId(String characterId) => characterId.startsWith('group:');

/// 从群聊标记中解析群组 id。
String? parseGroupChatId(String characterId) {
  if (!isGroupChatCharacterId(characterId)) {
    return null;
  }
  return characterId.substring('group:'.length);
}
