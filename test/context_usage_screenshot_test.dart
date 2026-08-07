// 特别版：上下文用量页面截图生成（非断言测试）。
//
// 运行：flutter test --update-goldens test/context_usage_screenshot_test.dart
// 产物：test/goldens/context_usage_page.png（可用图片查看器打开预览）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/data/app_settings.dart';
import 'package:pocket_inn/models/prompt_assembly.dart';
import 'package:pocket_inn/models/world_book.dart';
import 'package:pocket_inn/pages/chat/context_usage_page.dart';
import 'package:pocket_inn/pages/chat/widgets/chat_input_area.dart';

void main() {
  setUpAll(() async {
    // 无操作；字体检查在测试体内执行（setUpAll 中 markTestSkipped 不会跳过测试）
  });

  testWidgets('上下文用量页面截图', (tester) async {
    // 加载系统黑体，让中文正常显示（golden 默认 Ahem 字体会把中文画成方块）。
    // 若系统无 SimHei（如 CI/Linux 等非 Windows 环境），标记跳过——避免
    // Ahem 方块与 SimHei golden 不匹配。本测试仅用于本地生成界面预览截图。
    final fontFile = File(r'C:\Windows\Fonts\simhei.ttf');
    if (!fontFile.existsSync()) {
      markTestSkipped('系统黑体 simhei.ttf 不可用，跳过截图对比');
      return;
    }
    // testWidgets 默认在 FakeAsync zone 中，真实文件 IO 需 runAsync
    await tester.runAsync(() async {
      final loader = FontLoader('SimHei')
        ..addFont(fontFile.readAsBytes().then(ByteData.sublistView));
      await loader.load();
    });
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0; // 360x733 逻辑尺寸
    addTearDown(tester.view.reset);

    final assembly = PromptAssemblyResult(
      messages: [
        PromptMessage(
          role: 'system',
          content: '预设 main 的内容：角色扮演核心设定与风格要求，请严格按照设定进行扮演。',
          sources: const ['预设: main'],
          sourceChars: const [36],
        ),
        PromptMessage(
          role: 'system',
          content: '角色卡 description：一位神秘的贵族小姐。\n角色卡 personality：优雅傲娇。',
          sources: const ['预设: main', '角色卡: description', '角色卡: personality'],
          sourceChars: const [20, 20, 10],
        ),
        PromptMessage(
          role: 'system',
          content: '世界书：before 条目内容',
          sources: const ['世界书: before'],
          sourceChars: const [12],
        ),
        PromptMessage(
          role: 'system',
          content: '开场提示：夜已经很深了。',
          sources: const ['虚拟聊天记录'],
          sourceChars: const [11],
        ),
        PromptMessage(
          role: 'user',
          content: '我轻轻地推开门，看到你坐在窗边。',
          sources: const ['虚拟聊天记录'],
          sourceChars: const [19],
        ),
        PromptMessage(
          role: 'assistant',
          content: '你来了。我等你很久了，过来坐吧。',
          sources: const ['虚拟聊天记录'],
          sourceChars: const [21],
        ),
      ],
      mergedText: '',
      activatedWorldBookEntries: [
        ActivatedWorldBookEntry(
          bookId: 'b1',
          bookName: '世界观设定',
          entry: WorldBookEntry(
            id: 'e1',
            content: '王国与魔法的基础设定，帝国与联邦的对峙格局。',
            comment: '',
          ),
          triggeredByConstant: true,
        ),
        ActivatedWorldBookEntry(
          bookId: 'b1',
          bookName: '世界观设定',
          entry: WorldBookEntry(
            id: 'e2',
            content: '贵族社会等级与礼仪规范。',
            comment: '',
          ),
          triggeredByConstant: false,
        ),
        ActivatedWorldBookEntry(
          bookId: 'b2',
          bookName: '人物关系表',
          entry: WorldBookEntry(
            id: 'e3',
            content: '主角与各角色的关系与恩怨。',
            comment: '',
          ),
          triggeredByConstant: false,
        ),
      ],
      segments: const [],
      unusedCharacterOverrides: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'SimHei',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF1C1B1F),
        ),
        home: const ContextUsagePage(
          assembly: null, // 占位，下方重新 pump
          contextWindow: 128000,
          modelName: 'deepseek-chat',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'SimHei',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF1C1B1F),
        ),
        home: ContextUsagePage(
          assembly: assembly,
          contextWindow: 128000,
          modelName: 'deepseek-chat',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(ContextUsagePage),
      matchesGoldenFile('goldens/context_usage_page.png'),
    );

    // 第二张：聊天输入框右上侧的用量入口条
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'SimHei',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF1C1B1F),
        ),
        home: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputArea(
                textController: TextEditingController(text: ''),
                focusNode: FocusNode(),
                inputTapRegionGroupId: Object(),
                sessionKey: null,
                isSendEnabled: false,
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
                contextUsedTokens: 10240,
                contextMaxTokens: 1000000,
                onOpenContextUsage: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(ChatInputArea),
      matchesGoldenFile('goldens/context_usage_entry_bar.png'),
    );
  });
}
