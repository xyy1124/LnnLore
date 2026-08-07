import 'package:flutter/material.dart';

import '../../../models/chat_message.dart';
import '../../../models/user_setting.dart';
import '../../../services/chat_character_resolver.dart';
import '../../../widgets/scroll_float_button.dart';
import 'message_bubble.dart';
import 'stream_bubble.dart';

/// 聊天消息列表（含滚动浮动按钮）。
///
/// 从原 [ChatPage] 的 build 方法中拆出，负责根据可见消息列表渲染
/// [MessageBubble] 并将用户事件转发给回调。
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.visibleMessages,
    required this.scrollController,
    /// 特别版：底部真实锚点（父级持有 GlobalKey，跳底 ensureVisible 对齐）
    this.bottomAnchorKey,
    /// 特别版：到底按钮外部回调（父级统一可靠跳底）
    this.onScrollToBottom,
    required this.inputTapRegionGroupId,
    required this.isSending,
    /// 特别版：流式悬浮面板数据（列表外显示，列表零增长）
    this.streamingText = '',
    this.streamingThinking = '',
    this.streamingIsThinking = false,
    this.streamingRetryNotice = '',
    this.streamingSpeakerName,
    /// 特别版：列表冻结中（禁用编辑/删除/重生成——冻结视图索引
    /// 与真实数据不一致，操作会错位）
    this.messagesFrozen = false,
    required this.isImpersonating,
    required this.regeneratingUserMessageId,
    required this.isDraftSession,
    required this.activeCharacter,
    /// 特别版：群聊成员按 id 查找（消息头像/发言人渲染用）
    this.groupCharactersById = const {},
    required this.currentUserSetting,
    required this.sessionId,
    /// 特别版：群聊发言人名称映射（characterId → 角色名），用于群聊消息标识
    this.groupCharacterNames = const {},
    required this.onCopyMessage,
    required this.onEditMessage,
    required this.onEditDraftOpeningMessage,
    required this.onDeleteMessage,
    required this.onRegenerateFromUserMessage,
    required this.onRegenerateMessage,
    required this.onContinueMessage,
    required this.onImpersonate,
    required this.onSwitchMessageVariant,
    /// 特别版：消息动作按钮（模型 choices）点击回调
    this.onChoicePressed,
    /// 特别版：会话变量表（{{getvar::key}} 显示解析数据源）
    this.sessionVariables = const {},
  });

  final void Function(String label, String action)? onChoicePressed;

  /// 特别版：会话变量表（{{getvar::key}} 显示解析数据源）。
  final Map<String, String> sessionVariables;

  final List<ChatMessage> visibleMessages;

  /// 底部锚点 key（末尾追加一个轻量 SizedBox，作为"真实底部"）。
  final Key? bottomAnchorKey;

  /// 到底按钮外部回调；null 时按钮回退到旧的 maxScrollExtent 循环。
  final VoidCallback? onScrollToBottom;
  final ScrollController scrollController;
  final Object inputTapRegionGroupId;
  final bool isSending;
  final String streamingText;
  final String streamingThinking;
  final bool streamingIsThinking;
  final String streamingRetryNotice;
  final String? streamingSpeakerName;
  final bool messagesFrozen;
  final bool isImpersonating;
  final String? regeneratingUserMessageId;
  final bool isDraftSession;
  final ResolvedChatCharacter? activeCharacter;
  final Map<String, ResolvedChatCharacter> groupCharactersById;
  final UserSetting? currentUserSetting;
  final String? sessionId;

  /// 特别版：群聊发言人名称映射（characterId → 角色名）。
  final Map<String, String> groupCharacterNames;

  final void Function(ChatMessage msg) onCopyMessage;
  final void Function(int index) onEditMessage;
  final VoidCallback onEditDraftOpeningMessage;
  final void Function(int index) onDeleteMessage;
  final void Function(int index) onRegenerateFromUserMessage;
  final void Function(int index) onRegenerateMessage;
  final void Function(int index) onContinueMessage;
  final VoidCallback onImpersonate;
  final void Function(ChatMessage message, int delta) onSwitchMessageVariant;

  @override
  Widget build(BuildContext context) {
    if (visibleMessages.isEmpty) {
      return const Center(child: Text('这段聊天还没有消息'));
    }
    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0x00FFFFFF),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: const [0.0, 0.03, 0.97, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
          // v59：移除 ValueKey(sessionId)——草稿会话第一次发送会创建
          // 正式会话并更换 ID，key 变化会让 Flutter 重建整棵列表、随后
          // 新 ID 被当成"首次打开"触发可靠跳底（"有时跳底"来源之一）。
          // 消息气泡自带消息 ID key，列表滚动位置由外层手动管理。
          controller: scrollController,
          // 特别版：普通列表（非 reverse）——新消息追加到尾部不顶动
          // 视口；解冻合入后视口位置天然保持，与"界面不动"目标一致。
          reverse: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          // 特别版：末尾 +1 追加真实底部锚点（跳底 ensureVisible 对齐用）
          itemCount: visibleMessages.length + 1,
          itemBuilder: (context, index) {
            // 非 reverse：index 0 = 顶部（最旧），尾部 = 最新
            if (index == visibleMessages.length) {
              // 真实底部锚点：轻量占位，跳底时 ensureVisible(alignment: 1.0)
              return SizedBox(
                key: bottomAnchorKey,
                height: 12,
              );
            }
            final messageIndex = index;
            final msg = visibleMessages[messageIndex];
            final isLastMessage = messageIndex == visibleMessages.length - 1;
            final isLastUserMessageWithoutReply = isLastMessage && msg.isMe;
            final isLastCharacterMessage = isLastMessage && !msg.isMe;
            final isRegeneratingUserMessage =
                regeneratingUserMessageId != null &&
                msg.id == regeneratingUserMessageId;
            // 特别版：流式输出在列表外悬浮面板（StreamingPanel）展示，
            // 列表零增长——发消息后主界面彻底定住。
            final hasPersistedMessage = msg.id != null;
            final hasDraftOpeningActions =
                isDraftSession && !hasPersistedMessage && !msg.isMe;
            // v51：显示与可用分离——操作区始终保留布局（生成/冻结时
            // 只是禁用+淡出），避免操作按钮消失导致消息高度变化、
            // 流式输出期间视口跳动（"输出时界面不动"回归根因）。
            final showActions = hasPersistedMessage || hasDraftOpeningActions;
            final actionsEnabled =
                (!isSending || isRegeneratingUserMessage) && !messagesFrozen;
            final canEditMessage =
                (hasPersistedMessage || hasDraftOpeningActions) &&
                !isSending &&
                !messagesFrozen;
            final canDeleteMessage =
                hasPersistedMessage && !isSending && !messagesFrozen;
            // 特别版：群聊消息的发言人名称
            final speakerName = !msg.isMe && msg.characterId != null
                ? groupCharacterNames[msg.characterId]
                : null;
            final Widget itemContent = Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: msg.isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (speakerName != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        bottom: 2,
                      ),
                      child: Text(
                        speakerName,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  MessageBubble(
                    key: ValueKey(msg.id ?? messageIndex),
                    message: msg,
                    userSetting: currentUserSetting,
                    character: activeCharacter,
                    // 特别版：群聊消息头像/名字按发言人解析
                    resolvedSpeaker: msg.characterId != null
                        ? groupCharactersById[msg.characterId]
                        : null,
                    inputTapRegionGroupId: inputTapRegionGroupId,
                    isLastUserMessageWithoutReply: isLastUserMessageWithoutReply,
                    isLastCharacterMessage: isLastCharacterMessage,
                    showActions: showActions,
                    actionsEnabled: actionsEnabled,
                    canEdit: canEditMessage,
                    canDelete: canDeleteMessage,
                    isBusyRegenerating: isRegeneratingUserMessage,
                    isBusyImpersonating: isImpersonating,
                    onCopy: () => onCopyMessage(msg),
                onEdit: hasDraftOpeningActions
                    ? onEditDraftOpeningMessage
                    : () => onEditMessage(messageIndex),
                onDelete: () => onDeleteMessage(messageIndex),
                onGenerate:
                    isLastUserMessageWithoutReply &&
                        showActions &&
                        actionsEnabled &&
                        !isRegeneratingUserMessage
                    ? () => onRegenerateFromUserMessage(messageIndex)
                    : null,
                onRegenerate: isLastCharacterMessage &&
                        showActions &&
                        actionsEnabled
                    ? () => onRegenerateMessage(messageIndex)
                    : null,
                onContinue: isLastCharacterMessage &&
                        showActions &&
                        actionsEnabled
                    ? () => onContinueMessage(messageIndex)
                    : null,
                onImpersonate: isLastCharacterMessage && showActions
                    ? onImpersonate
                    : null,
                onSelectPreviousVariant: msg.hasMultiple && !messagesFrozen
                    ? () => onSwitchMessageVariant(msg, -1)
                    : null,
                onSelectNextVariant: msg.hasMultiple && !messagesFrozen
                    ? () => onSwitchMessageVariant(msg, 1)
                    : null,
                onChoicePressed: onChoicePressed,
                sessionVariables: sessionVariables,
                  ),
                ],
              ),
            );
            return itemContent;
          },
        ),
        ),
        // 特别版：流式输出悬浮面板（列表外，固定高度）——流式期间
        // 列表冻结（显示发送前快照），主界面完全不动；输出结束自动
        // 合入（非 reverse 尾部追加不顶动视口），浮层消失。
        if (isSending)
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: IgnorePointer(
              // 流式中不拦截触摸（不挡列表滚动）
              child: StreamingPanel(
                text: streamingText,
                thinking: streamingThinking,
                isThinking: streamingIsThinking,
                retryNotice: streamingRetryNotice,
                speakerName: streamingSpeakerName,
              ),
            ),
          ),
        Positioned(
          right: 16,
          // 流式面板显示时上移按钮，避免遮挡
          bottom: isSending ? 168 : 16,
          child: ScrollFloatButton(
            scrollController: scrollController,
            isReversed: false,
            // 特别版：到底统一走父级可靠跳底（bottom anchor 对齐）
            onScrollToBottom: onScrollToBottom,
          ),
        ),
      ],
    );
  }
}
