import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/prompt_assembly.dart';
import 'package:pocket_inn/models/world_book.dart';
import 'package:pocket_inn/services/context_usage_breakdown.dart';

void main() {
  group('estimateContextTokens', () {
    test('纯中文按 1 字 ≈ 1 token', () {
      expect(estimateContextTokens('你好世界'), 4);
    });

    test('纯英文按 4 字符 ≈ 1 token（向上取整）', () {
      expect(estimateContextTokens('abcd'), 1);
      expect(estimateContextTokens('abcde'), 2);
      expect(estimateContextTokens(''), 0);
    });

    test('中英混合累加', () {
      expect(estimateContextTokens('你好hello'), 2 + 2);
    });
  });

  group('breakdownContextTokens（生产拆分逻辑）', () {
    PromptAssemblyResult buildAssembly({
      required List<PromptMessage> messages,
      List<ActivatedWorldBookEntry> worldBookEntries = const [],
    }) {
      return PromptAssemblyResult(
        messages: messages,
        mergedText: '',
        activatedWorldBookEntries: worldBookEntries,
        segments: const [],
        unusedCharacterOverrides: const [],
      );
    }

    test('合并消息按 sourceChars 拆分到各来源', () {
      // 模拟 PromptAssembler 合并后的消息：预设 + 角色卡拼在一起
      final assembly = buildAssembly(
        messages: [
          PromptMessage(
            role: 'system',
            content: '预设内容。\n\n角色卡内容。',
            sources: ['预设: main', '角色卡: description'],
            sourceChars: [5, 5],
          ),
        ],
      );
      final breakdown = breakdownContextTokens(assembly);
      expect(breakdown.sections['预设: main'], 5); // 5 个 CJK 字符 → 5 token
      expect(breakdown.sections['角色卡: description'], 5);
      // 无双计：总 token = 两条之和
      expect(
        breakdown.sections.values.fold<int>(0, (s, v) => s + v),
        estimateContextTokens('预设内容。\n\n角色卡内容。'),
      );
    });

    test('世界书来源跳过消息层，仅按激活条目聚合（无双计）', () {
      final entry1 = WorldBookEntry(
        id: 'e1',
        content: '世界书条目一内容',
        comment: '',
      );
      final entry2 = WorldBookEntry(
        id: 'e2',
        content: '世界书条目二内容',
        comment: '',
      );
      final assembly = buildAssembly(
        messages: [
          PromptMessage(
            role: 'system',
            content: '世界书：before\n世界书条目一内容\n世界书条目二内容',
            sources: ['世界书: before'],
            sourceChars: [30],
          ),
        ],
        worldBookEntries: [
          ActivatedWorldBookEntry(
            bookId: 'b1',
            bookName: '设定集',
            entry: entry1,
            triggeredByConstant: false,
          ),
          ActivatedWorldBookEntry(
            bookId: 'b1',
            bookName: '设定集',
            entry: entry2,
            triggeredByConstant: false,
          ),
        ],
      );
      final breakdown = breakdownContextTokens(assembly);
      // 世界书按**实际注入文本**计入 sections['世界书']（无双计）；
      // 逐条目仅作明细展示（token 置 0，不再按原文重复估算）
      expect(breakdown.sections.containsKey('世界书: before'), isFalse);
      expect(
        breakdown.sections['世界书'],
        estimateContextTokens('世界书：before\n世界书条目一内容\n世界书条目二内容'),
      );
      expect(breakdown.worldBookEntries.length, 2);
      expect(
        breakdown.worldBookEntries.fold<int>(0, (s, e) => s + e.tokens),
        0,
      );
      expect(breakdown.worldBookEntries.first.bookName, '设定集');
    });

    test('聊天记录按 role 拆为我的消息/角色回复', () {
      final assembly = buildAssembly(
        messages: [
          PromptMessage(
            role: 'user',
            content: '用户说的内容',
            sources: const ['虚拟聊天记录'],
            sourceChars: const [6],
          ),
          PromptMessage(
            role: 'assistant',
            content: '角色回复的内容',
            sources: const ['虚拟聊天记录'],
            sourceChars: const [7],
          ),
          PromptMessage(
            role: 'system',
            content: '开场提示内容',
            sources: const ['虚拟聊天记录'],
            sourceChars: const [6],
          ),
        ],
      );
      final breakdown = breakdownContextTokens(assembly);
      // 聊天消息进入 chatHistory 明细（sections 不重复计数）
      expect(breakdown.sections.containsKey('我的消息'), isFalse);
      expect(breakdown.sections.containsKey('角色回复'), isFalse);
      expect(breakdown.chatHistory.length, 2);
      final userMsg = breakdown.chatHistory.firstWhere((m) => m.isUser);
      final assistantMsg =
          breakdown.chatHistory.firstWhere((m) => !m.isUser);
      // '用户说的内容' = 6 个 CJK 字符 → 6 token
      expect(userMsg.tokens, 6);
      // '角色回复的内容' = 7 个 CJK 字符 → 7 token
      expect(assistantMsg.tokens, 7);
      // new_chat_prompt 等系统开场提示单独归类进 sections
      expect(breakdown.sections['开场提示'], 6);
    });

    test('思维链模板与提醒单独计入', () {
      final assembly = buildAssembly(messages: const []);
      final breakdown = breakdownContextTokens(
        assembly,
        templateText: '【强制思维模式】模板内容',
        tailReminder: '提醒内容',
      );
      expect(
        breakdown.sections['思维链模板与提醒'],
        estimateContextTokens('【强制思维模式】模板内容') +
            estimateContextTokens('提醒内容'),
      );
    });

    test('无 sourceChars 时按 sources 均分（回退路径）；未知来源入未分类桶', () {
      final assembly = buildAssembly(
        messages: [
          PromptMessage(
            role: 'system',
            content: '甲乙丙丁',
            sources: ['来源A', '来源B'],
          ),
        ],
      );
      final breakdown = breakdownContextTokens(assembly);
      // 4 字符 / 2 来源 → 各 2；未知来源不静默丢失，进入"其他/未分类"
      expect(breakdown.sections.containsKey('来源A'), isFalse);
      expect(breakdown.sections.containsKey('来源B'), isFalse);
      expect(breakdown.sections['其他/未分类'], 4);
    });
  });
}
