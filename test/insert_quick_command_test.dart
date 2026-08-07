import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/pages/chat/widgets/chat_input_area.dart';

void main() {
  group('insertTextAtCursor（插入型快捷指令）', () {
    test('光标在末尾：提示词追加到末尾', () {
      final (text, cursor) = insertTextAtCursor('我在写', '地点：', 3, 3);
      expect(text, '我在写地点：');
      expect(cursor, 6);
    });

    test('光标在中间：插入并自动补空格，不粘连', () {
      final (text, cursor) = insertTextAtCursor('你好世界', '，', 2, 2);
      expect(text, '你好， 世界');
      expect(cursor, 4);
    });

    test('连续插入（可多次）：第二次插到第一次之后', () {
      final first = insertTextAtCursor('', '【天气】', 0, 0);
      final second = insertTextAtCursor(first.$1, '【地点】', first.$2, first.$2);
      expect(second.$1, '【天气】【地点】');
      expect(second.$2, 8);
    });

    test('有选中文本：覆盖选区', () {
      final (text, cursor) = insertTextAtCursor('1234567890', 'XX', 3, 7);
      expect(text, '123XX890');
      expect(cursor, 5);
    });

    test('边界：start/end 越界时 clamp 到安全范围', () {
      final (text, cursor) = insertTextAtCursor('abc', '!', -5, 99);
      expect(text, '!');
      expect(cursor, 1);
    });

    test('空输入框：直接插入', () {
      final (text, cursor) = insertTextAtCursor('', '旁白：', 0, 0);
      expect(text, '旁白：');
      expect(cursor, 3);
    });
  });
}
