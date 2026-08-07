import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/quick_command.dart';
import 'package:pocket_inn/pages/chat/widgets/quick_command_marks.dart';
import 'package:pocket_inn/pages/chat/widgets/quick_command_text_editing_controller.dart';

void main() {
  final commands = [
    QuickCommand(
      id: 'c1',
      name: '时间流逝',
      prompt: '时间流逝，请描写一夜之后的变化。',
      type: QuickCommandType.insert,
    ),
    QuickCommand(
      id: 'c2',
      name: '旁白',
      prompt: '请以旁白形式描写当前场景。',
      type: QuickCommandType.direct,
    ),
  ];

  group('quick_command_marks', () {
    test('wrap/restore 往返', () {
      final mark = wrapQuickCommandMark('时间流逝');
      expect(hasQuickCommandMark(mark), isTrue);
      expect(restoreQuickCommandMarks(mark), '【快捷指令：时间流逝】');
      expect(extractQuickCommandName(mark), '时间流逝');
    });

    test('无标记时原样返回', () {
      expect(restoreQuickCommandMarks('普通文本'), '普通文本');
      expect(hasQuickCommandMark('普通文本'), isFalse);
    });

    test('展开：占位替换为提示词', () {
      final text = '${wrapQuickCommandMark('时间流逝')} 他醒了';
      final expanded = expandQuickCommandMarks(text, commands);
      expect(expanded, '时间流逝，请描写一夜之后的变化。 他醒了');
    });

    test('展开：未匹配的标记保留为可读占位（指令已删除不丢内容）', () {
      final text = '${wrapQuickCommandMark('已删除指令')} 内容';
      final expanded = expandQuickCommandMarks(text, commands);
      expect(expanded, '【快捷指令：已删除指令】 内容');
    });

    test('展开：剥离未配对的私有区字符（用户删掉半个标记）', () {
      final text = '前缀\uE000残留\uE001中间\uE000没闭合 内容';
      final expanded = expandQuickCommandMarks(text, commands);
      expect(expanded.contains('\uE000'), isFalse);
      expect(expanded.contains('\uE001'), isFalse);
    });

    test('复制/预览还原：消息文本含占位时还原为可读形式', () {
      final text = '${wrapQuickCommandMark('时间流逝')}流逝了一夜';
      final copied = restoreQuickCommandMarks(text);
      expect(copied.contains('\uE000'), isFalse);
      expect(copied, '【快捷指令：时间流逝】流逝了一夜');
    });

    test('多标记消息：还原所有标记', () {
      final text =
          '${wrapQuickCommandMark('时间流逝')}然后${wrapQuickCommandMark('旁白')}收尾';
      final restored = restoreQuickCommandMarks(text);
      expect(restored, '【快捷指令：时间流逝】然后【快捷指令：旁白】收尾');
    });

    test('编辑还原：用户只改补充内容，提示词还原为占位（核心场景）', () {
      // 原消息：占位 + 补充；modelText = 提示词 + 补充
      final expanded = '时间流逝，请描写一夜之后的变化。补充2';
      final display = restorePromptsToMarks(expanded, commands, ['时间流逝']);
      expect(display, '${wrapQuickCommandMark('时间流逝')}补充2');
    });

    test('编辑还原：前缀优先 + 后续标记 replaceFirst（新旧标记混合）', () {
      final expanded = '时间流逝，请描写一夜之后的变化。然后请以旁白形式描写当前场景。收尾';
      final display = restorePromptsToMarks(
        expanded,
        commands,
        ['时间流逝', '旁白'],
      );
      expect(
        display,
        '${wrapQuickCommandMark('时间流逝')}然后${wrapQuickCommandMark('旁白')}收尾',
      );
    });

    test('编辑还原：用户改写提示词后不再匹配，原样保留', () {
      final expanded = '完全改写的提示词 补充';
      final display = restorePromptsToMarks(expanded, commands, ['时间流逝']);
      expect(display, expanded);
    });

    test('split 切分标记段与普通段', () {
      final text = '前缀${wrapQuickCommandMark('旁白')}后缀';
      final segments = splitQuickCommandMarks(text);
      expect(segments, [
        (false, '前缀'),
        (true, '旁白'),
        (false, '后缀'),
      ]);
    });

    test('还原消息文本（消息界面显示）', () {
      final text = '${wrapQuickCommandMark('时间流逝')}流逝了一夜';
      expect(restoreQuickCommandMarks(text), '【快捷指令：时间流逝】流逝了一夜');
    });
  });

  group('QuickCommandTextEditingController', () {
    Future<BuildContext> pumpContext(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox()),
      );
      return tester.element(find.byType(MaterialApp));
    }

    testWidgets('占位标记渲染为斜体彩色 span', (tester) async {
      final controller =
          QuickCommandTextEditingController(text: wrapQuickCommandMark('旁白'));
      addTearDown(controller.dispose);
      final context = await pumpContext(tester);

      final span = controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 16),
        withComposing: false,
      ) as TextSpan;

      expect(span.children, isNotNull);
      final markSpan = span.children!.first as TextSpan;
      expect(markSpan.text, '【旁白】');
      expect(markSpan.style?.fontStyle, FontStyle.italic);
      expect(markSpan.style?.color, isNotNull);
    });

    testWidgets('普通文本无标记时不拆 span', (tester) async {
      final controller = QuickCommandTextEditingController(text: '普通文本');
      addTearDown(controller.dispose);
      final context = await pumpContext(tester);

      final span = controller.buildTextSpan(
        context: context,
        style: const TextStyle(fontSize: 16),
        withComposing: false,
      ) as TextSpan;

      expect(span.children, hasLength(1));
      expect((span.children!.first as TextSpan).text, '普通文本');
    });
  });
}
