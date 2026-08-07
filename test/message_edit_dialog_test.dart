import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/pages/chat/widgets/message_edit_dialog.dart';

void main() {
  Widget buildHost({required Size size, bool canSaveAndSend = true}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MessageEditDialog(
                  initialText: '测试内容',
                  title: '编辑消息',
                  canSaveAndSend: canSaveAndSend,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('v51: 窄屏（320px）下"发送"按钮始终可见（两层布局）', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildHost(size: const Size(320, 640)));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 三层按钮都可见（旧版横向滚动会把"保存并发送"藏到屏幕外）
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
    // 发送按钮在视口内（未被横向滚动推出）
    final sendRect = tester.getRect(find.text('发送'));
    expect(sendRect.right, lessThanOrEqualTo(320));
  });

  testWidgets('v51: canSaveAndSend=false 时不显示"发送"按钮', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildHost(size: const Size(320, 640), canSaveAndSend: false),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('发送'), findsNothing);
  });
}
