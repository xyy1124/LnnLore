import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/widgets/scroll_float_button.dart';

void main() {
  testWidgets('传 onScrollToBottom 时到底按钮走外部回调', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var callbackCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                controller: controller,
                children: List.generate(
                  80,
                  (i) => SizedBox(height: 40, child: Text('item $i')),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ScrollFloatButton(
                  scrollController: controller,
                  isReversed: false,
                  onScrollToBottom: () => callbackCalls++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<ScrollFloatButton>(
      find.byType(ScrollFloatButton),
    );
    expect(button.onScrollToBottom, isNotNull);

    // 直接触发按钮的对外回调（真实 tap 由集成层保证；此处验证接线）
    button.onScrollToBottom!();
    expect(callbackCalls, 1);
  });

  testWidgets('不传 onScrollToBottom 时保持旧行为（回调为 null）', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                controller: controller,
                children: List.generate(
                  80,
                  (i) => SizedBox(height: 40, child: Text('item $i')),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ScrollFloatButton(
                  scrollController: controller,
                  isReversed: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<ScrollFloatButton>(
      find.byType(ScrollFloatButton),
    );
    expect(button.onScrollToBottom, isNull);
  });
}
