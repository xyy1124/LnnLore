import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 特别版：验证 reverse 聊天列表的行为实证。
///
/// 场景还原：reverse 聊天列表（index 0 在视觉底部 = 最新消息），
/// 流式输出在底部追加新内容（数据 insert(0)，旧消息 index 平移 =
/// 已布局内容整体平移，flutter/flutter#155152）。视口应保持显示
/// 发送时的内容，不得跳动/跳顶。
void main() {
  const viewportHeight = 600.0;
  const itemHeight = 200.0;

  /// 判断文本是否真正渲染在视口内（未构建/在 cache 区域均视为不可见）。
  bool isVisible(WidgetTester tester, String text) {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) {
      return false;
    }
    final rect = tester.getRect(finder);
    return rect.bottom > 0 && rect.top < viewportHeight;
  }

  Future<void> pumpChat(
    WidgetTester tester,
    ScrollController controller,
    List<String> messages,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (context, index) => SizedBox(
              height: itemHeight,
              child: Center(child: Text(messages[index])),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('底部追加内容后按距顶恒定补偿，可见内容保持原样', (tester) async {
    final controller = ScrollController();
    // 数据头部 = 视觉底部（最新消息）：m1 为初始最新
    final messages = <String>['m1', 'm2', 'm3', 'm4', 'm5'];
    await pumpChat(tester, controller, messages);
    // 贴底（reverse 列表 pixels = 0 = 视觉底部）
    controller.jumpTo(0);
    await tester.pump();
    final dist = controller.position.maxScrollExtent - controller.position.pixels;
    expect(dist, controller.position.maxScrollExtent); // 贴底：距顶 = max
    expect(controller.position.pixels, 0);

    // 初始可见：底部 3 条 = m1、m2、m3
    expect(isVisible(tester, 'm1'), isTrue);
    expect(isVisible(tester, 'm2'), isTrue);
    expect(isVisible(tester, 'm3'), isTrue);
    expect(isVisible(tester, 'm4'), isFalse);

    // 流式输出在底部追加 3 条新消息：数据 insert(0)，旧消息 index 平移
    messages.insertAll(0, ['n1', 'n2', 'n3']);
    await pumpChat(tester, controller, messages);
    // 帧末补偿：target = maxScrollExtent - dist（与 chat_page 逻辑一致）
    final target = (controller.position.maxScrollExtent - dist).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(target);
    await tester.pump();

    // 视口显示的内容应与增长前一致：m1/m2/m3 可见，m4 不可见
    expect(controller.position.pixels, closeTo(600, 0.001));
    expect(isVisible(tester, 'm1'), isTrue);
    expect(isVisible(tester, 'm2'), isTrue);
    expect(isVisible(tester, 'm3'), isTrue);
    expect(isVisible(tester, 'm4'), isFalse);
    // 新消息（n1/n2/n3）在视口下方，不可见
    expect(isVisible(tester, 'n1'), isFalse);
    expect(isVisible(tester, 'n2'), isFalse);
  });

  testWidgets('多轮增长距顶恒定补偿目标恒在合法范围（不可能跳顶）', (tester) async {
    final controller = ScrollController();
    final messages = <String>['m1', 'm2', 'm3', 'm4', 'm5'];
    await pumpChat(tester, controller, messages);
    controller.jumpTo(0);
    await tester.pump();
    final dist = controller.position.maxScrollExtent;

    // 模拟多轮流式增长并补偿
    for (var round = 0; round < 6; round++) {
      messages.insertAll(0, ['n${round}a', 'n${round}b']);
      await pumpChat(tester, controller, messages);
      final max = controller.position.maxScrollExtent;
      final target = (max - dist).clamp(0.0, max);
      expect(target, lessThanOrEqualTo(max));
      expect(target, greaterThanOrEqualTo(0));
      controller.jumpTo(target);
      await tester.pump();
    }
    // 多轮增长后视口仍在内容中部（距顶距离保持），未跳到顶端
    final finalMax = controller.position.maxScrollExtent;
    expect(controller.position.pixels, closeTo(finalMax - dist, 0.001));
    // 旧可见内容仍在视口内
    expect(isVisible(tester, 'm2'), isTrue);
    expect(isVisible(tester, 'm3'), isTrue);
  });
}
