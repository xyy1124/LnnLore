import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/widgets/chat_markdown_body.dart';

void main() {
  group('normalizeSimpleHtmlBlocks（角色状态栏 HTML 支持）', () {
    test('列表 ul/li 转 markdown 列表', () {
      final out = normalizeSimpleHtmlBlocks(
        '<ul><li>HP: 100</li><li>MP: 50</li></ul>',
      );
      expect(out, contains('- HP: 100'));
      expect(out, contains('- MP: 50'));
      expect(out.contains('<li>'), isFalse);
    });

    test('table 降级为 | 分隔纯文本', () {
      final out = normalizeSimpleHtmlBlocks(
        '<table><tr><td>HP</td><td>100</td></tr></table>',
      );
      expect(out, contains('HP | 100'));
      expect(out.contains('<td>'), isFalse);
    });

    test('span/font/center 剥标签保留内容', () {
      final out = normalizeSimpleHtmlBlocks(
        '<span style="color:red">受伤</span><font color="#ff0000">严重</font><center>居中内容</center>',
      );
      expect(out, contains('受伤'));
      expect(out, contains('严重'));
      expect(out, contains('居中内容'));
      expect(out.contains('<span'), isFalse);
      expect(out.contains('<font'), isFalse);
      expect(out.contains('<center'), isFalse);
    });

    test('br/p/div 换行与 hr 分隔线保持', () {
      final out = normalizeSimpleHtmlBlocks(
        '<div>第一行<br>第二行</div><hr><p>第三段</p>',
      );
      expect(out, contains('第一行\n第二行'));
      expect(out, contains('---'));
      expect(out, contains('第三段'));
      expect(out.contains('<div>'), isFalse);
      expect(out.contains('<p>'), isFalse);
    });

    test('无 HTML 时原样返回', () {
      expect(normalizeSimpleHtmlBlocks('纯文本 **粗体** 正常'), '纯文本 **粗体** 正常');
    });

    test('代码块内的 HTML 保持字面量（不被归一化改写）', () {
      final out = normalizeSimpleHtmlBlocks(
        '示例：\n```\n<li>raw</li>\n<br>\n```\n行内 `<li>x</li>` 也保留',
      );
      expect(out, contains('<li>raw</li>'));
      expect(out, contains('<br>'));
      expect(out, contains('<li>x</li>'));
      // 代码块外的 li 仍被转换
      final out2 = normalizeSimpleHtmlBlocks('<ul><li>真实列表</li></ul>');
      expect(out2, contains('- 真实列表'));
    });
  });
}
