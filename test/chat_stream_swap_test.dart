import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/chat_message.dart';
import 'package:pocket_inn/pages/chat/widgets/chat_message_list.dart';
import 'package:pocket_inn/pages/chat/widgets/stream_bubble.dart';

/// 特别版：验证流式输出在列表外悬浮面板（StreamingPanel）展示——
/// 流式期间列表零增长、主界面彻底定住；输出结束一次性加入正式消息。
void main() {
  Widget buildList(
    ScrollController controller,
    List<ChatMessage> messages, {
    required bool isSending,
    String streamingText = '',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChatMessageList(
          visibleMessages: messages,
          scrollController: controller,
          inputTapRegionGroupId: Object(),
          isSending: isSending,
          streamingText: streamingText,
          isImpersonating: false,
          regeneratingUserMessageId: null,
          isDraftSession: false,
          activeCharacter: null,
          currentUserSetting: null,
          sessionId: 's1',
          groupCharacterNames: const {},
          onCopyMessage: (_) {},
          onEditMessage: (_) {},
          onEditDraftOpeningMessage: () {},
          onDeleteMessage: (_) {},
          onRegenerateFromUserMessage: (_) {},
          onRegenerateMessage: (_) {},
          onContinueMessage: (_) {},
          onImpersonate: () {},
          onSwitchMessageVariant: (_, _) {},
        ),
      ),
    );
  }

  testWidgets('非 reverse 列表：流式悬浮面板 + 完成后自动合入视口不动', (tester) async {
    final controller = ScrollController();
    // 历史 3 条（各 200px）——非 reverse 列表：index 0 在顶部（最旧）
    final history = [
      for (var i = 0; i < 3; i++)
        ChatMessage(id: 'h$i', text: '历史消息 $i', isMe: i.isOdd),
    ];
    var isSending = true;
    var messages = [...history];

    await tester.pumpWidget(
      buildList(
        controller,
        messages,
        isSending: isSending,
        streamingText: '正在输出…',
      ),
    );
    // 贴底（非 reverse 列表：offset = maxScrollExtent = 视觉底部）
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final bottomOffset = controller.position.pixels;
    // 悬浮面板可见（列表外），列表仍只有历史 3 条（零增长）
    expect(find.byType(StreamingPanel), findsOneWidget);
    expect(find.textContaining('正在输出'), findsOneWidget);
    expect(find.textContaining('历史消息 2'), findsOneWidget);

    // 输出结束：自动合入（正式消息进入列表，非 reverse 尾部追加
    // 不顶动视口），浮层消失
    isSending = false;
    messages = [
      ...history,
      ChatMessage(
        id: 'final-1',
        text: '这是完整的正式回复内容，比占位气泡长很多很多……',
        isMe: false,
      ),
    ];
    await tester.pumpWidget(
      buildList(
        controller,
        messages,
        isSending: isSending,
        streamingText: '',
      ),
    );
    await tester.pump();

    // 视口完全没动：pixels 保持（非 reverse 尾部追加不顶动内容）
    expect(controller.position.pixels, bottomOffset);
    // 正式消息已合入列表，悬浮面板消失
    expect(find.textContaining('完整的正式回复内容'), findsOneWidget);
    expect(find.byType(StreamingPanel), findsNothing);
    expect(find.text('查看最新回复'), findsNothing);
  });
}


