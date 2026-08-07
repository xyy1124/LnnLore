import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/pages/chat/widgets/quick_command_marks.dart';
import 'package:pocket_inn/pages/chat/widgets/quick_command_text_editing_controller.dart';

/// v53：占位标记一键删除回归——Backspace/Delete 删到标记任意字符时
/// 整体移除标记，不再逐字符删出半截标记（用户反馈"删一下变奇怪、
/// 还要删好多下"）。
void main() {
  group('QuickCommandTextEditingController 标记删除', () {
    test('光标在标记后按 Backspace → 一次性删除整个标记', () {
      final controller = QuickCommandTextEditingController(
        text: '开头${wrapQuickCommandMark('时间流逝')}结尾',
      );
      // 光标移到"结尾"前（标记后）
      final markEnd = '开头${wrapQuickCommandMark('时间流逝')}'.length;
      controller.selection = TextSelection.collapsed(offset: markEnd);
      // 模拟 Backspace：删除标记末尾的 \uE001
      controller.value = controller.value.copyWith(
        text: controller.text.substring(0, markEnd - 1) +
            controller.text.substring(markEnd),
        selection: TextSelection.collapsed(offset: markEnd - 1),
      );
      // 整个标记（含私有区字符）被移除，只剩"开头结尾"
      expect(controller.text, '开头结尾');
      expect(controller.selection.baseOffset, '开头'.length);
    });

    test('光标在标记前按 Delete → 一次性删除整个标记', () {
      final controller = QuickCommandTextEditingController(
        text: '开头${wrapQuickCommandMark('时间流逝')}结尾',
      );
      final markStart = '开头'.length;
      controller.selection = TextSelection.collapsed(offset: markStart);
      // 模拟 Delete：删除标记起始的 \uE000
      controller.value = controller.value.copyWith(
        text: controller.text.substring(0, markStart) +
            controller.text.substring(markStart + 1),
        selection: TextSelection.collapsed(offset: markStart),
      );
      expect(controller.text, '开头结尾');
      expect(controller.selection.baseOffset, markStart);
    });

    test('光标在标记中间删除 → 一次性删除整个标记', () {
      final controller = QuickCommandTextEditingController(
        text: wrapQuickCommandMark('详细描写') + '正文',
      );
      // 光标移到标记中间（"详|细描写"处）
      final mid = 1; // \uE000 之后
      controller.selection = TextSelection.collapsed(offset: mid);
      controller.value = controller.value.copyWith(
        text: controller.text.substring(0, mid - 1) +
            controller.text.substring(mid),
        selection: TextSelection.collapsed(offset: mid - 1),
      );
      expect(controller.text, '正文');
      expect(controller.selection.baseOffset, 0);
    });

    test('普通文本删除不受影响', () {
      final controller = QuickCommandTextEditingController(text: '普通文本');
      controller.selection = const TextSelection.collapsed(offset: 4);
      controller.value = controller.value.copyWith(
        text: '普通文',
        selection: const TextSelection.collapsed(offset: 3),
      );
      expect(controller.text, '普通文');
    });

    test('多标记文本：删除第二个标记不影响第一个', () {
      final controller = QuickCommandTextEditingController(
        text: '${wrapQuickCommandMark('时间流逝')}和'
            '${wrapQuickCommandMark('摄像机视角')}',
      );
      final first = wrapQuickCommandMark('时间流逝');
      final second = wrapQuickCommandMark('摄像机视角');
      // 光标移到整个文本末尾，Backspace 删第二个标记的 \uE001
      final cursor = (first + '和' + second).length;
      controller.selection = TextSelection.collapsed(offset: cursor);
      controller.value = controller.value.copyWith(
        text: controller.text.substring(0, cursor - 1),
        selection: TextSelection.collapsed(offset: cursor - 1),
      );
      expect(controller.text, '$first和');
      expect(hasQuickCommandMark(controller.text), isTrue);
    });

    test('选择删除（多字符）不拦截，保持默认行为', () {
      final controller = QuickCommandTextEditingController(
        text: '开头${wrapQuickCommandMark('时间流逝')}结尾',
      );
      final start = '开头'.length;
      final end = '开头${wrapQuickCommandMark('时间流逝')}'.length;
      // 模拟选择删除整个标记（长度差 > 1）
      controller.value = controller.value.copyWith(
        text: '开头结尾',
        selection: TextSelection.collapsed(offset: start),
      );
      expect(controller.text, '开头结尾');
    });
  });
}
