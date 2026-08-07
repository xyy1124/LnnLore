import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// 聊天消息数据模型
@freezed
abstract class ChatMessage with _$ChatMessage {
  const ChatMessage._();

  const factory ChatMessage({
    String? id,
    String? sessionId,
    String? parentId,
    required String text,
    required bool isMe,
    /// 当前消息索引（从1开始）
    @Default(1) int index,
    /// 该角色的总消息数
    @Default(1) int total,
    /// 同级消息 ID 列表，顺序与 index/total 对应
    @Default([]) List<String> siblingIds,
    /// 思考链内容（可选）
    String? thinkingChain,
    /// 特别版：发送给模型的完整内容（快捷指令场景下与 [text] 不同）
    String? modelText,
    /// 特别版：群聊中本条消息的发言角色 id（assistant 消息；非群聊为 null）
    String? characterId,
    /// 特别版：是否为用户中途停止产生的部分输出（不入记忆提取）
    @Default(false) bool isPartial,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  /// 是否有多条消息（需要显示<1/x>按钮）
  bool get hasMultiple => total > 1;

  /// 是否有思考链
  bool get hasThinkingChain =>
      thinkingChain != null && thinkingChain!.isNotEmpty;
}
