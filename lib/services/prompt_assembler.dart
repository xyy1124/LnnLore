import 'dart:math';

import '../models/character_card.dart';
import '../models/chat_message.dart';
import '../models/prompt_assembly.dart';
import '../models/preset.dart';
import '../models/world_book.dart';
import 'chat_memory_service.dart';
import 'chat_variable_service.dart';

class PromptAssembler {
  const PromptAssembler._();

  static PromptAssemblyResult build(PromptAssemblyContext context) {
    final normalizedCard = normalizeToV2Card(context.characterCardData);
    final cardData = Map<String, dynamic>.from(
      normalizedCard['data'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );
    final macroState = _buildMacroState(context);
    final activatedEntries = _activateWorldBookEntries(
      worldBooks: context.selectedWorldBooks,
      chatMessages: context.chatMessages,
      currentInput: context.currentInput,
    );
    final worldInfoBefore = _joinWorldBookContent(
      activatedEntries.where((item) => item.entry.position == 0).toList(),
    );
    final worldInfoAfter = _joinWorldBookContent(
      activatedEntries.where((item) => item.entry.position != 0).toList(),
    );
    final unusedOverrides = _buildUnusedOverrides(cardData, context);

    final resolvedEntries = <_ResolvedPromptEntry>[];
    var sequence = 0;
    for (final prompt in context.preset.prompts) {
      if (!prompt.enabled) {
        continue;
      }

      final content = _resolvePromptContent(
        prompt: prompt,
        cardData: cardData,
        context: context,
        macroState: macroState,
        worldInfoBefore: worldInfoBefore,
        worldInfoAfter: worldInfoAfter,
      );
      if (content.trim().isEmpty) {
        continue;
      }

      resolvedEntries.add(
        _ResolvedPromptEntry(
          prompt: prompt,
          sequence: sequence++,
          segment: PromptSegment(
            role: prompt.role.trim().isEmpty ? 'system' : prompt.role.trim(),
            content: content.trim(),
            source: _sourceLabel(prompt),
            identifier: prompt.identifier,
          ),
        ),
      );
    }

    // 特别版：群聊扮演说明（最高优先级，注入在预设之后）
    // 解决"调度/头像轮流但人设混同"：OpenAI 的 assistant role 会让
    // 模型把历史中其他角色的消息当成自己说的，导致人设被污染。
    if (context.groupCharacterNames.isNotEmpty) {
      resolvedEntries.insert(
        0,
        _ResolvedPromptEntry(
          prompt: const PresetPrompt(
            identifier: 'groupChatInstruction',
            name: 'GroupChatInstruction',
            role: 'system',
            marker: true,
          ),
          sequence: -1,
          segment: PromptSegment(
            role: 'system',
            content: _buildGroupChatInstruction(context),
            source: '群聊扮演说明',
            identifier: 'groupChatInstruction',
          ),
        ),
      );
    }

    final inChatEntries = resolvedEntries
        .where((item) => _isInChatPrompt(item.prompt))
        .toList(growable: false);
    final topLevelSegments = resolvedEntries
        .where((item) => !_isInChatPrompt(item.prompt))
        .map(
          (item) => item.segment.identifier == 'chatHistory'
              ? PromptSegment(
                  role: item.segment.role,
                  content: _buildMergedChatHistoryText(
                    context: context,
                    inChatEntries: inChatEntries,
                  ),
                  source: item.segment.source,
                  identifier: item.segment.identifier,
                )
              : item.segment,
        )
        .toList(growable: false);
    final messages = _buildOpenAiMessages(
      segments: topLevelSegments,
      inChatEntries: inChatEntries,
      context: context,
    );
    return PromptAssemblyResult(
      messages: messages,
      mergedText: _buildMergedText(_mergeAdjacentMessages(topLevelSegments)),
      activatedWorldBookEntries: activatedEntries,
      segments: topLevelSegments,
      unusedCharacterOverrides: unusedOverrides,
    );
  }

  static List<ActivatedWorldBookEntry> _activateWorldBookEntries({
    required List<WorldBook> worldBooks,
    required List<ChatMessage> chatMessages,
    required String currentInput,
  }) {
    final scanCorpus = [
      for (final message in chatMessages) message.text,
      currentInput,
    ].join('\n').toLowerCase();
    final activated = <ActivatedWorldBookEntry>[];
    final seen = <String>{};

    for (final book in worldBooks) {
      final sortedEntries = [...book.entries]
        ..sort((a, b) {
          final positionCompare = a.position.compareTo(b.position);
          if (positionCompare != 0) {
            return positionCompare;
          }
          return a.order.compareTo(b.order);
        });

      for (final entry in sortedEntries) {
        if (!entry.isEnabled) {
          continue;
        }
        final triggeredByConstant = entry.constant;
        final matchesKeywords = _matchesWorldBookEntry(entry, scanCorpus);
        if (!triggeredByConstant && !matchesKeywords) {
          continue;
        }

        final dedupeKey = '${entry.position}|${entry.content.trim()}';
        if (!seen.add(dedupeKey)) {
          continue;
        }

        activated.add(
          ActivatedWorldBookEntry(
            bookId: book.id,
            bookName: book.name,
            entry: entry,
            triggeredByConstant: triggeredByConstant,
          ),
        );
      }
    }

    activated.sort((a, b) {
      final positionCompare = a.entry.position.compareTo(b.entry.position);
      if (positionCompare != 0) {
        return positionCompare;
      }
      return a.entry.order.compareTo(b.entry.order);
    });
    return activated;
  }

  static bool _matchesWorldBookEntry(WorldBookEntry entry, String scanCorpus) {
    if (scanCorpus.trim().isEmpty) {
      return false;
    }

    final keywords = [
      ...entry.key,
      ...entry.keysecondary,
    ].map((item) => item.trim().toLowerCase()).where((item) => item.isNotEmpty);

    for (final keyword in keywords) {
      if (scanCorpus.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static String _joinWorldBookContent(List<ActivatedWorldBookEntry> entries) {
    return entries
        .map((item) => item.entry.content)
        .where((item) => item.trim().isNotEmpty)
        .join('\n\n');
  }

  static List<UnusedCharacterOverride> _buildUnusedOverrides(
    Map<String, dynamic> cardData,
    PromptAssemblyContext context,
  ) {
    final overrides = <UnusedCharacterOverride>[];
    final systemPrompt = _replaceVariables(
      cardData['system_prompt'] as String? ?? '',
      context,
    ).trim();
    if (systemPrompt.isNotEmpty) {
      overrides.add(
        const UnusedCharacterOverride(
          field: 'system_prompt',
          content: '',
          reason: '角色卡字段已保留，本期不覆盖预设 main。',
        ),
      );
      overrides[overrides.length - 1] = UnusedCharacterOverride(
        field: 'system_prompt',
        content: systemPrompt,
        reason: '角色卡字段已保留，本期不覆盖预设 main。',
      );
    }

    final postHistoryInstructions = _replaceVariables(
      cardData['post_history_instructions'] as String? ?? '',
      context,
    ).trim();
    if (postHistoryInstructions.isNotEmpty) {
      overrides.add(
        UnusedCharacterOverride(
          field: 'post_history_instructions',
          content: postHistoryInstructions,
          reason: '角色卡字段已保留，本期不覆盖预设 jailbreak/post_history_instructions。',
        ),
      );
    }
    return overrides;
  }

  static String _resolvePromptContent({
    required PresetPrompt prompt,
    required Map<String, dynamic> cardData,
    required PromptAssemblyContext context,
    required PromptMacroState macroState,
    required String worldInfoBefore,
    required String worldInfoAfter,
  }) {
    final rawContent = _resolveRawPromptContent(
      prompt: prompt,
      cardData: cardData,
      context: context,
      worldInfoBefore: worldInfoBefore,
      worldInfoAfter: worldInfoAfter,
    );
    return _resolvePromptText(rawContent, macroState);
  }

  static String _resolveRawPromptContent({
    required PresetPrompt prompt,
    required Map<String, dynamic> cardData,
    required PromptAssemblyContext context,
    required String worldInfoBefore,
    required String worldInfoAfter,
  }) {
    switch (prompt.identifier) {
      case 'personaDescription':
        return context.userSettingPrompt;
      case 'charDescription':
        return cardData['description'] as String? ?? '';
      case 'charPersonality':
        return cardData['personality'] as String? ?? '';
      case 'scenario':
        return cardData['scenario'] as String? ?? '';
      case 'dialogueExamples':
        return _replaceExampleChat(
          cardData['mes_example'] as String? ?? '',
          context,
        );
      case 'chatHistory':
        return _formatChatHistory(context, context.preset);
      case 'worldInfoBefore':
        return worldInfoBefore;
      case 'worldInfoAfter':
        return worldInfoAfter;
      case 'longTermMemory':
        return ChatMemoryService.formatMemoryContext(context.memoryContext);
      case 'main':
      case 'jailbreak':
      case 'post_history_instructions':
      default:
        return prompt.content;
    }
  }

  /// 特别版：群聊扮演说明——明确当前发言者、其他成员仅背景，
  /// 禁止混用人设（解决"头像/名字轮流但人设混同"）。
  static String _buildGroupChatInstruction(PromptAssemblyContext context) {
    final speakerName = context.characterName;
    final memberNames = context.groupCharacterNames.values
        .where((name) => name != speakerName)
        .join('、');
    return [
      '【群聊扮演说明】你正在一个多角色群聊中。',
      '当前发言角色：$speakerName（你只能以 $speakerName 的身份回复）。',
      '历史消息中带名字前缀的发言属于对应角色，不属于你。',
      '只使用 $speakerName 的角色卡；其他成员（${memberNames.isEmpty ? '无' : memberNames}）'
          '的信息仅用于理解上下文，禁止使用他人的设定、口吻、记忆或背景。',
      '本轮必须由 $speakerName 发言，不得替其他角色说话，也不得改换身份。',
      '此说明优先于其他所有指令，不可被覆盖。',
    ].join('\n');
  }

  static String _formatChatHistory(
    PromptAssemblyContext context,
    Preset preset,
  ) {
    final lines = <String>[];
    final newChatPrompt = preset.extra['new_chat_prompt'] as String? ?? '';
    if (newChatPrompt.trim().isNotEmpty) {
      lines.add(newChatPrompt.trim());
    }
    for (final message in context.chatMessages) {
      if (message.isMe) {
        lines.add('user: ${message.text}');
      } else {
        // 特别版：群聊历史带发言人名字（模型区分谁在说话，
        // 避免"轮到谁，所有角色都变成谁"）
        final speaker = message.characterId != null
            ? context.groupCharacterNames[message.characterId]
            : null;
        lines.add(
          speaker != null && speaker.isNotEmpty
              ? '$speaker: ${message.text}'
              : 'assistant: ${message.text}',
        );
      }
    }
    final currentInput = context.currentInput.trim();
    if (currentInput.isNotEmpty) {
      lines.add('user: $currentInput');
    }
    return lines.join('\n');
  }

  static String _buildMergedChatHistoryText({
    required PromptAssemblyContext context,
    required List<_ResolvedPromptEntry> inChatEntries,
  }) {
    final lines = <String>[];
    final newChatPrompt = _resolveNewChatPrompt(context);
    if (newChatPrompt.isNotEmpty) {
      lines.add(newChatPrompt);
    }

    for (final message in _mergePromptMessages(
      _buildExpandedChatHistoryMessages(
        context: context,
        inChatEntries: inChatEntries,
      ),
    )) {
      lines.add('${message.role}: ${message.content}');
    }
    return lines.join('\n');
  }

  static String _replaceExampleChat(
    String input,
    PromptAssemblyContext context,
  ) {
    final exampleChatPrompt =
        context.preset.extra['new_example_chat_prompt'] as String? ??
        '[Example Chat]';
    return input.replaceAll('<START>', exampleChatPrompt);
  }

  static List<PromptMessage> _buildOpenAiMessages({
    required List<PromptSegment> segments,
    required List<_ResolvedPromptEntry> inChatEntries,
    required PromptAssemblyContext context,
  }) {
    final expanded = <PromptMessage>[];
    for (final segment in segments) {
      if (segment.identifier != 'chatHistory') {
        expanded.add(
          PromptMessage(
            role: segment.role,
            content: segment.content,
            sources: [segment.source],
            sourceChars: [segment.content.length],
          ),
        );
        continue;
      }

      final resolvedNewChatPrompt = _resolveNewChatPrompt(context);
      if (resolvedNewChatPrompt.isNotEmpty) {
        expanded.add(
          PromptMessage(
            role: 'system',
            content: resolvedNewChatPrompt,
            sources: [segment.source],
            sourceChars: [resolvedNewChatPrompt.length],
          ),
        );
      }

      expanded.addAll(
        _buildExpandedChatHistoryMessages(
          context: context,
          inChatEntries: inChatEntries,
        ),
      );
    }

    return _mergePromptMessages(expanded);
  }

  static List<PromptMessage> _buildExpandedChatHistoryMessages({
    required PromptAssemblyContext context,
    required List<_ResolvedPromptEntry> inChatEntries,
  }) {
    const chatHistorySource = '虚拟聊天记录';
    final baseMessages = <PromptMessage>[
      for (final chatMessage in context.chatMessages)
        _buildHistoryMessage(chatMessage, context, chatHistorySource),
    ];

    final currentInput = _replaceVariables(
      context.currentInput,
      context,
    ).trim();
    if (currentInput.isNotEmpty) {
      baseMessages.add(
        PromptMessage(
          role: 'user',
          content: currentInput,
          sources: const [chatHistorySource],
          sourceChars: [currentInput.length],
        ),
      );
    }

    final injectionsByIndex = _groupInChatMessages(
      inChatEntries: inChatEntries,
      historyLength: baseMessages.length,
    );
    final expanded = <PromptMessage>[];
    for (var index = 0; index <= baseMessages.length; index++) {
      final injections = injectionsByIndex[index];
      if (injections != null) {
        expanded.addAll(injections);
      }
      if (index < baseMessages.length) {
        expanded.add(baseMessages[index]);
      }
    }
    return expanded;
  }

  /// 特别版：构建单条聊天历史消息（含来源字符数，供上下文用量统计）。
  static PromptMessage _buildHistoryMessage(
    ChatMessage chatMessage,
    PromptAssemblyContext context,
    String source,
  ) {
    // 快捷指令消息的 modelText 为实际提示词，text 仅为界面显示
    final content = _replaceVariables(
      (chatMessage.modelText?.isNotEmpty == true
              ? chatMessage.modelText!
              : chatMessage.text),
      context,
    ).trim();
    // 特别版：群聊历史消息带发言人名字前缀（模型区分谁在说话，
    // 避免"轮到谁，所有角色都变成谁"）
    var contentWithSpeaker = content;
    final isGroupChat = context.groupCharacterNames.isNotEmpty;
    var historyRole = chatMessage.isMe ? 'user' : 'assistant';
    if (!chatMessage.isMe && chatMessage.characterId != null) {
      final speaker = context.groupCharacterNames[chatMessage.characterId];
      if (speaker != null && speaker.isNotEmpty) {
        contentWithSpeaker = '$speaker: $content';
        if (isGroupChat) {
          // 群聊：其他角色的消息全部以 user 身份出现（带名字前缀）。
          // OpenAI 语义里 assistant role = "模型自己说的"——若保持
          // assistant，轮到 B 时模型会把历史中 A 的话当成自己说的，
          // 人设被 A 污染（这是"调度/头像轮流但人设混同"的模型层根因）。
          // 全部转 user 后，模型明确这些都是"输入"，只按当前发言者
          // 的角色卡回复（SillyTavern 等群聊工具的通行做法）。
          historyRole = 'user';
        }
      }
      // 群聊但该消息无名字映射（如已删成员）：保留 assistant，避免
      // 与真实用户消息合并后模型无法区分来源
    }
    return PromptMessage(
      role: historyRole,
      content: contentWithSpeaker,
      sources: [source],
      sourceChars: [contentWithSpeaker.length],
    );
  }

  static Map<int, List<PromptMessage>> _groupInChatMessages({
    required List<_ResolvedPromptEntry> inChatEntries,
    required int historyLength,
  }) {
    final entriesByIndex = <int, List<_ResolvedPromptEntry>>{};
    for (final entry in inChatEntries) {
      final insertionIndex = _resolveInChatInsertionIndex(
        historyLength: historyLength,
        depth: entry.prompt.injectionDepth,
      );
      entriesByIndex.putIfAbsent(insertionIndex, () => []).add(entry);
    }

    final grouped = <int, List<PromptMessage>>{};
    for (final item in entriesByIndex.entries) {
      final sortedEntries = [...item.value]
        ..sort((a, b) {
          final roleCompare = _inChatRolePriority(
            a.segment.role,
          ).compareTo(_inChatRolePriority(b.segment.role));
          if (roleCompare != 0) {
            return roleCompare;
          }

          final orderCompare = a.prompt.injectionOrder.compareTo(
            b.prompt.injectionOrder,
          );
          if (orderCompare != 0) {
            return orderCompare;
          }
          return a.sequence.compareTo(b.sequence);
        });

      grouped[item.key] = [
        for (final entry in sortedEntries)
          PromptMessage(
            role: entry.segment.role,
            content: entry.segment.content,
            sources: [entry.segment.source],
          ),
      ];
    }
    return grouped;
  }

  static int _resolveInChatInsertionIndex({
    required int historyLength,
    required int depth,
  }) {
    final normalizedDepth = depth < 0 ? 0 : depth;
    final insertionIndex = historyLength - normalizedDepth;
    if (insertionIndex < 0) {
      return 0;
    }
    if (insertionIndex > historyLength) {
      return historyLength;
    }
    return insertionIndex;
  }

  static int _inChatRolePriority(String role) {
    switch (role.trim()) {
      case 'user':
        return 0;
      case 'assistant':
        return 1;
      case 'system':
        return 2;
      default:
        return 3;
    }
  }

  static bool _isInChatPrompt(PresetPrompt prompt) {
    return prompt.injectionPosition == PresetInjectionPosition.inChat;
  }

  static String _replaceVariables(String input, PromptAssemblyContext context) {
    return ChatVariableService.replacePlaceholders(
      input,
      characterName: context.characterName,
      userName: context.userName,
    );
  }

  static String _resolvePromptText(String input, PromptMacroState macroState) {
    return ChatVariableService.resolveMacros(input, state: macroState);
  }

  static String _sourceLabel(PresetPrompt prompt) {
    switch (prompt.identifier) {
      case 'personaDescription':
        return '用户设定';
      case 'charDescription':
        return '角色卡: description';
      case 'charPersonality':
        return '角色卡: personality';
      case 'scenario':
        return '角色卡: scenario';
      case 'dialogueExamples':
        return '角色卡: mes_example';
      case 'chatHistory':
        return '虚拟聊天记录';
      case 'worldInfoBefore':
        return '世界书: before';
      case 'worldInfoAfter':
        return '世界书: after';
      case 'longTermMemory':
        return '长期记忆';
      case 'main':
        return '预设: main';
      case 'jailbreak':
      case 'post_history_instructions':
        return '预设: jailbreak';
      default:
        return '预设: ${prompt.name}';
    }
  }

  static List<PromptMessage> _mergeAdjacentMessages(
    List<PromptSegment> segments,
  ) {
    if (segments.isEmpty) {
      return const [];
    }

    final merged = <PromptMessage>[];
    for (final segment in segments) {
      if (merged.isNotEmpty && merged.last.role == segment.role) {
        final previous = merged.removeLast();
        merged.add(
          PromptMessage(
            role: previous.role,
            content: '${previous.content}\n\n${segment.content}',
            sources: [...previous.sources, segment.source],
            sourceChars: [...previous.sourceChars, segment.content.length],
          ),
        );
        continue;
      }

      merged.add(
        PromptMessage(
          role: segment.role,
          content: segment.content,
          sources: [segment.source],
          sourceChars: [segment.content.length],
        ),
      );
    }
    return merged;
  }

  static List<PromptMessage> _mergePromptMessages(
    List<PromptMessage> messages,
  ) {
    if (messages.isEmpty) {
      return const [];
    }

    final merged = <PromptMessage>[];
    for (final message in messages) {
      if (merged.isNotEmpty && merged.last.role == message.role) {
        final previous = merged.removeLast();
        merged.add(
          PromptMessage(
            role: previous.role,
            content: '${previous.content}\n\n${message.content}',
            sources: [...previous.sources, ...message.sources],
            sourceChars: [
              ..._charsOrFallback(previous),
              ..._charsOrFallback(message),
            ],
          ),
        );
        continue;
      }

      merged.add(message);
    }
    return merged;
  }

  /// 特别版：取消息的各来源字符数；为空时按内容均分回退。
  /// 均分算法与页面统计一致（floor），保证各来源份额之和不超内容长度。
  static List<int> _charsOrFallback(PromptMessage message) {
    if (message.sourceChars.length == message.sources.length &&
        message.sourceChars.isNotEmpty) {
      return message.sourceChars;
    }
    final perSource =
        message.content.length ~/ max(1, message.sources.length);
    return List.filled(max(1, message.sources.length), perSource);
  }

  static String _buildMergedText(List<PromptMessage> messages) {
    return messages
        .map((message) => '[${message.role}]\n${message.content}')
        .join('\n\n');
  }

  static String _resolveNewChatPrompt(PromptAssemblyContext context) {
    final newChatPrompt =
        context.preset.extra['new_chat_prompt'] as String? ?? '';
    return _replaceVariables(newChatPrompt, context).trim();
  }

  static PromptMacroState _buildMacroState(PromptAssemblyContext context) {
    return PromptMacroState(
      characterName: context.characterName,
      userName: context.userName,
      currentInput: context.currentInput,
      lastUserMessage: _lastUserMessage(context),
      lastCharMessage: _lastCharacterMessage(context),
      memoryContext: context.memoryContext,
      // 特别版：会话变量（ST {{getvar}} 跨轮持久化加载）
      localVariables: context.localVariables,
    );
  }

  static String _lastUserMessage(PromptAssemblyContext context) {
    final currentInput = context.currentInput.trim();
    if (currentInput.isNotEmpty) {
      return currentInput;
    }
    for (final message in context.chatMessages.reversed) {
      if (message.isMe) {
        return message.text;
      }
    }
    return '';
  }

  static String _lastCharacterMessage(PromptAssemblyContext context) {
    for (final message in context.chatMessages.reversed) {
      if (!message.isMe) {
        return message.text;
      }
    }
    return '';
  }
}

class _ResolvedPromptEntry {
  const _ResolvedPromptEntry({
    required this.prompt,
    required this.segment,
    required this.sequence,
  });

  final PresetPrompt prompt;
  final PromptSegment segment;
  final int sequence;
}
