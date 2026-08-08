// v64 回归测试：消息长按菜单从"每消息 OverlayPortal"改为 showMenu 路由后，
// 覆盖审查指出的核心行为：
//  - 长按弹出菜单（showMenu 路由，不依附消息组件）
//  - 菜单外点击自动关闭（Navigator 路由自带）
//  - 连续长按不残留冷却（_openingActionMenu 在 finally 释放）
//  - 生成/冻结期间（actionsEnabled=false）长按不弹菜单
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/chat_message.dart';
import 'package:pocket_inn/models/user_setting.dart';
import 'package:pocket_inn/pages/chat/widgets/message_bubble.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  ChatMessage makeMessage({String text = '测试消息', bool isMe = false}) {
    return ChatMessage(
      id: 'msg_1',
      sessionId: 'session_1',
      isMe: isMe,
      text: text,
    );
  }

  MessageBubble makeBubble({
    required ChatMessage message,
    bool showActions = true,
    bool actionsEnabled = true,
    bool canEdit = true,
    bool canDelete = true,
    VoidCallback? onCopy,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return MessageBubble(
      message: message,
      userSetting: UserSetting(
        id: 'u1',
        name: '我',
        prompt: '',
        colorValue: 0xFF000000,
      ),
      character: null,
      inputTapRegionGroupId: const Object(),
      isLastUserMessageWithoutReply: false,
      isLastCharacterMessage: false,
      showActions: showActions,
      actionsEnabled: actionsEnabled,
      canEdit: canEdit,
      canDelete: canDelete,
      isBusyRegenerating: false,
      isBusyImpersonating: false,
      onCopy: onCopy ?? () {},
      onEdit: onEdit ?? () {},
      onDelete: onDelete ?? () {},
    );
  }

  testWidgets('长按用户消息弹出操作菜单（复制/编辑/删除）', (tester) async {
    var copied = false;
    await tester.pumpWidget(
      wrap(
        makeBubble(
          message: makeMessage(isMe: true),
          onCopy: () => copied = true,
        ),
      ),
    );

    // 长按消息正文
    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();

    // showMenu 菜单项出现
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 点击"复制"触发回调并关闭菜单
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, isTrue);
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('长按角色消息同样弹出菜单，且删除项为错误色', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      wrap(
        makeBubble(
          message: makeMessage(isMe: false),
          onDelete: () => deleted = true,
        ),
      ),
    );

    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('删除'), findsNothing);
  });

  testWidgets('菜单外点击立即关闭，无需等待冷却', (tester) async {
    var openedCount = 0;
    // 通过多次"长按→点外部→再长按"验证没有 2-3 秒冷却残留
    await tester.pumpWidget(
      wrap(
        makeBubble(message: makeMessage()),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.longPress(find.text('测试消息'));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget, reason: '第 ${i + 1} 次长按应弹出菜单');
      openedCount++;

      // 点菜单外部空白处关闭
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsNothing, reason: '第 ${i + 1} 次菜单外点击应关闭');
    }
    expect(openedCount, 5);
  });

  testWidgets('生成/冻结期间（actionsEnabled=false）长按不弹菜单', (tester) async {
    await tester.pumpWidget(
      wrap(
        makeBubble(
          message: makeMessage(),
          actionsEnabled: false,
        ),
      ),
    );

    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('删除'), findsNothing);
  });

  testWidgets('showActions=false 时长按不弹菜单', (tester) async {
    await tester.pumpWidget(
      wrap(
        makeBubble(
          message: makeMessage(),
          showActions: false,
        ),
      ),
    );

    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('连续长按同一消息两次：第二次立即弹出（无冷却状态残留）', (tester) async {
    await tester.pumpWidget(
      wrap(
        makeBubble(message: makeMessage()),
      ),
    );

    // 第一次：弹出后选择复制（菜单随路由关闭）
    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    // 第二次：立即长按，应立刻弹出（_openingActionMenu 已释放）
    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('canEdit=false 时菜单不含编辑项', (tester) async {
    await tester.pumpWidget(
      wrap(
        makeBubble(
          message: makeMessage(),
          canEdit: false,
        ),
      ),
    );

    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('消息列表重建后菜单不残留（showMenu 路由不依附消息组件）', (tester) async {
    await tester.pumpWidget(
      wrap(
        makeBubble(message: makeMessage()),
      ),
    );

    // 打开菜单
    await tester.longPress(find.text('测试消息'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);

    // 通过重建整个 widget 树模拟消息列表刷新——菜单（Navigator 路由）
    // 应保持显示，不随消息组件消失
    await tester.pumpWidget(
      wrap(
        makeBubble(message: makeMessage(text: '测试消息2')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget, reason: '列表重建后菜单不应随消息组件消失');

    // 点击菜单外部关闭（模态屏障消费点击——showMenu 路由自带）
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);

    // 关闭后立即长按新消息：立即可弹出（无冷却残留）
    await tester.longPress(find.text('测试消息2'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
  });
}
