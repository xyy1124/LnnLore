import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/data/app_settings.dart';
import 'package:pocket_inn/data/mock_user_settings.dart';
import 'package:pocket_inn/models/quick_command.dart';
import 'package:pocket_inn/models/user_setting.dart';
import 'package:pocket_inn/models/world_book.dart';
import 'package:pocket_inn/pages/chat/widgets/chat_input_area.dart';

void main() {
  Future<void> pumpArea(
    WidgetTester tester,
    List<QuickCommand> commands,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputArea(
            textController: controller,
            focusNode: focusNode,
            inputTapRegionGroupId: Object(),
            sessionKey: null,
            isSendEnabled: true,
            isSending: false,
            hasBackground: false,
            settings: const AppSettings(),
            worldBooks: const [],
            selectedWorldBookIds: const {},
            currentUserSetting: null,
            onUserSettingsPressed: (_) {},
            onWorldBookPressed: (_) {},
            onPresetPressed: (_) {},
            onSendPressed: () {},
            onStopGeneratingPressed: () {},
            quickCommands: commands,
          ),
        ),
      ),
    );
  }

  QuickCommand cmd(String id, String name, String prompt, QuickCommandType t) =>
      QuickCommand(id: id, name: name, prompt: prompt, type: t);

  testWidgets('快捷指令面板：分类页签 + 当前分类指令 + 提示词预览', (tester) async {
    await pumpArea(tester, [
      cmd('d1', '继续', '请继续你的表演', QuickCommandType.direct),
      cmd('p1', '时间流逝', '描述时间流逝', QuickCommandType.prompt),
      cmd('i1', '插入地点', '地点：', QuickCommandType.insert),
    ]);

    // 点击"快捷指令"入口打开面板（不再是 + 图标）
    await tester.tap(find.text('快捷指令'));
    await tester.pumpAndSettle();

    // 默认 direct 页签：只显示直接发送的指令
    expect(find.text('继续'), findsOneWidget);
    expect(find.text('时间流逝'), findsNothing);
    expect(find.text('插入地点'), findsNothing);
    // 三分类页签都在
    expect(find.text('直接发送'), findsOneWidget);
    expect(find.text('询问后发送'), findsOneWidget);
    expect(find.text('插入输入框'), findsOneWidget);
  });

  testWidgets('快捷指令面板：切换页签显示对应分类', (tester) async {
    await pumpArea(tester, [
      cmd('d1', '继续', '请继续你的表演', QuickCommandType.direct),
      cmd('i1', '插入地点', '地点：', QuickCommandType.insert),
    ]);

    await tester.tap(find.text('快捷指令'));
    await tester.pumpAndSettle();

    // 切到"插入输入框"页签
    await tester.tap(find.text('插入输入框'));
    await tester.pumpAndSettle();
    expect(find.text('插入地点'), findsOneWidget);
    expect(find.text('继续'), findsNothing);
  });

  testWidgets('快捷指令面板：空分类显示"暂无指令"空态', (tester) async {
    await pumpArea(tester, [
      cmd('d1', '继续', '请继续你的表演', QuickCommandType.direct),
    ]);

    await tester.tap(find.text('快捷指令'));
    await tester.pumpAndSettle();

    // direct 页签有指令；切到询问页签为空态
    await tester.tap(find.text('询问后发送'));
    await tester.pumpAndSettle();
    expect(find.text('暂无指令'), findsOneWidget);
  });

  testWidgets('无快捷指令时入口隐藏', (tester) async {
    await pumpArea(tester, const []);

    expect(find.text('快捷指令'), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
  });

  testWidgets('发送中：内嵌发送键变为停止（图标切换）', (tester) async {    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputArea(
            textController: controller,
            focusNode: focusNode,
            inputTapRegionGroupId: Object(),
            sessionKey: null,
            isSendEnabled: true,
            isSending: true,
            hasBackground: false,
            settings: const AppSettings(),
            worldBooks: const [],
            selectedWorldBookIds: const {},
            currentUserSetting: null,
            onUserSettingsPressed: (_) {},
            onWorldBookPressed: (_) {},
            onPresetPressed: (_) {},
            onSendPressed: () {},
            onStopGeneratingPressed: () {},
            quickCommands: const [],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });

  testWidgets('工具行：超长世界书名不溢出输入栏边界', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputArea(
            textController: controller,
            focusNode: focusNode,
            inputTapRegionGroupId: Object(),
            sessionKey: null,
            isSendEnabled: true,
            isSending: false,
            hasBackground: false,
            settings: const AppSettings(),
            // 超长世界书名字（触发省略号路径）
            worldBooks: [
              WorldBook(
                id: 'w1',
                name: '这是一个非常非常非常非常非常非常非常非常非常非常长的世界书名字用来测试省略',
                description: '',
                colorValue: 0xFF4B6CB7,
                updatedAt: DateTime.now(),
              ),
            ],
            selectedWorldBookIds: const {'w1'},
            currentUserSetting: null,
            onUserSettingsPressed: (_) {},
            onWorldBookPressed: (_) {},
            onPresetPressed: (_) {},
            onSendPressed: () {},
            onStopGeneratingPressed: () {},
            quickCommands: const [],
          ),
        ),
      ),
    );
    // 无异常（无 RenderFlex overflow 报错）即通过
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具行：超长用户设定名（限字截断）不溢出', (tester) async {
    final original = userSettingsNotifier.value;
    final longSetting = UserSetting(
      id: 'u1',
      name: '超长用户设定名字超长用户设定名字超长用户设定名字超长',
      prompt: '',
      colorValue: 0xFF5C6BC0,
    );
    userSettingsNotifier.value = [longSetting];
    addTearDown(() => userSettingsNotifier.value = original);

    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputArea(
            textController: controller,
            focusNode: focusNode,
            inputTapRegionGroupId: Object(),
            sessionKey: null,
            isSendEnabled: true,
            isSending: false,
            hasBackground: false,
            settings: const AppSettings(),
            worldBooks: const [],
            selectedWorldBookIds: const {},
            currentUserSetting: longSetting,
            onUserSettingsPressed: (_) {},
            onWorldBookPressed: (_) {},
            onPresetPressed: (_) {},
            onSendPressed: () {},
            onStopGeneratingPressed: () {},
            quickCommands: const [],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
