import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/chat_message.dart';
import 'package:pocket_inn/models/preset.dart';
import 'package:pocket_inn/models/prompt_assembly.dart';
import 'package:pocket_inn/models/world_book.dart';
import 'package:pocket_inn/services/prompt_assembler.dart';

void main() {
  group('PromptAssembler', () {
    test('replaces variables across prompt and world book content', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(),
          userName: '林澈',
          userSettingPrompt: '我是{{user}}。',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'main',
                name: 'Main',
                content: 'Write for {{char}} with {{user}}.',
              ),
              PresetPrompt(
                identifier: 'worldInfoBefore',
                name: 'World Before',
                marker: true,
              ),
            ],
          ),
          selectedWorldBooks: [
            WorldBook(
              id: 'wb-1',
              name: '世界书',
              description: '',
              colorValue: 0xFF000000,
              entries: [
                const WorldBookEntry(
                  id: 'entry-1',
                  key: ['溪桥'],
                  keysecondary: [],
                  content: '{{char}}正在与{{user}}交谈。',
                  comment: '桥',
                  constant: false,
                  selective: false,
                  selectiveLogic: 0,
                  order: 10,
                  position: 0,
                  depth: 4,
                  sticky: 0,
                  cooldown: 0,
                  delay: 0,
                  isEnabled: true,
                  extensions: {},
                ),
              ],
            ),
          ],
          chatMessages: [ChatMessage(text: '我们去溪桥吧', isMe: true)],
          currentInput: '',
        ),
      );

      expect(result.mergedText, contains('Write for 艾琳 with 林澈.'));
      expect(result.mergedText, contains('艾琳正在与林澈交谈。'));
    });

    test(
      'preserves character overrides without replacing preset main or jailbreak',
      () {
        final result = PromptAssembler.build(
          PromptAssemblyContext(
            characterName: '艾琳',
            characterCardData: _cardData(
              systemPrompt: '角色卡 main',
              postHistoryInstructions: '角色卡 history',
            ),
            userName: '林澈',
            userSettingPrompt: '',
            preset: Preset(
              id: 'preset-1',
              name: '测试预设',
              updatedAt: DateTime(2026),
              prompts: [
                PresetPrompt(
                  identifier: 'main',
                  name: 'Main',
                  content: '预设 main',
                ),
                PresetPrompt(
                  identifier: 'jailbreak',
                  name: 'Jailbreak',
                  content: '预设 jailbreak',
                ),
                PresetPrompt(
                  identifier: 'post_history_instructions',
                  name: 'Post History',
                  content: '预设 history',
                ),
              ],
            ),
            selectedWorldBooks: const [],
            chatMessages: const [],
            currentInput: '',
          ),
        );

        expect(result.mergedText, contains('预设 main'));
        expect(result.mergedText, contains('预设 jailbreak'));
        expect(result.mergedText, isNot(contains('角色卡 main')));
        // v47：post_history_instructions 真正注入——预设与角色卡内容合并
        expect(result.mergedText, contains('预设 history'));
        expect(result.mergedText, contains('角色卡 history'));
        // system_prompt 仍保留为 unused override；post_history 不再列入
        expect(
          result.unusedCharacterOverrides.map((item) => item.field),
          contains('system_prompt'),
        );
        expect(
          result.unusedCharacterOverrides.map((item) => item.field),
          isNot(contains('post_history_instructions')),
        );
      },
    );

    test('v47: post_history_instructions 注入时剥离 <!--panel--> HTML 模板', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(
            postHistoryInstructions:
                '每次回复末尾输出状态面板\n'
                '<!--panel-->\n'
                '<details><summary>面板</summary><div>烙印值：'
                '{{getvar::yw_brand}}/100</div></details>\n'
                '<!--/panel-->\n'
                '数值必须与剧情一致',
          ),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'post_history_instructions',
                name: 'Post History',
                content: '',
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: const [],
          currentInput: '',
        ),
      );

      // 面板 HTML 模板被剥离（避免"输出 HTML 面板"与"只输出 JSON patch"
      // 冲突），文字规则保留。
      // v69：面板外的"输出状态栏"指令句也被剥离——模型只输出 JSON，
      // 面板由 App 渲染（否则模型收到两套互相矛盾的要求，会把面板
      // 混进正文）；非输出指令（字段含义/数值一致性规则）保留。
      expect(
        result.mergedText,
        isNot(contains('每次回复末尾输出状态面板')),
        reason: 'v69："输出状态栏"指令句不再注入模型（App 负责渲染面板）',
      );
      expect(result.mergedText, contains('数值必须与剧情一致'));
      expect(result.mergedText, isNot(contains('<details>')));
      expect(result.mergedText, isNot(contains('<!--panel-->')));
    });

    test('v48: 真实默认预设 identifier=jailbreak 也注入角色卡 post-history 规则', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(
            postHistoryInstructions:
                '每次回复末尾输出状态更新\n'
                '<!--panel-->\n'
                '<details><summary>面板</summary><div>烙印值：'
                '{{getvar::yw_brand}}/100</div></details>\n'
                '<!--/panel-->',
          ),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              // 与 assets/Default.json 一致：Post-History 用 jailbreak
              PresetPrompt(
                identifier: 'jailbreak',
                name: 'Post-History Instructions',
                content: '预设 jailbreak 内容',
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: const [],
          currentInput: '',
        ),
      );

      // 默认预设走 jailbreak：必须注入角色卡 post-history 规则（剥掉
      // panel HTML 块），否则模型收不到状态变化指令
      expect(result.mergedText, contains('预设 jailbreak 内容'));
      expect(result.mergedText, contains('每次回复末尾输出状态更新'));
      expect(result.mergedText, isNot(contains('<details>')));
      expect(result.mergedText, isNot(contains('<!--panel-->')));
    });

    test('v48: 说明句含字面 <!--panel--> 时注入剥离不被误伤', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(
            postHistoryInstructions:
                '必须保留 <!--panel--> 标记；数值用 {{getvar}} 引用，不得编造：\n'
                '<!--panel-->\n'
                '<details><summary>面板</summary><div>烙印值：'
                '{{getvar::yw_brand}}/100</div></details>\n'
                '<!--/panel-->\n'
                '其余规则',
          ),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'jailbreak',
                name: 'Post-History Instructions',
                content: '',
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: const [],
          currentInput: '',
        ),
      );

      // 说明句里的字面 <!--panel--> 不是独占整行 → 不应被当作边界删除；
      // 真正的面板块（独占整行）被剥离
      expect(result.mergedText, contains('必须保留 <!--panel--> 标记'));
      expect(result.mergedText, contains('其余规则'));
      expect(result.mergedText, isNot(contains('<details>')));
    });

    test('resolves setvar getvar comment and trim macros in prompt order', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'setter',
                name: 'Setter',
                content: '{{setvar::wordsCloud::不少于1000}}{{// 备注不会发送}}{{trim}}',
              ),
              PresetPrompt(
                identifier: 'reader',
                name: 'Reader',
                content: '长度要求：{{getvar::wordsCloud}}',
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: const [],
          currentInput: '',
        ),
      );

      expect(result.segments, hasLength(1));
      expect(result.segments.single.identifier, 'reader');
      expect(result.mergedText, contains('长度要求：不少于1000'));
      expect(result.mergedText, isNot(contains('setvar')));
      expect(result.mergedText, isNot(contains('备注不会发送')));
    });

    test('resolves input lastusermessage and lastcharmessage macros', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'main',
                name: 'Main',
                content:
                    'I={{input}} | LU={{lastusermessage}} | LC={{lastcharmessage}}',
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: [
            ChatMessage(text: '第一句', isMe: true),
            ChatMessage(text: '第二句', isMe: false),
            ChatMessage(text: '第三句', isMe: true),
          ],
          currentInput: '当前输入',
        ),
      );

      expect(result.mergedText, contains('I=当前输入 | LU=当前输入 | LC=第二句'));
    });

    test(
      'scans world book triggers only from chat history and current input',
      () {
        final result = PromptAssembler.build(
          PromptAssemblyContext(
            characterName: '艾琳',
            characterCardData: _cardData(description: '这里提到禁书库'),
            userName: '林澈',
            userSettingPrompt: '用户设定中提到禁书库',
            preset: Preset(
              id: 'preset-1',
              name: '测试预设',
              updatedAt: DateTime(2026),
              prompts: [
                PresetPrompt(
                  identifier: 'worldInfoBefore',
                  name: 'World Before',
                  marker: true,
                ),
              ],
            ),
            selectedWorldBooks: [
              WorldBook(
                id: 'wb-1',
                name: '世界书',
                description: '',
                colorValue: 0xFF000000,
                entries: [
                  const WorldBookEntry(
                    id: 'entry-1',
                    key: ['禁书库'],
                    keysecondary: [],
                    content: '命中禁书库',
                    comment: '禁书库',
                    constant: false,
                    selective: false,
                    selectiveLogic: 0,
                    order: 10,
                    position: 0,
                    depth: 4,
                    sticky: 0,
                    cooldown: 0,
                    delay: 0,
                    isEnabled: true,
                    extensions: {},
                  ),
                ],
              ),
            ],
            chatMessages: [ChatMessage(text: '这里只有普通对话', isMe: true)],
            currentInput: '',
          ),
        );

        expect(result.activatedWorldBookEntries, isEmpty);

        final triggered = PromptAssembler.build(
          PromptAssemblyContext(
            characterName: '艾琳',
            characterCardData: _cardData(),
            userName: '林澈',
            userSettingPrompt: '',
            preset: Preset(
              id: 'preset-1',
              name: '测试预设',
              updatedAt: DateTime(2026),
              prompts: [
                PresetPrompt(
                  identifier: 'worldInfoBefore',
                  name: 'World Before',
                  marker: true,
                ),
              ],
            ),
            selectedWorldBooks: result.activatedWorldBookEntries.isEmpty
                ? [
                    WorldBook(
                      id: 'wb-1',
                      name: '世界书',
                      description: '',
                      colorValue: 0xFF000000,
                      entries: [
                        const WorldBookEntry(
                          id: 'entry-1',
                          key: ['禁书库'],
                          keysecondary: [],
                          content: '命中禁书库',
                          comment: '禁书库',
                          constant: false,
                          selective: false,
                          selectiveLogic: 0,
                          order: 10,
                          position: 0,
                          depth: 4,
                          sticky: 0,
                          cooldown: 0,
                          delay: 0,
                          isEnabled: true,
                          extensions: {},
                        ),
                      ],
                    ),
                  ]
                : const [],
            chatMessages: [ChatMessage(text: '我们去禁书库', isMe: true)],
            currentInput: '',
          ),
        );

        expect(triggered.activatedWorldBookEntries, hasLength(1));
      },
    );

    test('merges adjacent messages with the same role', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(
            description: '角色描述',
            personality: '角色性格',
          ),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'charDescription',
                name: 'Description',
                role: 'system',
                marker: true,
              ),
              PresetPrompt(
                identifier: 'charPersonality',
                name: 'Personality',
                role: 'system',
                marker: true,
              ),
              PresetPrompt(
                identifier: 'chatHistory',
                name: 'History',
                role: 'user',
                marker: true,
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: [ChatMessage(text: '你好', isMe: true)],
          currentInput: '继续',
        ),
      );

      expect(result.segments, hasLength(3));
      expect(result.messages, hasLength(2));
      expect(result.messages.first.role, 'system');
      expect(result.messages.first.content, contains('角色描述'));
      expect(result.messages.first.content, contains('角色性格'));
      expect(result.messages.first.sources, hasLength(2));
    });

    test(
      'uses new chat prompt, replaces example start token, and formats history with roles',
      () {
        final result = PromptAssembler.build(
          PromptAssemblyContext(
            characterName: '艾琳',
            characterCardData: _cardData(
              mesExample: '<START>\n{{user}}: 你好\n{{char}}: 你好。',
            ),
            userName: '林澈',
            userSettingPrompt: '',
            preset: Preset(
              id: 'preset-1',
              name: '测试预设',
              updatedAt: DateTime(2026),
              prompts: [
                PresetPrompt(
                  identifier: 'dialogueExamples',
                  name: 'Examples',
                  role: 'system',
                  marker: true,
                ),
                PresetPrompt(
                  identifier: 'chatHistory',
                  name: 'History',
                  role: 'system',
                  marker: true,
                ),
              ],
              extra: const {
                'new_chat_prompt': '[Start a new Chat]',
                'new_example_chat_prompt': '[Example Chat]',
              },
            ),
            selectedWorldBooks: const [],
            chatMessages: [
              ChatMessage(text: '第一句', isMe: true),
              ChatMessage(text: '第二句', isMe: false),
            ],
            currentInput: '第三句',
          ),
        );

        expect(result.mergedText, contains('[Example Chat]'));
        expect(result.mergedText, isNot(contains('<START>')));
        expect(
          result.mergedText,
          contains('[Start a new Chat]\nuser: 第一句\nassistant: 第二句\nuser: 第三句'),
        );
        expect(result.mergedText, isNot(contains('林澈: 第一句')));
        expect(result.mergedText, isNot(contains('艾琳: 第二句')));

        expect(result.messages, hasLength(4));
        expect(result.messages[0].role, 'system');
        expect(result.messages[0].content, contains('[Example Chat]'));
        expect(result.messages[0].content, contains('[Start a new Chat]'));
        expect(result.messages[1].role, 'user');
        expect(result.messages[1].content, '第一句');
        expect(result.messages[2].role, 'assistant');
        expect(result.messages[2].content, '第二句');
        expect(result.messages[3].role, 'user');
        expect(result.messages[3].content, '第三句');
      },
    );

    test('群聊历史消息带发言人名字前缀', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'chatHistory',
                name: 'History',
                role: 'system',
                marker: true,
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: [
            ChatMessage(text: '你好', isMe: true),
            ChatMessage(
              text: '我是艾琳',
              isMe: false,
              characterId: 'char-a',
            ),
            ChatMessage(
              text: '我是莉莉',
              isMe: false,
              characterId: 'char-b',
            ),
          ],
          currentInput: '继续',
          groupCharacterNames: const {
            'char-a': '艾琳',
            'char-b': '莉莉',
          },
        ),
      );

      // 合并文本历史：用户消息为 user，角色消息带各自名字
      expect(result.mergedText, contains('user: 你好'));
      expect(result.mergedText, contains('艾琳: 我是艾琳'));
      expect(result.mergedText, contains('莉莉: 我是莉莉'));
      // OpenAI 消息：群聊角色消息 role 全部为 user（带发言人前缀）——
      // 模型不会把其他角色的发言当成自己说的（人设混同的模型层修复）
      final history = result.messages
          .where(
            (m) => m.content.contains('我是艾琳') || m.content.contains('我是莉莉'),
          )
          .toList();
      expect(history, hasLength(1));
      expect(history.first.role, 'user');
      expect(history.first.content, contains('艾琳: 我是艾琳'));
      expect(history.first.content, contains('莉莉: 我是莉莉'));
    });

    test('群聊时注入扮演说明（当前发言者 + 其他成员仅背景）', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'chatHistory',
                name: 'History',
                role: 'system',
                marker: true,
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: [ChatMessage(text: '你好', isMe: true)],
          currentInput: '继续',
          groupCharacterNames: const {
            'char-a': '艾琳',
            'char-b': '莉莉',
          },
        ),
      );

      // 扮演说明注入 system 且包含当前发言者与禁止混用人设
      final instruction = result.messages
          .where((m) => m.content.contains('群聊扮演说明'))
          .toList();
      expect(instruction, hasLength(1));
      expect(instruction.first.role, 'system');
      expect(instruction.first.content, contains('当前发言角色：艾琳'));
      expect(instruction.first.content, contains('莉莉'));
      expect(instruction.first.content, contains('禁止使用他人'));
      // 单聊不注入
      final single = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [],
          ),
          selectedWorldBooks: const [],
          chatMessages: [ChatMessage(text: '你好', isMe: true)],
          currentInput: '继续',
        ),
      );
      expect(
        single.mergedText.contains('群聊扮演说明'),
        isFalse,
      );
    });

    test(
      'inserts in-chat prompts by depth and orders same-depth prompts by role then injection order',
      () {
        final result = PromptAssembler.build(
          PromptAssemblyContext(
            characterName: '艾琳',
            characterCardData: _cardData(),
            userName: '林澈',
            userSettingPrompt: '',
            preset: Preset(
              id: 'preset-1',
              name: '测试预设',
              updatedAt: DateTime(2026),
              prompts: [
                PresetPrompt(
                  identifier: 'chatHistory',
                  name: 'History',
                  role: 'system',
                  marker: true,
                ),
                PresetPrompt(
                  identifier: 'tail_system',
                  name: 'Tail System',
                  content: 'System tail',
                  role: 'system',
                  systemPrompt: true,
                  injectionPosition: PresetInjectionPosition.inChat,
                  injectionDepth: 0,
                ),
                PresetPrompt(
                  identifier: 'depth_user_late',
                  name: 'Depth User Late',
                  content: 'User note 20',
                  role: 'user',
                  systemPrompt: false,
                  injectionPosition: PresetInjectionPosition.inChat,
                  injectionDepth: 1,
                  injectionOrder: 20,
                ),
                PresetPrompt(
                  identifier: 'depth_assistant',
                  name: 'Depth Assistant',
                  content: 'Assistant note',
                  role: 'assistant',
                  systemPrompt: false,
                  injectionPosition: PresetInjectionPosition.inChat,
                  injectionDepth: 1,
                  injectionOrder: 10,
                ),
                PresetPrompt(
                  identifier: 'depth_user_early',
                  name: 'Depth User Early',
                  content: 'User note 10',
                  role: 'user',
                  systemPrompt: false,
                  injectionPosition: PresetInjectionPosition.inChat,
                  injectionDepth: 1,
                  injectionOrder: 10,
                ),
              ],
            ),
            selectedWorldBooks: const [],
            chatMessages: [
              ChatMessage(text: '第一句', isMe: true),
              ChatMessage(text: '第二句', isMe: false),
            ],
            currentInput: '第三句',
          ),
        );

        expect(
          result.mergedText,
          contains(
            'assistant: 第二句\nuser: User note 10\n\nUser note 20\nassistant: Assistant note\nuser: 第三句\nsystem: System tail',
          ),
        );
        expect(result.messages.map((item) => item.role).toList(), [
          'user',
          'assistant',
          'user',
          'assistant',
          'user',
          'system',
        ]);
        expect(result.messages[2].content, 'User note 10\n\nUser note 20');
        expect(result.messages[3].content, 'Assistant note');
        expect(result.messages[4].content, '第三句');
        expect(result.messages[5].content, 'System tail');
      },
    );

    test('places deep in-chat prompts before the first chat message', () {
      final result = PromptAssembler.build(
        PromptAssemblyContext(
          characterName: '艾琳',
          characterCardData: _cardData(),
          userName: '林澈',
          userSettingPrompt: '',
          preset: Preset(
            id: 'preset-1',
            name: '测试预设',
            updatedAt: DateTime(2026),
            prompts: [
              PresetPrompt(
                identifier: 'chatHistory',
                name: 'History',
                role: 'system',
                marker: true,
              ),
              PresetPrompt(
                identifier: 'deep_system',
                name: 'Deep System',
                content: 'Before all history',
                role: 'system',
                injectionPosition: PresetInjectionPosition.inChat,
                injectionDepth: 99,
              ),
            ],
          ),
          selectedWorldBooks: const [],
          chatMessages: [ChatMessage(text: '第一句', isMe: true)],
          currentInput: '',
        ),
      );

      expect(result.messages, hasLength(2));
      expect(result.messages.first.role, 'system');
      expect(result.messages.first.content, 'Before all history');
      expect(result.messages.last.role, 'user');
      expect(result.messages.last.content, '第一句');
    });
  });
}

Map<String, dynamic> _cardData({
  String description = '角色描述',
  String personality = '角色性格',
  String scenario = '角色场景',
  String mesExample = '示例对话',
  String systemPrompt = '',
  String postHistoryInstructions = '',
}) {
  return {
    'spec': 'chara_card_v2',
    'spec_version': '2.0',
    'data': {
      'name': '艾琳',
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': '',
      'mes_example': mesExample,
      'creator_notes': '',
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistoryInstructions,
      'alternate_greetings': <String>[],
      'tags': <String>[],
      'character_book': {
        'entries': <String, dynamic>{},
        'extensions': <String, dynamic>{},
      },
      'extensions': <String, dynamic>{},
    },
  };
}
