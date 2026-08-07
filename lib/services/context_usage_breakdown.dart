import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/prompt_assembly.dart';

/// 估算 token 数：CJK 字符 ≈ 1 token，其余按 4 字符 ≈ 1 token。
/// 与真实 tokenizer 存在偏差，仅作参考（上下文用量统计用）。
int estimateContextTokens(String text) {
  var cjk = 0;
  var other = 0;
  for (final rune in text.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk + (other + 3) ~/ 4;
}

/// 详细分解中的单项。
class ContextUsageItem {
  const ContextUsageItem({required this.name, required this.tokens});

  final String name;
  final int tokens;
}

/// 世界信息单条目用量（参考图 World Info 逐条目明细）。
class WorldBookEntryUsage {
  const WorldBookEntryUsage({
    required this.bookName,
    required this.entryName,
    required this.tokens,
  });

  final String bookName;
  final String entryName;
  final int tokens;
}

/// 聊天历史单条消息用量（参考图 Chat History 逐条明细）。
class ChatMessageUsage {
  const ChatMessageUsage({
    required this.isUser,
    required this.index,
    required this.preview,
    required this.tokens,
  });

  final bool isUser;
  final int index;
  final String preview;
  final int tokens;
}

/// 上下文用量分解结果。
class ContextUsageBreakdown {
  const ContextUsageBreakdown({
    required this.sections,
    required this.worldBookEntries,
    required this.chatHistory,
  });

  /// 分组聚合（预设/角色卡/用户设定/长期记忆/开场提示/思维链模板等）。
  final Map<String, int> sections;

  /// 世界信息逐条目。
  final List<WorldBookEntryUsage> worldBookEntries;

  /// 聊天历史逐条（我的消息/角色回复）。
  final List<ChatMessageUsage> chatHistory;
}

/// 按来源拆分统计一次提示词组装的 token 用量（公共纯函数，可单测）。
///
/// 规则：
/// - 消息按 [PromptMessage.sources]/[sourceChars] 拆分（PromptAssembler
///   会合并相邻同 role 消息，sources 保留全部来源），各来源按字符权重
///   分摊 token；
/// - '世界书: ' 来源的消息份额与聊天记录消息不进入 [sections]，分别由
///   [worldBookEntries]（逐条目）与 [chatHistory]（逐条）承载，防双计；
/// - [templateText] 非空时计入 '思维链模板与提醒'。
ContextUsageBreakdown breakdownContextTokens(
  PromptAssemblyResult assembly, {
  String? templateText,
  String tailReminder = '',
}) {
  final sections = <String, int>{};
  final chatHistory = <ChatMessageUsage>[];
  var userCount = 0;
  var assistantCount = 0;

  void add(String name, int tokens) {
    if (tokens <= 0) return;
    sections[name] = (sections[name] ?? 0) + tokens;
  }

  for (final message in assembly.messages) {
    final chars = message.sourceChars.isNotEmpty &&
            message.sourceChars.length == message.sources.length
        ? message.sourceChars
        : List.filled(
            max(1, message.sources.length),
            message.content.length ~/ max(1, message.sources.length),
          );
    final totalChars = chars.fold<int>(0, (sum, c) => sum + c);
    if (totalChars <= 0) continue;
    final messageTokens = estimateContextTokens(message.content);
    for (var i = 0; i < message.sources.length; i++) {
      final source = message.sources[i];
      final tokens = (messageTokens * chars[i] / totalChars).round();
      if (tokens <= 0) continue;
      if (source.startsWith('预设: ')) {
        add(source, tokens);
      } else if (source.startsWith('角色卡: ')) {
        add(source, tokens);
      } else if (source.startsWith('世界书: ')) {
        // 特别版：世界书按**实际注入文本**统计（before/after 段含
        // 标题/包装/顺序），而不是按条目原文估算。逐条目明细仍由
        // [worldBookEntries] 展示（仅展示原文预览，token 不再重复计）。
        add('世界书', tokens);
      } else if (source == '用户设定') {
        add('用户设定', tokens);
      } else if (source == '长期记忆') {
        add('长期记忆', tokens);
      } else if (source == '虚拟聊天记录') {
        if (message.role == 'system') {
          // new_chat_prompt 等开场系统提示
          add('开场提示', tokens);
        } else if (message.role == 'user') {
          userCount++;
          chatHistory.add(
            ChatMessageUsage(
              isUser: true,
              index: userCount,
              preview: _previewOf(message.content),
              tokens: tokens,
            ),
          );
        } else {
          assistantCount++;
          chatHistory.add(
            ChatMessageUsage(
              isUser: false,
              index: assistantCount,
              preview: _previewOf(message.content),
              tokens: tokens,
            ),
          );
        }
      } else if (source == '群聊扮演说明') {
        add('群聊扮演说明', tokens);
      } else {
        // 特别版：未分类来源不能静默丢失——计入"其他/未分类"桶，
        // 并输出 debug 日志便于排查漏算。
        debugPrint('[CONTEXT_USAGE] 未分类来源: "$source" '
            'tokens=$tokens');
        add('其他/未分类', tokens);
      }
    }
  }

  // 世界书：按激活条目逐条聚合（条目名取 comment，空则取内容前缀）
  final worldBookEntries = <WorldBookEntryUsage>[];
  for (final entry in assembly.activatedWorldBookEntries) {
    // 特别版：逐条目仅作明细展示（条目名 + 原文预览）；token 已按
    // 实际注入文本并入 sections['世界书']，此处不重复计数（置 0）。
    worldBookEntries.add(
      WorldBookEntryUsage(
        bookName: entry.bookName,
        entryName: _entryLabel(entry),
        tokens: 0,
      ),
    );
  }

  // 思维链模板与提醒（固定注入的系统提示）
  if (templateText != null && templateText.isNotEmpty) {
    add(
      '思维链模板与提醒',
      estimateContextTokens(templateText) +
          estimateContextTokens(tailReminder),
    );
  }

  return ContextUsageBreakdown(
    sections: sections,
    worldBookEntries: worldBookEntries,
    chatHistory: chatHistory,
  );
}

/// 消息内容预览（首行前 16 字）。
String _previewOf(String content) {
  final firstLine = content.trim().split('\n').first.trim();
  if (firstLine.length <= 16) {
    return firstLine;
  }
  return '${firstLine.substring(0, 16)}…';
}


String _entryLabel(ActivatedWorldBookEntry entry) {
  final comment = entry.entry.comment.trim();
  if (comment.isNotEmpty) {
    return comment.length <= 20 ? comment : '${comment.substring(0, 20)}…';
  }
  return _previewOf(entry.entry.content);
}
