// v84 回归测试：解冻后视口位置恢复策略——
//  - 旧快照不可滚动（内容不足一屏）且处于逻辑底部时，解冻后应跳新底部
//    （否则恢复 pixels=0 会把视口钉在新列表顶部——首条消息视窗跳动根因）
//  - 已有可滚动历史仍恢复旧 pixels（第二、三轮行为不变）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/pages/chat_page.dart';

void main() {
  group('shouldRestoreToNewBottomAfterUnfreeze（v84 决策逻辑）', () {
    test('旧快照不可滚动 + 逻辑底部 → 跳新底部', () {
      // 发送前列表只有短开场消息：滚动范围≈0（min==max==0），贴底
      expect(
        ChatPage.shouldRestoreToNewBottomAfterUnfreeze(
          minScrollExtent: 0,
          maxScrollExtent: 0,
          extentAfter: 0,
        ),
        isTrue,
      );
    });

    test('旧快照不可滚动 + 不在底部 → 恢复旧像素（不跳新底部）', () {
      expect(
        ChatPage.shouldRestoreToNewBottomAfterUnfreeze(
          minScrollExtent: 0,
          maxScrollExtent: 0,
          extentAfter: 200,
        ),
        isFalse,
      );
    });

    test('旧快照可滚动 + 在底部 → 恢复旧像素（第二/三轮行为不变）', () {
      // 已有可滚动历史（max>min），即使贴底也恢复旧 pixels——
      // 不能把"接近底部但有意停住"的用户当作跟底用户
      expect(
        ChatPage.shouldRestoreToNewBottomAfterUnfreeze(
          minScrollExtent: 0,
          maxScrollExtent: 800,
          extentAfter: 0,
        ),
        isFalse,
      );
    });

    test('旧快照可滚动 + 在中部 → 恢复旧像素', () {
      expect(
        ChatPage.shouldRestoreToNewBottomAfterUnfreeze(
          minScrollExtent: 0,
          maxScrollExtent: 800,
          extentAfter: 300,
        ),
        isFalse,
      );
    });

    test('浮点误差容忍（±0.5 内视为不可滚动）', () {
      expect(
        ChatPage.shouldRestoreToNewBottomAfterUnfreeze(
          minScrollExtent: 0,
          maxScrollExtent: 0.3,
          extentAfter: 0,
        ),
        isTrue,
      );
      // 明显可滚动（0.5 以上）不归入 underfilled
      expect(
        ChatPage.shouldRestoreToNewBottomAfterUnfreeze(
          minScrollExtent: 0,
          maxScrollExtent: 2.0,
          extentAfter: 0,
        ),
        isFalse,
      );
    });
  });

  group('短列表解冻后跳新底部（widget 场景验证）', () {
    testWidgets('不可滚动短列表变长后 jumpTo(maxScrollExtent) 落在新底部', (
      tester,
    ) async {
      const viewportHeight = 600.0;
      final controller = ScrollController();

      // 解冻前：短开场消息（内容不足一屏，不可滚动）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: const [
                SizedBox(height: 200, child: Center(child: Text('开场'))),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.position.maxScrollExtent, 0); // 不可滚动
      expect(
        ChatPage.shouldRestoreToNewBottomAfterUnfreeze(
          minScrollExtent: controller.position.minScrollExtent,
          maxScrollExtent: controller.position.maxScrollExtent,
          extentAfter: controller.position.extentAfter,
        ),
        isTrue,
      );

      // 解冻后：开场 + 用户消息 + AI 输出（内容超一屏）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                const SizedBox(
                  height: 200,
                  child: Center(child: Text('开场')),
                ),
                const SizedBox(
                  height: 200,
                  child: Center(child: Text('用户消息')),
                ),
                SizedBox(
                  height: viewportHeight + 400, // AI 输出很长
                  child: const Center(child: Text('AI输出')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.position.maxScrollExtent, greaterThan(0));

      // 执行 v84 底部纠正：跳新底部
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      // 视口应落在新底部（AI 输出消息可见）
      final aiRect = tester.getRect(find.text('AI输出'));
      expect(aiRect.bottom, greaterThan(0));
      expect(aiRect.top, lessThan(viewportHeight));
      // 视口像素 == 新底部（不再钉在顶部）
      expect(
        controller.position.pixels,
        closeTo(controller.position.maxScrollExtent, 0.5),
      );
      // 懒加载：顶部"开场"已在视口外不构建（区别于钉在顶部时的可见）
      expect(find.text('开场'), findsNothing);
    });
  });
}
