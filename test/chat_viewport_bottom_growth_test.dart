import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 实证（最终版）：reverse 聊天列表在真实流式输出场景（最后一条消息
/// 文本增长，底部坐标固定）下：
/// ① 贴底（pixels=0）时视口天然稳定——无需补偿，pixels 保持 0、
/// 可见内容为最后消息的底部文本；
/// ② maxScrollExtent 在部分 item 未构建时是估算值（虚高）——
/// 证实"依赖 maxScrollExtent 的补偿会把视口推错位置（跳顶）"的根因，
/// 因此贴底必须不补偿。
void main() {
  const viewportHeight = 600.0;

  bool isVisible(WidgetTester tester, String text) {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) {
      return false;
    }
    final rect = tester.getRect(finder);
    return rect.bottom > 0 && rect.top < viewportHeight;
  }

  Future<void> pumpList(
    WidgetTester tester,
    ScrollController controller,
    double lastHeight,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            reverse: true,
            itemCount: 5,
            itemBuilder: (context, index) => SizedBox(
              // index 0 = 最后一条消息（视觉底部），流式输出时高度增长
              height: index == 0 ? lastHeight : 200,
              child: Center(child: Text('msg$index')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('贴底（pixels=0）时最后消息高度增长：视口内容天然稳定', (tester) async {
    final controller = ScrollController();
    await pumpList(tester, controller, 200);
    controller.jumpTo(0); // 贴底
    await tester.pump();
    expect(controller.position.pixels, 0);
    expect(controller.position.maxScrollExtent, 400);

    // 贴底时可见内容：底部 3 条（msg0/msg1/msg2）
    expect(isVisible(tester, 'msg0'), isTrue);
    expect(isVisible(tester, 'msg1'), isTrue);
    expect(isVisible(tester, 'msg2'), isTrue);
    expect(isVisible(tester, 'msg3'), isFalse);

    // 流式输出：最后消息高度 200 → 1000（文本增长，底部坐标固定）
    await pumpList(tester, controller, 1000);

    // 不做任何补偿：pixels 保持 0，视口稳定显示 msg0 的底部文本
    expect(controller.position.pixels, 0);
    expect(isVisible(tester, 'msg0'), isTrue);
    // msg1/msg2 被 msg0 的增长顶出视口（msg0 占满底部一屏）
    expect(isVisible(tester, 'msg1'), isFalse);
  });

  testWidgets('maxScrollExtent 在未构建 item 区域为估算值（虚高）', (tester) async {
    final controller = ScrollController();
    await pumpList(tester, controller, 200);
    controller.jumpTo(0);
    await tester.pump();
    // 增长前：5 条全部构建过，maxExtent 精确 = 1000 - 600 = 400
    expect(controller.position.maxScrollExtent, 400);

    // 增长后：msg0=1000 且 msg1-4 未构建（在 cache 外），
    // maxScrollExtent 用最后布局 item 高度（1000）估算其余 → 虚高
    await pumpList(tester, controller, 1000);
    final estimatedMax = controller.position.maxScrollExtent;
    // 实际内容高度 = 1000 + 4×200 = 1800 → 精确 max 应 1200
    // 估算值必然偏离（本环境实测 4400），证明依赖 max 的补偿不可靠
    debugPrint('estimated max=$estimatedMax (exact would be 1200)');
    expect(estimatedMax, isNot(1200));
    // 关键：pixels 仍稳定在 0（贴底不受估算影响）
    expect(controller.position.pixels, 0);
  });

  testWidgets('非 reverse 列表：尾部追加新消息视口完全不动（本方案根基）', (tester) async {
    final controller = ScrollController();
    // 非 reverse：index 0 在顶部（最旧）
    final messages = <String>['m1', 'm2', 'm3', 'm4', 'm5'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            reverse: false,
            itemCount: messages.length,
            itemBuilder: (context, index) => SizedBox(
              height: 200,
              child: Center(child: Text(messages[index])),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 滚到任意中间位置（非贴底），记录 pixels
    controller.jumpTo(400);
    await tester.pump();
    final offsetBefore = controller.position.pixels;
    // 尾部追加新消息（如同输出结束自动合入）
    messages.add('new-message');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            reverse: false,
            itemCount: messages.length,
            itemBuilder: (context, index) => SizedBox(
              height: 200,
              child: Center(child: Text(messages[index])),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // 视口完全没动：pixels 保持不变，已显示内容不被顶走
    expect(controller.position.pixels, offsetBefore);
    // 老内容仍在原位置，新消息在视口外（下方）
    expect(isVisible(tester, 'm3'), isTrue);
    expect(isVisible(tester, 'm4'), isTrue);
    expect(isVisible(tester, 'new-message'), isFalse);
  });
}
