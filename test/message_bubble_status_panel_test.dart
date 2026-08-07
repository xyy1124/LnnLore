import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/chat_message.dart';
import 'package:pocket_inn/pages/chat/widgets/message_bubble.dart';
import 'package:pocket_inn/pages/chat/widgets/special_status_panel.dart';
import 'package:pocket_inn/services/chat_character_resolver.dart';

/// 特别版：消息气泡状态面板的两项 v45 回归——
/// ① v2 规范快照压过 v1 旧模型 HTML（v1 旧快照被忽略）
/// ② 群聊历史消息用各自 resolvedSpeaker 的角色模板（非全局 activeCharacter）
void main() {
  ResolvedChatCharacter character({
    required String id,
    required String name,
    required Map<String, dynamic> cardJson,
  }) {
    return ResolvedChatCharacter(
      id: id,
      name: name,
      description: '测试角色',
      cardJson: cardJson,
    );
  }

  Map<String, dynamic> cardWithTemplate(String template, String schemaKey) => {
        'data': {
          'name': '测试角色',
          // v47：HTML 面板模板定义在 post_history_instructions 的
          // <!--panel--> 段（renderStatusPanelHtml 优先读取它）
          'post_history_instructions':
              '必须输出状态面板：\n<!--panel-->\n$template\n<!--/panel-->',
          'extensions': {
            'regex_scripts': [
              {
                'scriptName': 'StatusFallback',
                'replaceString': '文本兜底：{{getvar::$schemaKey}}',
              },
            ],
            'tracker': {
              'stateSchema': {
                schemaKey: {
                  'type': 'number',
                  'label': '烙印值',
                  'min': 0,
                  'max': 100,
                },
              },
              'initialState': {schemaKey: 20},
            },
          },
        },
      };

  Widget buildBubble({
    required ChatMessage message,
    required ResolvedChatCharacter? character,
    ResolvedChatCharacter? resolvedSpeaker,
    Map<String, String> sessionVariables = const {},
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: message,
          userSetting: null,
          character: character,
          resolvedSpeaker: resolvedSpeaker,
          inputTapRegionGroupId: Object(),
          isLastUserMessageWithoutReply: false,
          isLastCharacterMessage: false,
          showActions: false,
          canEdit: false,
          canDelete: false,
          isBusyRegenerating: false,
          isBusyImpersonating: false,
          onCopy: () {},
          onEdit: () {},
          onDelete: () {},
          sessionVariables: sessionVariables,
        ),
      ),
    );
  }

  testWidgets('v3 结构化状态快照优先，v2/v1 旧 HTML 快照被忽略', (tester) async {
    final card = character(
      id: 'A',
      name: '角色A',
      cardJson: cardWithTemplate('<div>烙印值：{{getvar::yw_brand}}/100</div>',
          'yw_brand'),
    );
    await tester.pumpWidget(
      buildBubble(
        message: ChatMessage(id: 'm1', text: '角色回复正文', isMe: false),
        character: card,
        sessionVariables: {
          // v1/v2 旧 HTML 快照（写死旧值 20/25）——v47 起必须被忽略
          '__msg_status_html__:m1': '<div>烙印值：20/100</div>',
          '__msg_status_html_v2__:m1': '<div>烙印值：25/100</div>',
          // v3 结构化状态（patch 应用后的最终值 35）——应优先显示，
          // 由气泡用角色卡模板动态渲染
          '__msg_tracker_state_v3__:m1': '{"yw_brand":"35"}',
        },
      ),
    );
    await tester.pumpAndSettle();

    // v50：面板默认收起——先点击兜底标题栏"状态面板"展开
    await tester.tap(find.text('状态面板'));
    await tester.pumpAndSettle();

    // 状态面板经 HtmlWidget 渲染为 RichText（非 Text widget），
    // 需 findRichText: true 才能匹配
    expect(
      find.textContaining('烙印值：35/100', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('20/100', findRichText: true), findsNothing);
    expect(find.textContaining('25/100', findRichText: true), findsNothing);
  });

  testWidgets('无快照时运行时生成面板用 resolvedSpeaker 模板（群聊）', (tester) async {
    final activeA = character(
      id: 'A',
      name: '角色A',
      cardJson: cardWithTemplate('<div>A状态：{{getvar::a_brand}}/100</div>',
          'a_brand'),
    );
    final speakerB = character(
      id: 'B',
      name: '角色B',
      cardJson: cardWithTemplate('<div>B状态：{{getvar::b_brand}}/100</div>',
          'b_brand'),
    );
    await tester.pumpWidget(
      buildBubble(
        // 群聊历史消息：characterId 指向 B，全局 activeCharacter 是 A
        message: ChatMessage(
          id: 'm1',
          text: 'B 的发言',
          isMe: false,
          characterId: 'B',
        ),
        character: activeA,
        resolvedSpeaker: speakerB,
        // 无 v2 快照 → 走运行时生成（必须用 B 的模板与变量）
        sessionVariables: {'b_brand': '42'},
      ),
    );
    await tester.pumpAndSettle();

    // v50：默认收起——展开后断言 B 的模板与变量（resolvedSpeaker）
    await tester.tap(find.text('状态面板'));
    await tester.pumpAndSettle();

    // 无快照时运行时生成：必须用 B 的模板与变量（resolvedSpeaker）
    expect(
      find.textContaining('B状态：42/100', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('A状态', findRichText: true), findsNothing);
  });

  testWidgets('单聊消息（characterId 为空）用全局 character 模板', (tester) async {
    final card = character(
      id: 'A',
      name: '角色A',
      cardJson: cardWithTemplate('<div>单聊状态：{{getvar::yw_brand}}/100</div>',
          'yw_brand'),
    );
    await tester.pumpWidget(
      buildBubble(
        message: ChatMessage(id: 'm1', text: '单聊正文', isMe: false),
        character: card,
        sessionVariables: {'yw_brand': '55'},
      ),
    );
    await tester.pumpAndSettle();

    // v50：默认收起——先点击兜底标题栏"状态面板"展开
    await tester.tap(find.text('状态面板'));
    await tester.pumpAndSettle();

    // 状态面板经 HtmlWidget 渲染为 RichText（非 Text widget），
    // 需 findRichText: true 才能匹配
    expect(find.textContaining('单聊状态：55/100', findRichText: true), findsOneWidget);
  });

  testWidgets('v49: 面板 summary 标题提取为折叠标题栏（可点击收起）', (tester) async {
    final card = character(
      id: 'A',
      name: '角色A',
      cardJson: cardWithTemplate(
        '<details><summary>🩸 烙印状态面板</summary>'
        '<div>烙印值：{{getvar::yw_brand}}/100</div></details>',
        'yw_brand',
      ),
    );
    await tester.pumpWidget(
      buildBubble(
        message: ChatMessage(id: 'm1', text: '角色回复正文', isMe: false),
        character: card,
        sessionVariables: {
          '__msg_tracker_state_v3__:m1': '{"yw_brand":"30"}',
        },
      ),
    );
    await tester.pumpAndSettle();

    // 标题提取为 Flutter Text（SpecialStatusPanel 原生标题栏，非 HtmlWidget）
    // 注：含 emoji（🩸）的文本 Text 内部走 RichText，需 findRichText: true
    expect(
      find.text('🩸 烙印状态面板', findRichText: true),
      findsOneWidget,
    );
    // v50：默认收起——正文初始不可见
    expect(
      find.textContaining('烙印值：30/100', findRichText: true),
      findsNothing,
    );
    // 点击标题 → 展开：正文可见
    await tester.tap(find.text('🩸 烙印状态面板', findRichText: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('烙印值：30/100', findRichText: true),
      findsOneWidget,
    );
    // 再点击 → 收起
    await tester.tap(find.text('🩸 烙印状态面板', findRichText: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('烙印值：30/100', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('v49: SpecialStatusPanel 无标题时行为与旧版一致（无折叠栏）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpecialStatusPanel(html: '<div>烙印值：30/100</div>'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 无折叠标题栏；正文直接渲染
    expect(
      find.textContaining('烙印值：30/100', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('v58: 折叠偏好三态——defaultExpanded=true 但用户保存 0 时保持收起', (tester) async {
    final card = character(
      id: 'A',
      name: '角色A',
      cardJson: {
        'data': {
          'name': '角色A',
          'post_history_instructions':
              '<!--panel-->\n<div>烙印值：{{getvar::yw_brand}}/100</div>\n<!--/panel-->',
          'extensions': {
            'tracker': {
              'stateSchema': {
                'yw_brand': {
                  'type': 'number',
                  'label': '烙印值',
                  'min': 0,
                  'max': 100,
                },
              },
              'initialState': {'yw_brand': 0},
              'defaultExpanded': true,
            },
          },
        },
      },
    );
    await tester.pumpWidget(
      buildBubble(
        message: ChatMessage(id: 'm1', text: '回复', isMe: false),
        character: card,
        // 用户手动收起偏好 '0'——即使卡声明 defaultExpanded=true
        sessionVariables: {'__tracker_expanded__:A': '0'},
      ),
    );
    await tester.pumpAndSettle();
    // 收起：正文不可见，标题栏兜底可见
    expect(
      find.textContaining('烙印值：0/100', findRichText: true),
      findsNothing,
    );
    // 点击展开后可见
    await tester.tap(find.text('状态面板'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('烙印值：0/100', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('v58: 折叠偏好三态——偏好 1 时展开（无视 defaultExpanded=false）', (tester) async {
    final card = character(
      id: 'A',
      name: '角色A',
      cardJson: {
        'data': {
          'name': '角色A',
          'post_history_instructions':
              '<!--panel-->\n<div>烙印值：{{getvar::yw_brand}}/100</div>\n<!--/panel-->',
          'extensions': {
            'tracker': {
              'stateSchema': {
                'yw_brand': {
                  'type': 'number',
                  'label': '烙印值',
                  'min': 0,
                  'max': 100,
                },
              },
              'initialState': {'yw_brand': 0},
            },
          },
        },
      },
    );
    await tester.pumpWidget(
      buildBubble(
        message: ChatMessage(id: 'm1', text: '回复', isMe: false),
        character: card,
        sessionVariables: {'__tracker_expanded__:A': '1'},
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('烙印值：0/100', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('v58: Safe HTML 面板不再套统一深色外框（外层透明）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpecialStatusPanel(
            title: '测试面板',
            html: '<div style="background-color:#171020;border:2px solid #8e44ad;">'
                '烙印值：30/100</div>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 无 v50 的统一深色外框 Container（0xFF17131F）
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == const Color(0xFF17131F),
      ),
      findsNothing,
    );
    // 卡自己的 HTML 正常渲染
    expect(
      find.textContaining('烙印值：30/100', findRichText: true),
      findsOneWidget,
    );
  });
}
