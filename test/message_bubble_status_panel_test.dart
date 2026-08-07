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

    // 状态面板经 HtmlWidget 渲染为 RichText（非 Text widget），
    // 需 findRichText: true 才能匹配
    expect(find.textContaining('单聊状态：55/100', findRichText: true), findsOneWidget);
  });
}
