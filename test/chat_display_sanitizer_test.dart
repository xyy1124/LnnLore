import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/chat_display_sanitizer.dart';

void main() {
  group('ChatDisplaySanitizer.stripNonDialogue', () {
    test('剥离 details 包裹的 HTML 状态面板（卡模板格式）', () {
      const text =
          '*她抬眸看向你*「你终于来了。」\n'
          '<details>\n'
          '<div style="padding:8px;background:#1a1a2e;border:1px solid #9b59b6;">\n'
          '<b>❤️ 夜无央·烙印值追踪</b>\n'
          '<hr>\n'
          '<span>烙印值：<b>【35/100】</b></span><br>\n'
          '<span>阶段：<b>身体依赖</b></span>\n'
          '</div>\n'
          '</details>';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '*她抬眸看向你*「你终于来了。」');
    });

    test('剥离无 details 包裹的内联 background div', () {
      const text =
          '正文内容。\n'
          '<div style="padding:8px;background:#1a1a2e;color:#e0c0ff;">\n'
          '状态：HP 42/100\n'
          '</div>';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '正文内容。');
    });

    test('剥离 status/status_bar/tracker 标签块', () {
      const text = '正文。<status>HP 42</status>尾巴';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '正文。尾巴');
    });

    test('剥离含状态特征的 html/xml 代码块', () {
      const text =
          '正文结束。\n'
          '```html\n'
          '<div class="status-bar">状态栏内容</div>\n'
          '```';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '正文结束。');
    });

    test('普通代码块（无状态特征）保留', () {
      const text =
          '看这段代码：\n'
          '```dart\n'
          'final x = 1;\n'
          '```\n'
          '就这样。';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, text.trim());
    });

    test('setvar + STATE 协议块一起剥离', () {
      const text =
          '「味道不错。」\n'
          '{{setvar::hp::42}}\n'
          '<STATE>\n'
          'hp=42\n'
          '</STATE>';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '「味道不错。」');
    });

    test('JSON patch 协议块剥离', () {
      const text =
          '「我们走吧。」\n'
          '{"patch": {"set": {"location": "森林"}}}';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '「我们走吧。」');
    });

    test('纯状态面板（无正文）剥离后为空', () {
      const text =
          '<details><div style="background:#1a1a2e;">❤️ 状态追踪</div></details>';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '');
    });

    test('空输入返回空', () {
      expect(ChatDisplaySanitizer.stripNonDialogue(''), '');
    });

    test('前后空白 trim', () {
      const text = '  正文内容。  \n  ';
      expect(ChatDisplaySanitizer.stripNonDialogue(text), '正文内容。');
    });

    test('正文中含 状态栏 普通文字不误删', () {
      const text = '「你看那边的状态栏，上面写了什么？」';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, text);
    });

    test('嵌套 details 循环剥离', () {
      const text =
          '正文。\n'
          '<details>\n'
          '<div style="background:#1a1a2e;">\n'
          '<details>\n'
          '<div style="background:#222;">内层</div>\n'
          '</details>\n'
          '</div>\n'
          '</details>';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '正文。');
    });

    test('{{match}} 包住的正文保留，{{comment}}/<!--panel--> 剥离', () {
      const text =
          '「今天轮到你了。」\n'
          '{{match}}触发词{{/match}}\n'
          '{{comment}}备注{{/comment}}\n'
          '<!--panel-->\n'
          '<!-- 状态栏注释 -->';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      // match 内正文保留（token 剥掉），comment/注释删除
      expect(result, '「今天轮到你了。」\n触发词');
    });

    test('正文里的普通 {{xxx}} 不误删（非 match/comment///）', () {
      const text = '他说道："{{晚安}}"。';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, text);
    });
  });

  group('ChatDisplaySanitizer.extract 特殊状态栏提取', () {
    test('extract 也剥离 ST 模板残留', () {
      const text =
          '「来啊。」\n'
          '{{match}}前戏{{/match}}\n'
          '<!--panel-->\n'
          '<details><div style="background:#1a1a2e;">❤️ 状态</div></details>';
      final result = ChatDisplaySanitizer.extract(text);
      // match 内正文保留；状态面板提取
      expect(result.displayText, '「来啊。」\n前戏');
      expect(result.specialStatusHtml, isNotNull);
      expect(result.specialStatusHtml, contains('background:#1a1a2e'));
    });

    test('提取 {{match}}+<!--panel-->...<!--/panel--> comment panel 块', () {
      const text =
          '「今天轮到你了。」\n'
          '{{match}}\n'
          '<!--panel-->\n'
          '<div style="background:#1a1a2e;color:#e0c0ff;">\n'
          '<b>❤️ 芭蕾三姐妹·今日侍奉</b><br>\n'
          '<span>侍奉状态：<b>轮流</b></span>\n'
          '</div>\n'
          '<!--/panel-->\n'
          '{{/match}}';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '「今天轮到你了。」');
      expect(result.specialStatusHtml, isNotNull);
      expect(result.specialStatusHtml, contains('background:#1a1a2e'));
      expect(result.specialStatusHtml, contains('侍奉状态'));
    });

    test('comment panel 纯文本正文包成 status-panel div（转义+br）', () {
      const text =
          '正文。\n'
          '<!--panel-->\n'
          '时间：夜晚\n'
          '地点：宿舍\n'
          '<!--/panel-->';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '正文。');
      expect(result.specialStatusHtml, isNotNull);
      expect(result.specialStatusHtml, contains('<div class="status-panel">'));
      expect(result.specialStatusHtml, contains('时间：夜晚'));
    });

    test('孤立 {{match}}/{{/match}}/{{comment}} 剥离', () {
      const text = '正文。{{match}}{{/match}}{{comment}}';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '正文。');
    });

    test('{{match}}...{{/match}} 包住的正文保留（不整块删除）', () {
      const text =
          '{{match}}\n'
          '*月光透过破窗洒进简陋的木屋，空气中弥漫着淡淡的冰莲清香与血腥气。*\n'
          '{{/match}}';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '*月光透过破窗洒进简陋的木屋，空气中弥漫着淡淡的冰莲清香与血腥气。*');
    });

    test('{{comment}}...{{/comment}} 内容删除', () {
      const text = '正文。{{comment}}这是注释内容不该显示{{/comment}}尾巴';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, '正文。尾巴');
    });

    test('普通带 border 样式的正文 div 不误删（仅 border 不作数）', () {
      const text =
          '她说：\n'
          '<div style="border:1px solid #ccc;">引用框内容</div>\n'
          '说完走了。';
      final result = ChatDisplaySanitizer.stripNonDialogue(text);
      expect(result, text.trim());
    });

    test('background 样式 div 仍提取为状态面板', () {
      const text =
          '正文。\n'
          '<div style="background:#1a1a2e;">❤️ 烙印值 35/100</div>';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '正文。');
      expect(result.specialStatusHtml, isNotNull);
      expect(result.specialStatusHtml, contains('background:#1a1a2e'));
    });

    test('extractOpeningMessages 过滤空白与重复', () {
      const raw = ['', '   ', '第一条', '第一条', '第二条'];
      final result = ChatDisplaySanitizer.extractOpeningMessages(raw);
      expect(result.messages, ['第一条', '第二条']);
    });

    test('stripStoredMessageForDisplay 保留正文 div/details（轻量不提取）', () {
      const text =
          '她说：\n'
          '<div style="border:1px solid #ccc;">引用框内容</div>\n'
          '<details><summary>折叠</summary>内容</details>\n'
          '说完走了。';
      final result =
          ChatDisplaySanitizer.stripStoredMessageForDisplay(text);
      expect(result, contains('引用框内容'));
      expect(result, contains('说完走了。'));
    });

    test('stripStoredMessageForDisplay 剥 panel comment/协议块/孤立 token', () {
      const text =
          '「来了。」\n'
          '{{match}}{{/match}}\n'
          '<!--panel-->状态面板<!--/panel-->\n'
          '{{setvar::hp::42}}\n'
          '<STATE>hp=42</STATE>';
      final result =
          ChatDisplaySanitizer.stripStoredMessageForDisplay(text);
      expect(result, contains('「来了。」'));
      expect(result, isNot(contains('{{setvar')));
      expect(result, isNot(contains('<STATE>')));
      expect(result, isNot(contains('<!--panel-->')));
    });

    test('stripStoredMessageForDisplay 非空消息不清洗成空（兜底）', () {
      // 模拟已入库正文（extract 可能误判为空的面板类文本），
      // 轻量清洗必须保留可见内容
      const text =
          '<div style="padding:8px;border:1px solid #ccc;">'
          '阶段：身体依赖。她低声说着台词。'
          '</div>';
      final result =
          ChatDisplaySanitizer.stripStoredMessageForDisplay(text);
      expect(result.trim(), isNotEmpty);
      expect(result, contains('她低声说着台词'));
    });

    test('纯系统文本（只有 setvar/STATE）清洗后为空，不兜底成正文', () {
      const text = '{{setvar::hp::42}}\n<STATE>hp=42</STATE>';
      final result =
          ChatDisplaySanitizer.stripStoredMessageForDisplay(text);
      expect(result, isEmpty);
    });

    test('纯面板开场（{{match}}+panel 包裹）不兜底进正文列表', () {
      const raw = [
        '{{match}}\n<!--panel-->\n<div style="background:#222;">面板二</div>\n<!--/panel-->\n{{/match}}',
      ];
      final result = ChatDisplaySanitizer.extractOpeningMessages(raw);
      expect(result.messages, isEmpty);
      expect(result.specialStatusHtml, isNotNull);
      expect(result.specialStatusHtml, contains('面板二'));
    });

    test('recoverDisplayTextAfterExtraction：正文+面板混合时恢复正文', () {
      const text =
          '「你终于来了。」她抬眸说道。\n'
          '<div style="background:#1a1a2e;">❤️ 烙印值 35/100</div>';
      const panel = '<div style="background:#1a1a2e;">❤️ 烙印值 35/100</div>';
      final recovered = ChatDisplaySanitizer.recoverDisplayTextAfterExtraction(
        text,
        specialStatusHtml: panel,
      );
      expect(recovered, contains('「你终于来了。」她抬眸说道。'));
      expect(recovered, isNot(contains('烙印值')));
    });

    test('isPurePanelText 新版本：HTML 实体/围栏归一化后判定', () {
      // 纯面板（带 ```html 围栏 + 实体）
      const pure =
          '```html\n<div style="background:#1a1a2e;">❤️ 烙印值&nbsp;35/100</div>\n```';
      const panel = '<div style="background:#1a1a2e;">❤️ 烙印值 35/100</div>';
      expect(
        ChatDisplaySanitizer.isPurePanelText(pure, panel),
        isTrue,
      );
      // 面板+正文 → 非纯面板
      const mixed =
          '正文内容。\n<div style="background:#1a1a2e;">❤️ 烙印值 35/100</div>';
      expect(
        ChatDisplaySanitizer.isPurePanelText(mixed, panel),
        isFalse,
      );
    });

    test('stripStoredMessageForDisplay 纯 comment 块不清洗成正文', () {
      const text = '{{comment}}这是注释{{/comment}}';
      final result =
          ChatDisplaySanitizer.stripStoredMessageForDisplay(text);
      expect(result, isEmpty);
    });
    test('提取 details 状态面板：正文 + specialStatusHtml 分离', () {
      const text =
          '*她抬眸*「你终于来了。」\n'
          '<details>\n'
          '<div style="padding:8px;background:#1a1a2e;border:1px solid #9b59b6;color:#e0c0ff;">\n'
          '<b>❤️ 夜无央·烙印值追踪</b>\n'
          '<hr>\n'
          '<span>烙印值：<b>【35/100】</b></span>\n'
          '</div>\n'
          '</details>';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '*她抬眸*「你终于来了。」');
      expect(result.specialStatusHtml, isNotNull);
      expect(result.specialStatusHtml, contains('background:#1a1a2e'));
      expect(result.specialStatusHtml, contains('烙印值'));
    });

    test('提取裸 background div（无 details 包裹）', () {
      const text =
          '正文。\n'
          '<div style="background:#1a1a2e;color:#e0c0ff;">\n'
          '状态：HP 42/100\n'
          '</div>';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '正文。');
      expect(result.specialStatusHtml, contains('HP 42/100'));
    });

    test('无状态面板时 specialStatusHtml 为 null', () {
      const text = '纯正文内容「你好」。';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, text);
      expect(result.specialStatusHtml, isNull);
    });

    test('纯状态面板：displayText 为空、html 有值', () {
      const text =
          '<details><div style="background:#1a1a2e;">❤️ 状态追踪</div></details>';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '');
      expect(result.specialStatusHtml, isNotNull);
    });

    test('多个面板取最后一个（最新状态）', () {
      const text =
          '正文。\n'
          '<div style="background:#111;">面板A</div>\n'
          '继续。\n'
          '<div style="background:#222;">面板B</div>';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '正文。\n\n继续。');
      expect(result.specialStatusHtml, contains('面板B'));
      expect(result.specialStatusHtml, isNot(contains('面板A')));
    });

    test('reply 含面板也能提取（同一条路径）', () {
      const text =
          '「我们走吧。」\n'
          '<div style="background:#333;color:#fff;">地点：森林</div>\n'
          '{"patch": {"set": {"location": "森林"}}}';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '「我们走吧。」');
      expect(result.specialStatusHtml, contains('森林'));
    });

    test('```html 代码块状态栏也能提取', () {
      const text =
          '正文结束。\n'
          '```html\n'
          '<div class="status-bar">状态栏内容</div>\n'
          '```';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '正文结束。');
      expect(result.specialStatusHtml, contains('status-bar'));
    });

    test('单引号 style 的 div 也能提取', () {
      const text =
          '正文。\n'
          "<div style='background:#1a1a2e;'>状态：HP 42/100</div>";
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '正文。');
      expect(result.specialStatusHtml, contains('HP 42/100'));
    });

    test('class 含 status/tracker/状态 的 div 也能提取', () {
      const text =
          '正文。\n'
          '<div class="status-panel">HP 42</div>\n'
          '<div class="tracker-box">MP 10</div>';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.specialStatusHtml, contains('MP 10'));
    });

    test('extractOpeningMessages 批量提取：正文过滤空 + 取最后一个 HTML', () {
      final raw = <String>[
        '第一条开场。',
        '第二条开场。\n<div style="background:#111;">面板一</div>',
        '<div style="background:#222;">面板二</div>',
      ];
      final result = ChatDisplaySanitizer.extractOpeningMessages(raw);
      expect(result.messages, ['第一条开场。', '第二条开场。']);
      expect(result.specialStatusHtml, contains('面板二'));
    });

    test('裸代码块 Markdown 状态栏不提取、保留在正文（苏蕴泠卡回归）', () {
      const text =
          '*暮色四合，她落在巷口。*「父亲，孩儿来看您了。」\n'
          '```\n'
          '人物：苏蕴泠\n'
          '当前心理状态：近乡情怯\n'
          '痴缠业：【零层•无】\n'
          '```';
      final result = ChatDisplaySanitizer.extract(text);
      // Markdown 状态栏不被当作 HTML 面板提取
      expect(result.specialStatusHtml, isNull);
      // 代码块原样保留在正文（原本正常的显示方式）
      expect(result.displayText, contains('人物：苏蕴泠'));
      expect(result.displayText, contains('```'));
    });

    test('```html 代码块内真实 HTML 面板仍提取', () {
      const text =
          '正文结束。\n'
          '```html\n'
          '<div style="background:#1a1a2e;">烙印值：35/100</div>\n'
          '```';
      final result = ChatDisplaySanitizer.extract(text);
      expect(result.displayText, '正文结束。');
      expect(result.specialStatusHtml, contains('烙印值'));
    });
  });
}
