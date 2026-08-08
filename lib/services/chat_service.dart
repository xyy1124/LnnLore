import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../data/api_configs.dart';
import '../data/app_settings.dart';
import '../data/mock_user_settings.dart';
import '../models/api_config.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/preset.dart';
import '../models/processed_assistant_output.dart';
import '../models/prompt_assembly.dart';
import '../models/tracker_config.dart';
import '../models/world_book.dart';
import 'chat_character_resolver.dart';
import 'chat_database_service.dart';
import 'chat_display_sanitizer.dart';
import 'chat_memory_service.dart';
import 'chat_variable_service.dart';
import 'storage_service.dart';
import 'tracker_runtime.dart';
import 'deepseek_balance_service.dart';
import 'i_openai_api_service.dart';
import 'openai_compatible_api_service.dart';
import 'preset_service.dart';
import 'prompt_assembler.dart';
import 'thinking_chain_guard.dart';
import 'thinking_chain_preset_service.dart';
import 'world_book_service.dart';

class ChatSendResult {
  const ChatSendResult({
    required this.userNode,
    required this.assistantNode,
    required this.promptAssembly,
    required this.completion,
  });

  /// 特别版：群聊全员回复模式下无用户消息，此字段为 null。
  final ChatNode? userNode;
  final ChatNode assistantNode;
  final PromptAssemblyResult promptAssembly;
  final ChatCompletionResult completion;
}

class ChatService {
  ChatService._();

  static final ChatService instance = ChatService._();

  /// v66：后台裁判轮次令牌——每次发送/重生成/继续递增；后台裁判返回
  /// 时若令牌已过期（用户已发起下一轮），只允许更新旧消息快照，
  /// 不允许覆盖当前会话状态（防旧裁判污染新剧情）。
  /// v70：升级为**按会话串行队列**——下一轮发送前等待上一轮裁判结算
  /// 完成（不再因"裁判返回太晚"丢弃整轮状态）。
  /// v73：令牌改为**按 sessionId 独立计数**——全局整数会串会话
  /// （会话 A 启动裁判 turn=1，切到会话 B 发送 turn=2，A 的裁判返回
  /// 被判过期、A 的状态不更新）；每会话独立递增互不影响。
  final Map<String, int> _trackerJudgeTurns = {};

  int _nextTrackerJudgeTurn(String sessionId) {
    final next = (_trackerJudgeTurns[sessionId] ?? 0) + 1;
    _trackerJudgeTurns[sessionId] = next;
    return next;
  }

  /// v73：该会话当前令牌（判断后台裁判是否过期用）。
  int _currentTrackerJudgeTurn(String sessionId) =>
      _trackerJudgeTurns[sessionId] ?? 0;

  /// v70：每会话的后台裁判任务队列——开始新一轮前 await 上一轮结算，
  /// 保证"正文先显示、状态稍后更新，但用户下次发送前上一轮状态必须
  /// 结算完成"（不丢状态、不覆盖）。
  final Map<String, Future<void>> _pendingTrackerJudges = {};

  /// v70：等待该会话上一轮后台裁判结算完成（无则立即返回）。
  Future<void> _awaitPendingTrackerJudge(String sessionId) async {
    final pending = _pendingTrackerJudges[sessionId];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // 裁判异常不影响新一轮
      }
    }
  }

  /// 特别版：强制思维链的最大自动重试次数（防止模型始终不合规时无限烧 token；
  /// 超过后抛出带原因的异常，用户可点击发送重试）。
  static const int maxThinkingChainRetryAttempts = 10;

  /// 特别版：角色卡预览（诊断日志用，截断超长内容）。
  static String _cardPreview(dynamic cardJson) {
    final raw = cardJson.toString();
    return raw.length > 300 ? raw.substring(0, 300) : raw;
  }

  Future<ChatSendResult> sendMessage({
    required ChatSession session,
    required ResolvedChatCharacter character,
    required List<ChatMessage> chatMessages,
    required String input,
    String? selectedPresetId,
    String? selectedUserSettingId,
    Set<String> selectedWorldBookIds = const <String>{},
    /// 特别版：群聊发言人名字映射（历史消息带发言人前缀）
    Map<String, String> groupCharacterNames = const {},
    bool useStreaming = false,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
    Future<ChatSession> Function()? persistSession,
    void Function(int attempt, String reason)? onThinkingChainRetry,
    /// 特别版：发送给模型的完整内容（快捷指令场景：界面显示 [input]，
    /// 实际送模型的为 [modelText]）
    String? modelText,
    /// 特别版：本地状态解析文本（快捷指令场景：界面 [input] 只是指令名，
    /// 用户补充内容（如"烙印值提高40%"）在 [modelText] 里——必须单独传给
    /// 状态解析器，否则补充的状态变化只送给模型、本地不落地（v49 确认
    /// 的"快捷指令下状态不更新"根因）。为 null 时回退解析 [input]。
    String? trackerText,
    /// 特别版：群聊中本条回复的发言角色 id（assistant 消息归属）
    String? assistantCharacterId,
  }) async {
    final normalizedInput = input.trim();
    if (normalizedInput.isEmpty) {
      throw const FormatException('消息不能为空');
    }

    final config = resolvedSelectedApi;
    if (config == null) {
      throw StateError('当前未选择 API 模型');
    }
    if (config.model.trim().isEmpty) {
      throw const FormatException('当前选中的模型未填写 Model ID');
    }

    final preset = await _resolvePreset(
      selectedPresetId ?? session.selectedPresetId,
    );
    final userSetting = _resolveUserSetting(
      selectedUserSettingId ?? session.selectedUserSettingId,
    );
    final worldBooks = await _loadSelectedWorldBooks(
      selectedWorldBookIds.isNotEmpty
          ? selectedWorldBookIds
          : session.selectedWorldBookIds.toSet(),
    );

    final memoryContext = await _buildMemoryContext(
      sessionId: session.id,
      chatMessages: chatMessages,
    );

    // 特别版：先建立正式会话（草稿 → 真实）再读写变量——否则旁白/
    // 变量会写进草稿 session.id，而 persistSession 创建的是全新 id 的
    // 正式会话，第一轮状态更新会全部丢失（"数值不更新"根因之一）。
    final activeSession = persistSession == null
        ? session
        : await persistSession();

    // 特别版：会话变量（ST {{getvar}} 跨轮持久化加载）——从正式会话
    // id 读取，避免草稿/正式 id 不一致导致变量表错位。
    // v70：会话串行——新一轮开始前等待上一轮后台裁判结算完成
    await _awaitPendingTrackerJudge(session.id);
    var localVariables = await ChatDatabaseService.instance
        .getSessionVariables(activeSession.id);

    final truncatedChatMessages = _truncateChatMessages(chatMessages);

    // 特别版：旁白确定性状态修改（（烙印值+10）（烙印值=35）
    // （黑丝状态=破损）等）——发送时立即应用并持久化，状态栏即时
    // 更新，不依赖模型是否输出状态协议。
    final narrationConfig = TrackerConfig.fromCardJson(character.cardJson);
    // 旁白字段本轮去重：这些字段已确定性落地，模型再输出同字段 patch
    // 会被过滤（防止 20→旁白+10→模型add+10→40 的重复叠加）
    var narrationChanges = <String, (String, bool)>{};
    // 状态解析文本：trackerText（快捷指令补充）优先，否则用户原始输入。
    // 快捷指令场景 [input] 只是指令名（如"旁白"），补充内容（如
    // "烙印值提高40%"）在 [modelText] 里——不单独传的话本地解析器
    // 完全看不到补充，状态不落地（v49 确认的链路断点）。
    final narrationText =
        trackerText?.trim().isNotEmpty == true
            ? trackerText!.trim()
            : input.trim();
    // v47：TRACKER_FLOW 排查日志——一次确认旁白链路到底断在哪一环
    // （tracker 未解析 / 正则没匹配 / SQLite 没写入 / 变量刷新没拿到 /
    // 快照仍用旧值）。装带日志的包后 adb logcat 过滤 [TRACKER_FLOW]。
    debugPrint(
      '[TRACKER_FLOW] session=${activeSession.id} '
      'card=${character.name} '
      'trackerEnabled=${narrationConfig.isEnabled} '
      'schemaKeys=${narrationConfig.stateSchema.keys} '
      'narrationText=${narrationText.length > 40 ? narrationText.substring(0, 40) : narrationText}',
    );
    if (narrationConfig.isEnabled && narrationText.isNotEmpty) {
      narrationChanges =
          TrackerRuntime.parseNarrationStateChanges(narrationText, narrationConfig);
      if (narrationChanges.isNotEmpty) {
        // before：应用前快照（供 TRACKER_FLOW 对比）
        final beforeVariables = Map<String, String>.from(localVariables)
          ..removeWhere((k, _) => k.startsWith('__'));
        final narrationVariables = Map<String, String>.from(localVariables);
        for (final entry in narrationChanges.entries) {
          final key = entry.key;
          final (value, isAdd) = entry.value;
          if (isAdd) {
            final next = TrackerRuntime.reduce(
              current: TrackerRuntime.initState(
                config: narrationConfig,
                existing: narrationVariables,
              ),
              patch: StatePatch(addValues: {key: num.tryParse(value) ?? 0}),
              config: narrationConfig,
            );
            narrationVariables[key] = '${next[key]}';
          } else {
            // = 赋值：number 字段走 reducer（_validate 按 min/max clamp，
            // 避免 （烙印值=999） 直接写入越界值）；string 字段直接写入。
            final schema = narrationConfig.stateSchema[key];
            if (schema != null && schema.isNumber) {
              final next = TrackerRuntime.reduce(
                current: TrackerRuntime.initState(
                  config: narrationConfig,
                  existing: narrationVariables,
                ),
                patch: StatePatch(
                  setValues: {key: num.tryParse(value) ?? 0},
                ),
                config: narrationConfig,
              );
              narrationVariables[key] = '${next[key]}';
            } else {
              narrationVariables[key] = value;
            }
          }
        }
        // v56：状态事务——旁白先在内存应用（模型状态注入/消息快照用），
        // **不立即写库**；模型生成成功、assistant 消息与快照保存后由
        // _processAssistantOutput（baseVariables 基线）一起提交。取消/
        // 失败/崩溃时状态保持原样，不会出现"状态变了但剧情没保存"。
        localVariables = narrationVariables;
        debugPrint('[旁白] 应用状态修改: $narrationChanges');
        debugPrint(
          '[TRACKER_FLOW] narrationApplied=$narrationChanges '
          'before=$beforeVariables '
          'after=${Map<String, String>.from(narrationVariables)..removeWhere((k, _) => k.startsWith('__'))}',
        );
      } else {
        debugPrint('[TRACKER_FLOW] 旁白正则未匹配（输入无（字段+/-/=/值）格式）');
      }
    } else {
      debugPrint(
        '[TRACKER_FLOW] 旁白跳过: trackerEnabled=${narrationConfig.isEnabled} '
        'inputEmpty=${input.trim().isEmpty}',
      );
    }

    final normalizedModelText = modelText?.trim().isNotEmpty == true
        ? modelText!.trim()
        : null;

    // 特别版：群聊诊断日志——确认每次请求实际注入的发言者角色卡
    // （speakerId/name 轮转时 cardHash 也应随之变化；若 hash 不变
    // 说明角色卡注入链路有误）。仅群聊打印；release 构建自动忽略。
    if (groupCharacterNames.isNotEmpty) {
      debugPrint(
        '[GROUP_SEND_SPEAKER_CARD] '
        'speakerId=${character.id}, '
        'speakerName=${character.name}, '
        'cardHash=${character.cardJson.toString().hashCode}, '
        'cardPreview=${_cardPreview(character.cardJson)}',
      );
    }

    final promptAssembly = PromptAssembler.build(
      PromptAssemblyContext(
        characterName: character.name,
        characterCardData: character.cardJson,
        userName: userSetting.name,
        userSettingPrompt: userSetting.prompt,
        preset: preset,
        selectedWorldBooks: worldBooks,
        chatMessages: truncatedChatMessages,
        currentInput: normalizedModelText ?? normalizedInput,
        memoryContext: memoryContext,
        groupCharacterNames: groupCharacterNames,
        localVariables: localVariables,
      ),
    );
    cancellationToken?.throwIfCancelled();

    final userNode = await ChatDatabaseService.instance.appendUserMessage(
      sessionId: activeSession.id,
      parentMessageId: activeSession.currentLeafMessageId,
      text: normalizedInput,
      modelText: normalizedModelText,
    );

    try {
      final completion = await _createCompletion(
        config,
        promptAssembly: promptAssembly,
        preset: preset,
        useStreaming: useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: onStreamProgress,
        enforceThinkingChain: true,
        onThinkingChainRetry: onThinkingChainRetry,
        trackerStateText: _trackerStateText(
          character.cardJson,
          localVariables,
          // v67：注入上一轮 narrative/consequence——状态成为剧情驱动器
          narrative: _previousStoryContextFromHistory(
            chatMessages,
            localVariables,
          ).$1,
          consequence: _previousStoryContextFromHistory(
            chatMessages,
            localVariables,
          ).$2,
          // v70：快速模式=主模型唯一写入者（输出 <TRACKER_UPDATE> 协议）；
          // 后台/严格=主模型只输出正文（状态由裁判决定）
          includeOutputProtocol:
              appSettingsNotifier.value.trackerUpdateMode ==
                  TrackerUpdateMode.quick,
        ),
      );

      // v73：后台/严格模式主模型只输出正文——状态由裁判决定；
      // 快速模式主模型是唯一状态写入者
      final updateMode = appSettingsNotifier.value.trackerUpdateMode;
      final processed = await _processAssistantOutput(
        activeSession.id,
        completion.text,
        cardJson: character.cardJson,
        // 旁白字段本轮去重：模型对这些字段的 set/add 一律忽略
        protectedStateKeys: narrationChanges.keys.toSet(),
        // v56：状态事务——内存基线（含已应用的旁白），模型成功后
        // 与 patch/setvar 一起提交；取消/失败则状态保持原样
        baseVariables: localVariables,
        // v73：后台/严格模式主模型只输出正文——状态由裁判决定
        allowInlineTrackerProtocol:
            updateMode == TrackerUpdateMode.quick,
      );
      // v60/v63：状态裁判——剧情生成后独立判断状态变化并生成本轮
      // 动态解读（narrative）。
      // v66：三档模式——quick（默认）不调裁判直接用主模型 narrative；
      // strict 等待裁判；background 正文先显示、裁判后台补算。
    final turn = _nextTrackerJudgeTurn(activeSession.id);
      (StatePatch, Map<String, String>, Map<String, String>)? judgeResult;
      if (updateMode == TrackerUpdateMode.strict) {
        try {
          judgeResult = await _judgeTrackerState(
            config: config,
            cardJson: character.cardJson,
            variables: processed.finalVariables ?? localVariables,
            userText: normalizedModelText ?? normalizedInput,
            assistantText: processed.displayText,
            cancellationToken: cancellationToken,
            mainPatch: processed.patch,
          );
        } on Object {
          judgeResult = null;
        }
      }
      final judgePatch = judgeResult?.$1;
      // v66：quick/background 用主模型 narrative；strict 用裁判 narrative
      // （裁判未返回时回退主模型 narrative）
      final judgeNarrative =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$2 ?? processed.narrative)
              : processed.narrative;
      // v67：consequence（下一轮剧情影响指令）——同样三档取值
      final judgeConsequence =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$3 ?? processed.consequence)
              : processed.consequence;
      // v69：诊断日志——快速模式看不到更新时，一行确认是哪层失败
      debugPrint(
        '[TRACKER_MODE] mode=$updateMode '
        'mainProtocol=${processed.patch.protocolDetected} '
        'mainPatch=${processed.patch} '
        'mainNarrative=${processed.narrative.keys} '
        'panelDetected=${processed.specialStatusHtml != null} '
        'judgeCalled=${judgeResult != null}',
      );
      final assistantNode = await ChatDatabaseService.instance
          .appendAssistantMessage(
            sessionId: activeSession.id,
            parentMessageId: userNode.id,
            text: processed.displayText,
            characterId: assistantCharacterId,
            isPartial: completion.isPartial,
            thinkingChain: completion.thinkingChain,
          );

      // v58/v63：状态事务提交点——assistant 消息保存成功后才写库。
      // v63：裁判 patch 在候选状态（旁白+主模型 patch）上叠加，不丢
      // 主模型字段；模型回复成功但无任何状态来源时，提交内存中的
      // 旁白状态（用户确定性指令不依赖模型输出）。
      final (finalVars, needCommit) = _applyJudgePatch(
        judgePatch: judgePatch,
        processed: processed,
        localVariables: localVariables,
        cardJson: character.cardJson,
        protectedKeys: narrationChanges.keys.toSet(),
      );
      if (needCommit || narrationChanges.isNotEmpty) {
        await ChatDatabaseService.instance.upsertSessionVariables(
          activeSession.id,
          finalVars,
        );
      }
      // 特别版：本条消息的规范状态快照按消息关联持久化——始终用该
      // 消息处理后的最终变量表 + 角色卡模板生成（JSON-only 回复也
      // 有快照；数值=消息时刻状态，不被后续轮次污染）
      // v65：传入上一轮 narrative 与本轮开始前变量表——未变化字段
      // 继承旧解读，已变化字段强制补齐解读（裁判漏写也不留空白）
      await _persistMessageStatusHtml(
        activeSession.id,
        assistantNode.id,
        character.cardJson,
        finalVars,
        narrative: judgeNarrative,
        previousNarrative: _previousNarrativeFromHistory(
          chatMessages,
          localVariables,
        ),
        beforeVariables: localVariables,
        consequence: judgeConsequence,
      );
      // v66：后台模式——正文已保存显示，裁判在后台补算（轮次令牌
      // 防旧裁判覆盖新状态）
      if (updateMode == TrackerUpdateMode.background) {
        unawaited(
          _runTrackerJudgeInBackground(
            turn: turn,
            config: config,
            cardJson: character.cardJson,
            sessionId: activeSession.id,
            messageId: assistantNode.id,
            processed: processed,
            localVariables: localVariables,
            protectedKeys: narrationChanges.keys.toSet(),
            history: chatMessages,
            userText: normalizedModelText ?? normalizedInput,
            assistantText: processed.displayText,
          ),
        );
      }

      // 特别版：消息动作按钮（模型 choices）挂到该消息下
      if (processed.hasChoices) {
        await ChatDatabaseService.instance.saveMessageChoices(
          assistantNode.id,
          processed.choices.map((c) => c.toJson()).toList(),
        );
      }

      if (!completion.isPartial) {
        unawaited(
          _tryAutoExtractMemories(
            sessionId: activeSession.id,
            branchLeafId: assistantNode.id,
            chatMessages: chatMessages,
            userMessage: ChatMessage(
              id: userNode.id,
              text: userNode.text,
              isMe: true,
            ),
            assistantMessage: ChatMessage(
              id: assistantNode.id,
              text: assistantNode.text,
              isMe: false,
            ),
            characterName: character.name,
            userName: userSetting.name,
            currentInput: userNode.text,
            cardData: _extractCardData(character.cardJson),
          ),
        );
      }

      return ChatSendResult(
        userNode: userNode,
        assistantNode: assistantNode,
        promptAssembly: promptAssembly,
        completion: completion,
      );
    } on ChatCompletionCancelledException {
      rethrow;
    } catch (error) {
      throw StateError('发送聊天请求失败: $error');
    }
  }

  /// 特别版：群聊"全员回复"模式——让 [character] 对当前对话的最后一条
  /// 消息直接回复（不追加用户消息、不注入用户输入）。
  /// 用于全员模式下成员按顺序自动连续发言。
  Future<ChatSendResult> generateGroupReply({
    required ChatSession session,
    required ResolvedChatCharacter character,
    required List<ChatMessage> chatMessages,
    /// 特别版：显式指定本条回复的父消息 id（全员模式第一轮挂在
    /// 上一位发言者的回复下）；缺省时取 [chatMessages] 最后一条。
    String? parentMessageId,
    String? selectedPresetId,
    String? selectedUserSettingId,
    Set<String> selectedWorldBookIds = const <String>{},
    /// 特别版：群聊发言人名字映射（历史消息带发言人前缀）
    Map<String, String> groupCharacterNames = const {},
    bool useStreaming = false,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
    Future<ChatSession> Function()? persistSession,
    void Function(int attempt, String reason)? onThinkingChainRetry,
  }) async {
    final config = resolvedSelectedApi;
    if (config == null) {
      throw StateError('当前未选择 API 模型');
    }
    if (config.model.trim().isEmpty) {
      throw const FormatException('当前选中的模型未填写 Model ID');
    }

    final preset = await _resolvePreset(
      selectedPresetId ?? session.selectedPresetId,
    );
    final userSetting = _resolveUserSetting(
      selectedUserSettingId ?? session.selectedUserSettingId,
    );
    final worldBooks = await _loadSelectedWorldBooks(
      selectedWorldBookIds.isNotEmpty
          ? selectedWorldBookIds
          : session.selectedWorldBookIds.toSet(),
    );
    final memoryContext = await _buildMemoryContext(
      sessionId: session.id,
      chatMessages: chatMessages,
    );

    // v55：先建立正式会话再读变量（与 sendMessage 统一）——草稿场景下
    // session.id 是草稿 id，读到的变量与后续写入的正式会话不一致
    // （新建群聊第一轮会读到空的草稿状态）。
    final activeSession = persistSession == null
        ? session
        : await persistSession();

    // 特别版：会话变量（ST {{getvar}} 跨轮持久化加载）
    // v70：会话串行——新一轮开始前等待上一轮后台裁判结算完成
    await _awaitPendingTrackerJudge(session.id);
    final localVariables = await ChatDatabaseService.instance
        .getSessionVariables(activeSession.id);

    final truncatedChatMessages = _truncateChatMessages(chatMessages);

    // 特别版：群聊诊断日志——全员模式每轮确认注入的发言者角色卡
    debugPrint(
      '[GROUP_GENERATE_CARD] '
      'speakerId=${character.id}, '
      'speakerName=${character.name}, '
      'cardHash=${character.cardJson.toString().hashCode}, '
      'cardPreview=${_cardPreview(character.cardJson)}',
    );

    final promptAssembly = PromptAssembler.build(
      PromptAssemblyContext(
        characterName: character.name,
        characterCardData: character.cardJson,
        userName: userSetting.name,
        userSettingPrompt: userSetting.prompt,
        preset: preset,
        selectedWorldBooks: worldBooks,
        chatMessages: truncatedChatMessages,
        // 群聊轮次发言：无新用户输入，基于上一条消息回复
        currentInput: '',
        memoryContext: memoryContext,
        groupCharacterNames: groupCharacterNames,
        localVariables: localVariables,
      ),
    );
    cancellationToken?.throwIfCancelled();

    try {
      final completion = await _createCompletion(
        config,
        promptAssembly: promptAssembly,
        preset: preset,
        useStreaming: useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: onStreamProgress,
        enforceThinkingChain: true,
        onThinkingChainRetry: onThinkingChainRetry,
        trackerStateText: _trackerStateText(
          character.cardJson,
          localVariables,
          // v67：注入上一轮 narrative/consequence——状态成为剧情驱动器
          narrative: _previousStoryContextFromHistory(
            chatMessages,
            localVariables,
          ).$1,
          consequence: _previousStoryContextFromHistory(
            chatMessages,
            localVariables,
          ).$2,
          // v70：快速模式=主模型唯一写入者（输出 <TRACKER_UPDATE> 协议）；
          // 后台/严格=主模型只输出正文（状态由裁判决定）
          includeOutputProtocol:
              appSettingsNotifier.value.trackerUpdateMode ==
                  TrackerUpdateMode.quick,
        ),
      );

      final updateMode = appSettingsNotifier.value.trackerUpdateMode;
      final processed = await _processAssistantOutput(
        activeSession.id,
        completion.text,
        cardJson: character.cardJson,
        // v73：后台/严格模式主模型只输出正文——状态由裁判决定
        allowInlineTrackerProtocol:
            updateMode == TrackerUpdateMode.quick,
      );
      // v60/v63：状态裁判——群聊剧情后独立判断状态变化并生成解读
      // v66：三档模式（quick 不调裁判/background 后台/strict 等待）
    final turn = _nextTrackerJudgeTurn(activeSession.id);
      (StatePatch, Map<String, String>, Map<String, String>)? judgeResult;
      if (updateMode == TrackerUpdateMode.strict) {
        try {
          judgeResult = await _judgeTrackerState(
            config: config,
            cardJson: character.cardJson,
            variables: processed.finalVariables ?? localVariables,
            userText: '',
            assistantText: processed.displayText,
            cancellationToken: cancellationToken,
            mainPatch: processed.patch,
          );
        } on Object {
          judgeResult = null;
        }
      }
      final judgePatch = judgeResult?.$1;
      final judgeNarrative =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$2 ?? processed.narrative)
              : processed.narrative;
      // v67：consequence（下一轮剧情影响指令）
      final judgeConsequence =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$3 ?? processed.consequence)
              : processed.consequence;
      // v69：诊断日志——快速模式看不到更新时，一行确认是哪层失败
      debugPrint(
        '[TRACKER_MODE] mode=$updateMode '
        'mainProtocol=${processed.patch.protocolDetected} '
        'mainPatch=${processed.patch} '
        'mainNarrative=${processed.narrative.keys} '
        'panelDetected=${processed.specialStatusHtml != null} '
        'judgeCalled=${judgeResult != null}',
      );
      final assistantNode = await ChatDatabaseService.instance
          .appendAssistantMessage(
            sessionId: activeSession.id,
            // 全员模式链式发言：显式指定父消息，保证消息链完整
            parentMessageId:
                parentMessageId ??
                (chatMessages.isNotEmpty
                    ? chatMessages.last.id
                    : null) ??
                activeSession.currentLeafMessageId,
            text: processed.displayText,
            characterId: character.id,
            isPartial: completion.isPartial,
            thinkingChain: completion.thinkingChain,
          );

      // v58/v63：状态事务提交点——assistant 消息保存成功后才写库；
      // 裁判 patch 在候选状态上叠加（不丢主模型字段）
      final (groupFinalVars, groupNeedCommit) = _applyJudgePatch(
        judgePatch: judgePatch,
        processed: processed,
        localVariables: localVariables,
        cardJson: character.cardJson,
        protectedKeys: const {},
      );
      if (groupNeedCommit) {
        await ChatDatabaseService.instance.upsertSessionVariables(
          activeSession.id,
          groupFinalVars,
        );
      }
      // 特别版：本条消息的规范状态快照按消息关联持久化
      // （JSON-only 回复也有快照；数值=消息时刻最终状态）
      // v65：完整 narrative 合并（未变化字段继承旧解读）
      await _persistMessageStatusHtml(
        activeSession.id,
        assistantNode.id,
        character.cardJson,
        groupFinalVars ?? localVariables,
        narrative: judgeNarrative,
        previousNarrative: _previousNarrativeFromHistory(
          chatMessages,
          localVariables,
        ),
        beforeVariables: localVariables,
        consequence: judgeConsequence,
      );
      // v66：后台模式——裁判后台补算（令牌防旧裁判覆盖新状态）
      if (updateMode == TrackerUpdateMode.background) {
        unawaited(
          _runTrackerJudgeInBackground(
            turn: turn,
            config: config,
            cardJson: character.cardJson,
            sessionId: activeSession.id,
            messageId: assistantNode.id,
            processed: processed,
            localVariables: localVariables,
            protectedKeys: const {},
            history: chatMessages,
            userText: '',
            assistantText: processed.displayText,
          ),
        );
      }

      // 特别版：消息动作按钮（模型 choices）挂到该消息下
      if (processed.hasChoices) {
        await ChatDatabaseService.instance.saveMessageChoices(
          assistantNode.id,
          processed.choices.map((c) => c.toJson()).toList(),
        );
      }

      return ChatSendResult(
        userNode: null,
        assistantNode: assistantNode,
        promptAssembly: promptAssembly,
        completion: completion,
      );
    } on ChatCompletionCancelledException {
      rethrow;
    } catch (error) {
      throw StateError('群聊发言生成失败: $error');
    }
  }

  Future<ChatSendResult> regenerateAssistantResponse({
    required ChatSession session,
    required ResolvedChatCharacter character,
    required List<ChatMessage> historyBeforeUserMessage,
    required ChatMessage userMessage,
    String? selectedPresetId,
    String? selectedUserSettingId,
    Set<String> selectedWorldBookIds = const <String>{},
    /// 特别版：群聊发言人名字映射（历史消息带发言人前缀）
    Map<String, String> groupCharacterNames = const {},
    bool useStreaming = false,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
    void Function(int attempt, String reason)? onThinkingChainRetry,
  }) async {
    if (userMessage.id == null) {
      throw StateError('用户消息缺少 ID，无法重新生成');
    }
    if (!userMessage.isMe) {
      throw StateError('只能基于用户消息重新生成回复');
    }

    final config = resolvedSelectedApi;
    if (config == null) {
      throw StateError('当前未选择 API 模型');
    }
    if (config.model.trim().isEmpty) {
      throw const FormatException('当前选中的模型未填写 Model ID');
    }

    final preset = await _resolvePreset(
      selectedPresetId ?? session.selectedPresetId,
    );
    final userSetting = _resolveUserSetting(
      selectedUserSettingId ?? session.selectedUserSettingId,
    );
    final worldBooks = await _loadSelectedWorldBooks(
      selectedWorldBookIds.isNotEmpty
          ? selectedWorldBookIds
          : session.selectedWorldBookIds.toSet(),
    );

    final memoryContext = await _buildMemoryContext(
      sessionId: session.id,
      chatMessages: historyBeforeUserMessage,
    );

    // 特别版：会话变量（ST {{getvar}} 跨轮持久化加载）
    // var：v51 分支回滚后会重新读取恢复后的变量表
    // v70：会话串行——新一轮开始前等待上一轮后台裁判结算完成
    await _awaitPendingTrackerJudge(session.id);
    var localVariables = await ChatDatabaseService.instance
        .getSessionVariables(session.id);

    final truncatedHistory = _truncateChatMessages(historyBeforeUserMessage);

    final userTextForModel = userMessage.modelText?.isNotEmpty == true
        ? userMessage.modelText!
        : userMessage.text;

    // 特别版：重生成旁白去重——原用户消息里的旁白（（烙印值+10）等）
    // 已在首次发送时确定性落地，重生成把原文重新发给模型时，模型若
    // 再次输出同字段 patch 会重复叠加。这里**只解析 keys 不应用**，
    // 用于阻止模型对已落地字段重复更新。
    final regenerateNarrationConfig =
        TrackerConfig.fromCardJson(character.cardJson);
    final regenerateProtectedKeys = regenerateNarrationConfig.isEnabled
        ? TrackerRuntime.parseNarrationStateChanges(
                userTextForModel, regenerateNarrationConfig)
            .keys
            .toSet()
        : <String>{};

    // v51/v55：分支状态回滚（核心修复）——消息树是分支化的，但 tracker
    // 状态是会话级单份全局变量；重生成/编辑重发直接读全局变量会拿到
    // 旧分支推进后的状态（"编辑像新消息"根因）。逻辑抽为公共方法
    // [_restoreTrackerBaselineForHistory]：重生成/编辑重发/继续生成共用。
    if (regenerateNarrationConfig.isEnabled) {
      localVariables = await _restoreTrackerBaselineForHistory(
        sessionId: session.id,
        history: historyBeforeUserMessage,
        userTextForModel: userTextForModel,
        cardJson: character.cardJson,
        currentVariables: localVariables,
        logLabel: '重生成状态回滚',
      );
    }

    final promptAssembly = PromptAssembler.build(
      PromptAssemblyContext(
        characterName: character.name,
        characterCardData: character.cardJson,
        userName: userSetting.name,
        userSettingPrompt: userSetting.prompt,
        preset: preset,
        selectedWorldBooks: worldBooks,
        chatMessages: truncatedHistory,
        currentInput: userTextForModel,
        memoryContext: memoryContext,
        groupCharacterNames: groupCharacterNames,
        localVariables: localVariables,
      ),
    );
    cancellationToken?.throwIfCancelled();

    try {
      final completion = await _createCompletion(
        config,
        promptAssembly: promptAssembly,
        preset: preset,
        useStreaming: useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: onStreamProgress,
        enforceThinkingChain: true,
        onThinkingChainRetry: onThinkingChainRetry,
        trackerStateText: _trackerStateText(
          character.cardJson,
          localVariables,
          // v67：注入上一轮 narrative/consequence——状态成为剧情驱动器
          narrative: _previousStoryContextFromHistory(
            historyBeforeUserMessage,
            localVariables,
          ).$1,
          consequence: _previousStoryContextFromHistory(
            historyBeforeUserMessage,
            localVariables,
          ).$2,
          // v70：快速模式=主模型唯一写入者；后台/严格=只输出正文
          includeOutputProtocol:
              appSettingsNotifier.value.trackerUpdateMode ==
                  TrackerUpdateMode.quick,
        ),
      );

      final updateMode = appSettingsNotifier.value.trackerUpdateMode;
      final processed = await _processAssistantOutput(
        session.id,
        completion.text,
        cardJson: character.cardJson,
        // 原用户消息旁白字段本轮去重（只阻止模型重复更新，不重新应用）
        protectedStateKeys: regenerateProtectedKeys,
        // v73：后台/严格模式主模型只输出正文——状态由裁判决定
        allowInlineTrackerProtocol:
            updateMode == TrackerUpdateMode.quick,
      );
      // v60/v63：状态裁判——重生成剧情后独立判断状态变化并生成解读
      // v66：三档模式（quick 不调裁判/background 后台/strict 等待）
    final turn = _nextTrackerJudgeTurn(session.id);
      (StatePatch, Map<String, String>, Map<String, String>)? judgeResult;
      if (updateMode == TrackerUpdateMode.strict) {
        try {
          judgeResult = await _judgeTrackerState(
            config: config,
            cardJson: character.cardJson,
            variables: processed.finalVariables ?? localVariables,
            userText: userTextForModel,
            assistantText: processed.displayText,
            cancellationToken: cancellationToken,
            mainPatch: processed.patch,
          );
        } on Object {
          judgeResult = null;
        }
      }
      final judgePatch = judgeResult?.$1;
      final judgeNarrative =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$2 ?? processed.narrative)
              : processed.narrative;
      // v67：consequence（下一轮剧情影响指令）
      final judgeConsequence =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$3 ?? processed.consequence)
              : processed.consequence;
      // v69：诊断日志——快速模式看不到更新时，一行确认是哪层失败
      debugPrint(
        '[TRACKER_MODE] mode=$updateMode '
        'mainProtocol=${processed.patch.protocolDetected} '
        'mainPatch=${processed.patch} '
        'mainNarrative=${processed.narrative.keys} '
        'panelDetected=${processed.specialStatusHtml != null} '
        'judgeCalled=${judgeResult != null}',
      );
      final assistantNode = await ChatDatabaseService.instance
          .appendAssistantMessage(
            sessionId: session.id,
            parentMessageId: userMessage.id,
            text: processed.displayText,
            isPartial: completion.isPartial,
            thinkingChain: completion.thinkingChain,
          );

      // v58/v63：状态事务提交点——assistant 消息保存成功后才写库；
      // 裁判 patch 在候选状态上叠加（不丢主模型字段）
      final (branchFinalVars, branchNeedCommit) = _applyJudgePatch(
        judgePatch: judgePatch,
        processed: processed,
        localVariables: localVariables,
        cardJson: character.cardJson,
        protectedKeys: regenerateProtectedKeys,
      );
      if (branchNeedCommit) {
        await ChatDatabaseService.instance.upsertSessionVariables(
          session.id,
          branchFinalVars,
        );
      }
      // 特别版：本条消息的规范状态快照按消息关联持久化
      // （JSON-only 回复也有快照；数值=消息时刻最终状态）
      // v65：完整 narrative 合并（未变化字段继承旧解读）
      await _persistMessageStatusHtml(
        session.id,
        assistantNode.id,
        character.cardJson,
        branchFinalVars ?? localVariables,
        narrative: judgeNarrative,
        previousNarrative: _previousNarrativeFromHistory(
          historyBeforeUserMessage,
          localVariables,
        ),
        beforeVariables: localVariables,
        consequence: judgeConsequence,
      );
      // v66：后台模式——裁判后台补算（令牌防旧裁判覆盖新状态）
      if (updateMode == TrackerUpdateMode.background) {
        unawaited(
          _runTrackerJudgeInBackground(
            turn: turn,
            config: config,
            cardJson: character.cardJson,
            sessionId: session.id,
            messageId: assistantNode.id,
            processed: processed,
            localVariables: localVariables,
            protectedKeys: regenerateProtectedKeys,
            history: historyBeforeUserMessage,
            userText: userTextForModel,
            assistantText: processed.displayText,
          ),
        );
      }

      // 特别版：消息动作按钮（模型 choices）挂到该消息下
      if (processed.hasChoices) {
        await ChatDatabaseService.instance.saveMessageChoices(
          assistantNode.id,
          processed.choices.map((c) => c.toJson()).toList(),
        );
      }

      if (!completion.isPartial) {
        unawaited(
          _tryAutoExtractMemories(
            sessionId: session.id,
            branchLeafId: assistantNode.id,
            chatMessages: historyBeforeUserMessage,
            userMessage: ChatMessage(
              id: userMessage.id,
              text: userMessage.text,
              isMe: true,
            ),
            assistantMessage: ChatMessage(
              id: assistantNode.id,
              text: assistantNode.text,
              isMe: false,
            ),
            characterName: character.name,
            userName: userSetting.name,
            currentInput: userMessage.text,
            cardData: _extractCardData(character.cardJson),
          ),
        );
      }

      return ChatSendResult(
        userNode: ChatNode(
          id: userMessage.id!,
          sessionId: userMessage.sessionId ?? session.id,
          parentId: userMessage.parentId,
          role: ChatNodeRole.user,
          text: userMessage.text,
          createdAt: DateTime.now(),
          siblingOrder: userMessage.index - 1,
        ),
        assistantNode: assistantNode,
        promptAssembly: promptAssembly,
        completion: completion,
      );
    } on ChatCompletionCancelledException {
      rethrow;
    } catch (error) {
      throw StateError('重新生成聊天回复失败: $error');
    }
  }

  /// 继续推进：基于最后一条角色消息生成新的角色消息。
  /// 使用预设中的 `continue_nudge_prompt` 作为继续提示。
  Future<ChatCompletionResult> continueAssistantResponse({
    required ChatSession session,
    required ResolvedChatCharacter character,
    required List<ChatMessage> chatMessages,
    String? selectedPresetId,
    String? selectedUserSettingId,
    Set<String> selectedWorldBookIds = const <String>{},
    /// 特别版：群聊发言人名字映射（历史消息带发言人前缀）
    Map<String, String> groupCharacterNames = const {},
    bool useStreaming = false,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
    void Function(int attempt, String reason)? onThinkingChainRetry,
  }) async {
    if (chatMessages.isEmpty) {
      throw StateError('没有可继续的消息');
    }
    final lastMessage = chatMessages.last;
    if (lastMessage.isMe) {
      throw StateError('只能继续角色消息');
    }
    final lastMessageId = lastMessage.id;
    if (lastMessageId == null) {
      throw StateError('角色消息缺少 ID，无法继续');
    }

    final config = resolvedSelectedApi;
    if (config == null) {
      throw StateError('当前未选择 API 模型');
    }
    if (config.model.trim().isEmpty) {
      throw const FormatException('当前选中的模型未填写 Model ID');
    }

    final preset = await _resolvePreset(
      selectedPresetId ?? session.selectedPresetId,
    );
    final userSetting = _resolveUserSetting(
      selectedUserSettingId ?? session.selectedUserSettingId,
    );
    final worldBooks = await _loadSelectedWorldBooks(
      selectedWorldBookIds.isNotEmpty
          ? selectedWorldBookIds
          : session.selectedWorldBookIds.toSet(),
    );

    final memoryContext = await _buildMemoryContext(
      sessionId: session.id,
      chatMessages: chatMessages,
    );

    // 特别版：会话变量（ST {{getvar}} 跨轮持久化加载）
    // var：v55 分支基线恢复后会重新读取恢复后的变量表
    // v70：会话串行——新一轮开始前等待上一轮后台裁判结算完成
    await _awaitPendingTrackerJudge(session.id);
    var localVariables = await ChatDatabaseService.instance
        .getSessionVariables(session.id);

    // v55：继续生成同样按当前消息链恢复分支基线（与重生成一致）——
    // 否则从记忆树/分支切换后"继续"会从全局最新状态继续，状态错位。
    final continueTrackerConfig = TrackerConfig.fromCardJson(character.cardJson);
    if (continueTrackerConfig.isEnabled) {
      localVariables = await _restoreTrackerBaselineForHistory(
        sessionId: session.id,
        history: chatMessages,
        userTextForModel: '',
        cardJson: character.cardJson,
        currentVariables: localVariables,
        logLabel: '继续生成状态回滚',
      );
    }

    final truncatedChatMessages = _truncateChatMessages(chatMessages);

    final promptAssembly = PromptAssembler.build(
      PromptAssemblyContext(
        characterName: character.name,
        characterCardData: character.cardJson,
        userName: userSetting.name,
        userSettingPrompt: userSetting.prompt,
        preset: preset,
        selectedWorldBooks: worldBooks,
        chatMessages: truncatedChatMessages,
        currentInput: '',
        memoryContext: memoryContext,
        groupCharacterNames: groupCharacterNames,
        localVariables: localVariables,
      ),
    );
    cancellationToken?.throwIfCancelled();

    final continueNudge = ChatVariableService.replacePlaceholders(
      preset.extra['continue_nudge_prompt'] as String? ??
          '[Continue your last message without repeating its original content.]',
      characterName: character.name,
      userName: userSetting.name,
    ).trim();

    final fixedRole = preset.extra['fixed_prompts_role'] as String? ?? 'system';

    final requestMessages = <Map<String, dynamic>>[
      for (final message in promptAssembly.messages)
        {'role': message.role, 'content': message.content},
      if (continueNudge.isNotEmpty)
        {'role': fixedRole, 'content': continueNudge},
    ];

    // 特别版：继续推进同样注入 tracker 状态指令（与普通发送一致），
    // 否则"继续"生成时模型收不到当前状态、也不会输出状态 patch。
    // v50：合并进最后一条 system（与 _createCompletion 一致，见 v50 说明）。
    final trackerState = _trackerStateText(
      character.cardJson,
      localVariables,
      // v67：注入上一轮 narrative/consequence——状态成为剧情驱动器
      narrative: _previousStoryContextFromHistory(
        chatMessages,
        localVariables,
      ).$1,
      consequence: _previousStoryContextFromHistory(
        chatMessages,
        localVariables,
      ).$2,
      // v70：快速模式=主模型唯一写入者；后台/严格=只输出正文
      includeOutputProtocol:
          appSettingsNotifier.value.trackerUpdateMode ==
              TrackerUpdateMode.quick,
    );
    if (trackerState != null && trackerState.trim().isNotEmpty) {
      final systemIdx = requestMessages.lastIndexWhere(
        (m) => m['role'] == 'system',
      );
      if (systemIdx >= 0) {
        requestMessages[systemIdx] = {
          ...requestMessages[systemIdx],
          'content':
              '${requestMessages[systemIdx]['content']}\n\n$trackerState',
        };
      } else {
        requestMessages.insert(0, {'role': 'system', 'content': trackerState});
      }
    }

    try {
      final completion = await _createCompletionFromMessages(
        config,
        messages: requestMessages,
        preset: preset,
        useStreaming: useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: onStreamProgress,
        enforceThinkingChain: true,
        onThinkingChainRetry: onThinkingChainRetry,
      );

      final updateMode = appSettingsNotifier.value.trackerUpdateMode;
      final processed = await _processAssistantOutput(
        session.id,
        completion.text,
        cardJson: character.cardJson,
        // v73：后台/严格模式主模型只输出正文——状态由裁判决定
        allowInlineTrackerProtocol:
            updateMode == TrackerUpdateMode.quick,
      );
      // v60/v63：状态裁判——继续推进剧情后独立判断状态变化并生成解读
      // v66：三档模式（quick 不调裁判/background 后台/strict 等待）
    final turn = _nextTrackerJudgeTurn(session.id);
      (StatePatch, Map<String, String>, Map<String, String>)? judgeResult;
      if (updateMode == TrackerUpdateMode.strict) {
        try {
          judgeResult = await _judgeTrackerState(
            config: config,
            cardJson: character.cardJson,
            variables: processed.finalVariables ?? localVariables,
            userText: '',
            assistantText: processed.displayText,
            cancellationToken: cancellationToken,
            mainPatch: processed.patch,
          );
        } on Object {
          judgeResult = null;
        }
      }
      final judgePatch = judgeResult?.$1;
      final judgeNarrative =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$2 ?? processed.narrative)
              : processed.narrative;
      // v67：consequence（下一轮剧情影响指令）
      final judgeConsequence =
          updateMode == TrackerUpdateMode.strict
              ? (judgeResult?.$3 ?? processed.consequence)
              : processed.consequence;
      // v69：诊断日志——快速模式看不到更新时，一行确认是哪层失败
      debugPrint(
        '[TRACKER_MODE] mode=$updateMode '
        'mainProtocol=${processed.patch.protocolDetected} '
        'mainPatch=${processed.patch} '
        'mainNarrative=${processed.narrative.keys} '
        'panelDetected=${processed.specialStatusHtml != null} '
        'judgeCalled=${judgeResult != null}',
      );
      final assistantNode = await ChatDatabaseService.instance
          .appendAssistantMessage(
        sessionId: session.id,
        parentMessageId: lastMessageId,
        text: processed.displayText,
        isPartial: completion.isPartial,
        thinkingChain: completion.thinkingChain,
      );

      // v58/v63：状态事务提交点——assistant 消息保存成功后才写库；
      // 裁判 patch 在候选状态上叠加（不丢主模型字段）
      final (branchFinalVars, branchNeedCommit) = _applyJudgePatch(
        judgePatch: judgePatch,
        processed: processed,
        localVariables: localVariables,
        cardJson: character.cardJson,
        protectedKeys: const {},
      );
      if (branchNeedCommit) {
        await ChatDatabaseService.instance.upsertSessionVariables(
          session.id,
          branchFinalVars,
        );
      }
      // 特别版：本条消息的规范状态快照按消息关联持久化
      // （JSON-only 回复也有快照；数值=消息时刻最终状态）
      // v65：完整 narrative 合并（未变化字段继承旧解读）
      await _persistMessageStatusHtml(
        session.id,
        assistantNode.id,
        character.cardJson,
        branchFinalVars ?? localVariables,
        narrative: judgeNarrative,
        previousNarrative: _previousNarrativeFromHistory(
          chatMessages,
          localVariables,
        ),
        beforeVariables: localVariables,
        consequence: judgeConsequence,
      );
      // v66：后台模式——裁判后台补算（令牌防旧裁判覆盖新状态）
      if (updateMode == TrackerUpdateMode.background) {
        unawaited(
          _runTrackerJudgeInBackground(
            turn: turn,
            config: config,
            cardJson: character.cardJson,
            sessionId: session.id,
            messageId: assistantNode.id,
            processed: processed,
            localVariables: localVariables,
            protectedKeys: const {},
            history: chatMessages,
            userText: '',
            assistantText: processed.displayText,
          ),
        );
      }

      // 特别版：消息动作按钮（模型 choices）挂到该消息下
      if (processed.hasChoices) {
        await ChatDatabaseService.instance.saveMessageChoices(
          assistantNode.id,
          processed.choices.map((c) => c.toJson()).toList(),
        );
      }

      return completion;
    } on ChatCompletionCancelledException {
      rethrow;
    } catch (error) {
      throw StateError('继续推进失败: $error');
    }
  }

  /// 助手帮答：基于当前对话生成一条用户回复，填入输入框。
  /// 使用预设中的 `impersonation_prompt` 作为扮演提示。不写入数据库。
  Future<String> generateUserReply({
    required ChatSession session,
    required ResolvedChatCharacter character,
    required List<ChatMessage> chatMessages,
    String? selectedPresetId,
    String? selectedUserSettingId,
    Set<String> selectedWorldBookIds = const <String>{},
    /// 特别版：群聊发言人名字映射（历史消息带发言人前缀）
    Map<String, String> groupCharacterNames = const {},
    bool useStreaming = false,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
  }) async {
    final config = resolvedSelectedApi;
    if (config == null) {
      throw StateError('当前未选择 API 模型');
    }
    if (config.model.trim().isEmpty) {
      throw const FormatException('当前选中的模型未填写 Model ID');
    }

    final preset = await _resolvePreset(
      selectedPresetId ?? session.selectedPresetId,
    );
    final userSetting = _resolveUserSetting(
      selectedUserSettingId ?? session.selectedUserSettingId,
    );
    final worldBooks = await _loadSelectedWorldBooks(
      selectedWorldBookIds.isNotEmpty
          ? selectedWorldBookIds
          : session.selectedWorldBookIds.toSet(),
    );

    final memoryContext = await _buildMemoryContext(
      sessionId: session.id,
      chatMessages: chatMessages,
    );

    // 特别版：会话变量（ST {{getvar}} 跨轮持久化加载）
    final localVariables = await ChatDatabaseService.instance
        .getSessionVariables(session.id);

    final truncatedChatMessages = _truncateChatMessages(chatMessages);

    final promptAssembly = PromptAssembler.build(
      PromptAssemblyContext(
        characterName: character.name,
        characterCardData: character.cardJson,
        userName: userSetting.name,
        userSettingPrompt: userSetting.prompt,
        preset: preset,
        selectedWorldBooks: worldBooks,
        chatMessages: truncatedChatMessages,
        currentInput: '',
        memoryContext: memoryContext,
        groupCharacterNames: groupCharacterNames,
        localVariables: localVariables,
      ),
    );
    cancellationToken?.throwIfCancelled();

    final impersonationPrompt = ChatVariableService.replacePlaceholders(
      preset.extra['impersonation_prompt'] as String? ??
          '[Write your next reply from the point of view of {{user}}, using the chat history so far as a guideline for the writing style of {{user}}. Don\'t write as {{char}} or system. Don\'t describe actions of {{char}}.]',
      characterName: character.name,
      userName: userSetting.name,
    ).trim();

    final fixedRole = preset.extra['fixed_prompts_role'] as String? ?? 'system';

    final requestMessages = <Map<String, dynamic>>[
      for (final message in promptAssembly.messages)
        {'role': message.role, 'content': message.content},
      if (impersonationPrompt.isNotEmpty)
        {'role': fixedRole, 'content': impersonationPrompt},
    ];

    try {
      final completion = await _createCompletionFromMessages(
        config,
        messages: requestMessages,
        preset: preset,
        useStreaming: useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: onStreamProgress,
      );
      return completion.text;
    } on ChatCompletionCancelledException {
      rethrow;
    } catch (error) {
      throw StateError('助手帮答失败: $error');
    }
  }

  /// 特别版：解析 AI 回复中的 {{setvar::k::v}} 宏与 Tracker 状态 patch
  /// （JSON patch / <STATE> 块），持久化到会话变量表；返回剥离了
  /// setvar 宏与状态块的显示文本（副作用内容不入库、不显示）。
  /// 重构版：返回 [ProcessedAssistantOutput]（正文 + patch + choices
  /// + 特殊状态栏 HTML + 最终变量表）。
  ///
  /// [protectedStateKeys]：本轮已由旁白确定性修改的字段（用户输入
  /// （烙印值+10）等已落地）。模型若再对同一字段输出 patch 会被过滤，
  /// 防止"旁白 +10 后又叠加模型 +10"（20→30→40）。
  ///
  /// [baseVariables]：v56 状态事务——调用方已在本轮内存中应用了旁白
  /// （未写库），传入它作为 reduce 的基线（否则 _processAssistantOutput
  /// 读库会拿到不含旁白的旧状态，旁白丢失）。不传时读库（重生成/
  /// 继续/群聊等无发送前旁白的路径）。
  Future<ProcessedAssistantOutput> _processAssistantOutput(
    String sessionId,
    String text, {
    Map<String, dynamic>? cardJson,
    Set<String> protectedStateKeys = const {},
    Map<String, String>? baseVariables,
    /// v73：是否允许主模型输出内联状态协议（patch/setvar/STATE/面板
    /// 回写）。快速模式=true（主模型是唯一状态写入者）；后台/严格=false
    /// ——主模型**只输出正文**，任何状态修改都被忽略（状态由独立裁判
    /// 决定，避免两个状态写入者重复增加/冲突）。
    bool allowInlineTrackerProtocol = true,
  }) async {
    // v75：setvar 受 allowInlineTrackerProtocol 控制——后台/严格模式
    // 主模型偷偷输出 {{setvar::}} 时不得修改状态（之前无条件解析，
    // 主模型可绕过裁判改状态/重复增加）
    final calls = allowInlineTrackerProtocol
        ? ChatVariableService.parseSetVarCalls(text)
        : const <(String, String)>[];
    final config = TrackerConfig.fromCardJson(cardJson);
    // v70：提取 <TRACKER_UPDATE> 标记块——正文在标记之前正常输出
    // （不再把长篇剧情塞进 JSON reply），标记内是短状态协议
    final (markerJson, markerDisplayText) =
        TrackerRuntime.extractTrackerUpdateBlock(text);
    // v73：后台/严格模式禁止主模型状态修改——patch 置空（只保留
    // protocolDetected=false 语义），setvar/STATE/面板回写一并忽略
    var patch = allowInlineTrackerProtocol
        ? TrackerRuntime.extractPatch(text)
        : StatePatch();
    // v50：字段名规范化——模型可能输出中文 label（"烙印值"）而非真实
    // key（yw_brand），映射回 key；完全未知字段丢弃（避免被 reducer
    // 当成新变量保存，面板仍读不到）。
    final canonical = TrackerRuntime.canonicalizePatch(patch, config);
    patch = canonical.$1;
    final droppedKeys = canonical.$2;
    if (droppedKeys.isNotEmpty) {
      debugPrint('[TRACKER_RESPONSE] 丢弃未知字段: $droppedKeys');
    }
    // v50/v55：始终打印模型状态诊断——protocolDetected 区分"模型没
    // 输出协议"（protocol=无）与"模型判断无变化"（protocol=有但
    // set/add 为空，即合法空 patch）。
    debugPrint(
      '[TRACKER_RESPONSE] protocol=${patch.protocolDetected ? '有' : '无'} '
      'set=${patch.setValues} add=${patch.addValues} '
      'allowInline=$allowInlineTrackerProtocol',
    );
    // 旁白字段本轮去重：模型对已落地旁白字段的 set/add 一律忽略
    // （其余字段照常应用）。
    if (protectedStateKeys.isNotEmpty) {
      patch = TrackerRuntime.filterProtectedPatch(patch, protectedStateKeys);
    }
    final choices = TrackerRuntime.extractChoices(text);

    // raw 与 reply 都扫：模型输出 {reply, patch} 时状态面板可能在
    // reply 里，也可能在 reply 外（patch 块旁边）。
    final rawExtracted = ChatDisplaySanitizer.extract(text);
    final replyExtracted = patch.reply == null
        ? null
        : ChatDisplaySanitizer.extract(patch.reply!);

    final specialStatusHtml = _nonEmpty(rawExtracted.specialStatusHtml) ??
        _nonEmpty(replyExtracted?.specialStatusHtml);

    var displayText =
        replyExtracted != null && replyExtracted.displayText.trim().isNotEmpty
            ? replyExtracted.displayText
            : rawExtracted.displayText;
    // v70：<TRACKER_UPDATE> 标记前的正文优先（新协议——正文在标记外，
    // 不经过 JSON 转义，解析成功率更高）
    if (markerDisplayText.trim().isNotEmpty) {
      displayText = markerDisplayText;
    }

    // extract 是破坏性拆解器。若误判导致正文为空，遍历候选源
    // （协议 reply 优先、其次原文），跳过纯面板后用恢复函数找回正文；
    // 纯面板（原文内容就是面板本身）保持空（面板 HTML 不应入正文）。
    if (displayText.trim().isEmpty) {
      final fallbackSources = <String>[
        if (patch.reply != null && patch.reply!.trim().isNotEmpty) patch.reply!,
        text,
      ];

      for (final source in fallbackSources) {
        if (ChatDisplaySanitizer.isPurePanelText(source, specialStatusHtml)) {
          continue;
        }

        final recovered =
            ChatDisplaySanitizer.recoverDisplayTextAfterExtraction(
          source,
          specialStatusHtml: specialStatusHtml,
        );

        if (recovered.trim().isNotEmpty) {
          displayText = recovered.trim();
          break;
        }
      }
    }

    // v69：剥离正文末尾的纯文本状态栏——模型可能输出
    // "状态栏：\n堕落进度：27/100\n当前状态：压制中"（无 HTML 变体，
    // 显示层清洗器不识别）。识别规则：末尾、≥2 行命中 tracker label、
    // 每行含冒号。
    // v73：后台/严格模式仍剥离（正文不含状态行），但**不回写变量**——
    // 状态由裁判决定，主模型的面板值不参与 reducer。
    if (config.isEnabled) {
      final plainPanelValues = <String, String>{};
      displayText = TrackerRuntime.stripTrailingPlainTrackerPanel(
        displayText,
        config,
        plainPanelValues: allowInlineTrackerProtocol
            ? plainPanelValues
            : null,
      );
      if (plainPanelValues.isNotEmpty) {
        debugPrint('[TRACKER_RESPONSE] 纯文本状态栏回写: $plainPanelValues');
        // 解析出的 label → 真实 key，走 reducer（canonicalize + clamp）
        final panelSet = StatePatch(setValues: {
          for (final e in plainPanelValues.entries) e.key: e.value,
        });
        final (canonical, _) =
            TrackerRuntime.canonicalizePatch(panelSet, config);
        // 受保护字段（旁白已落地）不覆盖
        final filtered = StatePatch(setValues: {
          for (final e in canonical.setValues.entries)
            if (!protectedStateKeys.contains(e.key)) e.key: e.value,
        });
        if (!filtered.isEmpty) {
          // 只补模型 patch/setvar 未覆盖的字段——面板值通常反映模型
          // 输出的时刻状态，可能比 patch 旧；模型已更新的字段以
          // patch/setvar 为准（避免面板旧值覆盖新 patch）。
          // setvar key 可能为中文 label，先 canonicalize 再对比
          final (canonicalCalls, _) = config.isEnabled
              ? TrackerRuntime.canonicalizePatch(
                  StatePatch(setValues: {
                    for (final (k, v) in calls) k: v,
                  }),
                  config,
                )
              : (
                  StatePatch(setValues: {
                    for (final (k, v) in calls) k: v,
                  }),
                  const <String>[],
                );
          final alreadyCovered = <String>{
            ...patch.setValues.keys,
            ...patch.addValues.keys,
            ...canonicalCalls.setValues.keys,
          };
          final toMerge = <String, String>{
            for (final e in filtered.setValues.entries)
              if (!alreadyCovered.contains(e.key)) e.key: '${e.value}',
          };
          if (toMerge.isNotEmpty) {
            final existingPatch = patch;
            patch = StatePatch(
              setValues: {
                ...existingPatch.setValues,
                ...toMerge,
              },
              addValues: existingPatch.addValues,
              reply: existingPatch.reply,
              protocolDetected: existingPatch.protocolDetected,
            );
            debugPrint(
              '[TRACKER_RESPONSE] 纯文本状态栏合并进 patch: $toMerge',
            );
          }
        }
      }
    }

    // 特别版：诊断日志（定位"状态栏不渲染"用）——装带日志的包后
    // adb logcat 过滤 [状态栏] 即可看到每条回复的提取结果。
    if (specialStatusHtml != null || calls.isNotEmpty || !patch.isEmpty) {
      debugPrint(
        '[状态栏] 原始前300字: ${text.length > 300 ? text.substring(0, 300) : text}',
      );
      debugPrint(
        '[状态栏] 提取: 正文${displayText.length}字 | '
        '面板${specialStatusHtml == null ? "无" : "${specialStatusHtml.length}字: ${specialStatusHtml.length > 100 ? specialStatusHtml.substring(0, 100) : specialStatusHtml}"}',
      );
    }

    // 有副作用（setvar / patch / 状态栏）才读写变量表
    if (calls.isNotEmpty || !patch.isEmpty || specialStatusHtml != null) {
      // 读当前变量 → 应用 setvar 覆盖 + tracker reducer → 写回
      // v56：优先使用调用方传入的内存基线（含已应用的旁白），
      // 否则读库（无发送前旁白的路径）
      final variables = baseVariables != null
          ? Map<String, String>.from(baseVariables)
          : await ChatDatabaseService.instance
                .getSessionVariables(sessionId);
      // v54：setvar 统一经过 tracker 保护与校验——受保护字段（旁白已
      // 落地）过滤；tracker 声明字段走 reducer（类型校验 + clamp）；
      // 其余字段直接写入。之前 setvar 直接覆盖变量表，模型同一轮输出
      // {{setvar::yw_brand::5}} 会把旁白（烙印值+10）已落地的值盖掉。
      // v57：setvar 顺序修正——**先 canonicalize（中文 label → 真实 key）
      // 再过滤受保护字段**。之前先按 protectedStateKeys（真实 key 如
      // yw_brand）过滤，`{{setvar::烙印值::5}}` 里的中文 label 匹配不上
      // 保护集，canonicalize 后仍会覆盖旁白（（烙印值+10））的结果。
      final (canonicalSetVar, _) = config.isEnabled
          ? TrackerRuntime.canonicalizePatch(
              StatePatch(setValues: {
                for (final (k, v) in calls) k: v,
              }),
              config,
            )
          : (
              StatePatch(setValues: {
                for (final (k, v) in calls) k: v,
              }),
              const <String>[],
            );
      final setVarPatch = StatePatch(setValues: {
        for (final e in canonicalSetVar.setValues.entries)
          if (!protectedStateKeys.contains(e.key)) e.key: e.value,
      });
      if (!setVarPatch.isEmpty) {
        if (config.isEnabled) {
          final initialized = TrackerRuntime.initState(
            config: config,
            existing: variables,
          );
          final next = TrackerRuntime.reduce(
            current: initialized,
            patch: setVarPatch,
            config: config,
          );
          variables
            ..clear()
            ..addAll(next.map((k, v) => MapEntry(k, '$v')));
        } else {
          for (final entry in setVarPatch.setValues.entries) {
            variables[entry.key] = '${entry.value}';
          }
        }
      }
      if (calls.length > setVarPatch.setValues.length) {
        debugPrint(
          '[TRACKER_RESPONSE] setvar 受保护字段被过滤: '
          '${calls.map((e) => e.$1).where((k) => protectedStateKeys.contains(k)).join(',')}',
        );
      }
      if (config.isEnabled && !patch.isEmpty) {
        // 先补 initialState（缺失字段），再应用 patch
        final initialized = TrackerRuntime.initState(
          config: config,
          existing: variables,
        );
        final next = TrackerRuntime.reduce(
          current: initialized,
          patch: patch,
          config: config,
        );
        variables
          ..clear()
          ..addAll(next.map((k, v) => MapEntry(k, '$v')));
      }
      // 特殊状态栏 HTML 一并持久化（TrackerStatusBar 优先渲染它）
      if (specialStatusHtml != null) {
        variables[kSpecialStatusHtmlKey] = specialStatusHtml;
        // 模型输出的是面板文本（而非 patch 协议）时，从面板解析
        // `label：值` 回写状态变量——但 **不得覆盖** patch/setvar
        // 已经修改过的字段（否则旧面板会把新 patch 值盖回去）。
        // v55：回写统一走 reducer（canonicalize + clamp）——之前直接
        // variables[e.key] = e.value，模型输出"烙印值：999/100"会把
        // 999 绕过 min/max 直接入库。
        // v75：HTML 面板回写仅快速模式允许——后台/严格模式主模型
        // 的面板值不得参与状态（状态由裁判决定），只保留 HTML 供显示
        if (config.isEnabled && allowInlineTrackerProtocol) {
          final protectedKeys = <String>{
            for (final (k, _) in calls) k,
            ...patch.setValues.keys,
            ...patch.addValues.keys,
          };
          final parsed = TrackerRuntime.extractValuesFromPanelText(
            specialStatusHtml,
            config,
          );
          final panelSet = StatePatch(setValues: {
            for (final e in parsed.entries)
              if (!protectedKeys.contains(e.key)) e.key: e.value,
          });
          if (!panelSet.isEmpty) {
            final initialized = TrackerRuntime.initState(
              config: config,
              existing: variables,
            );
            final (canonical, _) =
                TrackerRuntime.canonicalizePatch(panelSet, config);
            final next = TrackerRuntime.reduce(
              current: initialized,
              patch: canonical,
              config: config,
            );
            variables
              ..clear()
              ..addAll(next.map((k, v) => MapEntry(k, '$v')));
          }
        }
      }
      // v58：**此处不写库**——_processAssistantOutput 为纯计算（解析 +
      // 应用 setvar/patch/面板回写），最终变量表由调用方在 assistant
      // 消息保存成功后才统一提交（状态事务：消息保存失败/取消时状态
      // 不会单独前进）。
      return ProcessedAssistantOutput(
        displayText: displayText,
        patch: patch,
        choices: choices,
        specialStatusHtml: specialStatusHtml,
        // 本轮处理后的最终变量表（含 setvar/patch 应用后的状态），
        // 供调用方生成该消息的规范状态快照（快照值=消息时最终状态）。
        finalVariables: variables,
        // v66：主模型 narrative——快速模式直接使用（单次 API），
        // 后台/严格模式作为裁判未返回时的兜底
        narrative: TrackerRuntime.canonicalizeNarrative(
          TrackerRuntime.extractNarrative(text),
          config,
        ),
        // v67：主模型 consequence（下一轮剧情影响指令）
        consequence: TrackerRuntime.canonicalizeNarrative(
          TrackerRuntime.extractConsequence(text),
          config,
        ),
      );
    }
    return ProcessedAssistantOutput(
      displayText: displayText,
      patch: patch,
      choices: choices,
      specialStatusHtml: specialStatusHtml,
      // v66：主模型 narrative（无副作用路径也提取——正文可能带协议块）
      narrative: TrackerRuntime.canonicalizeNarrative(
        TrackerRuntime.extractNarrative(text),
        config,
      ),
      // v67：主模型 consequence
      consequence: TrackerRuntime.canonicalizeNarrative(
        TrackerRuntime.extractConsequence(text),
        config,
      ),
    );
  }

  /// 去空：null / 全空白返回 null。
  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  /// 消息级状态快照的变量表 key（按消息 id 关联，气泡内跟随渲染）。
  /// v3：结构化状态 JSON（`{"yw_brand":30,"yw_cloth":"完好",...}`）——
  /// 只保存该消息时刻的**状态值**，不保存预渲染 HTML。显示时由气泡用
  /// 消息对应角色卡 + post_history_instructions 的 HTML 模板动态渲染，
  /// 好处：
  /// - 样式始终来自当前角色卡模板（改模板提取规则无需迁移历史数据）；
  /// - 数值保持消息当时的状态（历史消息不被最新状态污染）。
  /// v2（`__msg_status_html_v2__:<id>`）与 v1（`__msg_status_html__:<id>`）
  /// 是预渲染 HTML 快照（含错误纯文本模板生成的面板），v47 起不再写入、
  /// 显示层不再读取（旧数据忽略）。
  static String messageStatusHtmlKey(String messageId) =>
      '__msg_tracker_state_v3__:$messageId';

  /// 把本条消息的**结构化状态快照**（v3）持久化到会话变量表：
  /// 保存该消息处理后的最终 tracker 状态值（JSON），不保存 HTML——
  /// - 模型只输出 JSON patch（无 HTML）时也会生成快照（不再缺失）；
  /// - 快照数值 = 消息当时的最终状态，历史消息不会被后续轮次的最新
  ///   状态污染；面板样式由显示层按当前卡模板动态生成。
  /// 卡未启用/无 tracker 字段时不写入。
  /// v4 快照 key：结构化状态 + 本轮动态解读（narrative）。
  static String messageStatusSnapshotV4Key(String messageId) =>
      '__msg_tracker_state_v4__:$messageId';

  /// v67 快照 key：结构化状态 + narrative + consequence（下一轮剧情影响
  /// 指令）——v5 结构是 v4 的超集（多了 consequence），读取时 v5 优先、
  /// v4 回退。
  static String messageStatusSnapshotV5Key(String messageId) =>
      '__msg_tracker_state_v5__:$messageId';

  Future<void> _persistMessageStatusHtml(
    String sessionId,
    String messageId,
    Map<String, dynamic>? cardJson,
    Map<String, String>? finalVariables, {
    /// v63：本轮动态解读（状态裁判生成，按字段）——写入 v4 快照，
    /// 历史消息显示消息时刻的解读，不随后续轮次漂移。
    Map<String, String>? narrative,
    /// v65：上一条角色消息的完整 narrative（继承用——未变化字段且
    /// 裁判没有新解读时沿用上一轮解读，不整包覆盖成 partial）。
    Map<String, String>? previousNarrative,
    /// v65：本轮开始前的变量表（计算 changedKeys 用）。
    Map<String, String>? beforeVariables,
    /// v67：本轮 consequence（下一轮剧情影响指令，按字段）——写入 v5
    /// 快照，下一轮主模型读取并作为剧情约束。
    Map<String, String>? consequence,
  }) async {
    if (finalVariables == null) {
      return;
    }
    final config = TrackerConfig.fromCardJson(cardJson);
    if (!config.isEnabled) {
      return;
    }
    // 只保存 tracker 声明的字段（排除 __ 内部变量与无关变量）
    final trackerKeys = <String>{
      ...config.stateSchema.keys,
      ...config.initialState.keys,
    };
    if (trackerKeys.isEmpty) {
      return;
    }
    final state = <String, dynamic>{
      for (final key in trackerKeys)
        if (finalVariables[key]?.trim().isNotEmpty == true)
          key: finalVariables[key]!,
    };
    if (state.isEmpty) {
      return;
    }
    // v65：合并完整 narrative——已变化字段必须有解读（裁判新解读优先、
    // 漏写回退新阶段静态描述、连静态也没有则确定性兜底）；未变化字段
    // 且裁判没有新解读时继承上一轮（不再整包覆盖成 partial）。
    var completeNarrative = narrative;
    if (narrative != null && beforeVariables != null) {
      completeNarrative = TrackerRuntime.mergeNarrative(
        previousNarrative: previousNarrative ?? const <String, String>{},
        judgeNarrative: narrative,
        beforeVariables: beforeVariables,
        afterVariables: finalVariables,
        config: config,
      );
    }
    // v67：consequence 合并——已变化字段必须有影响指令（裁判漏写回退
    // 该字段 narrative；都没有则确定性兜底），未变化字段继承上一轮。
    var completeConsequence = consequence;
    if (consequence != null && beforeVariables != null) {
      final changed = TrackerRuntime.changedKeys(
        before: beforeVariables,
        after: finalVariables,
        config: config,
      );
      final merged = Map<String, String>.from(consequence);
      for (final key in changed) {
        if (merged[key]?.trim().isNotEmpty == true) {
          continue;
        }
        final narrativeFallback = completeNarrative?[key]?.trim();
        if (narrativeFallback != null && narrativeFallback.isNotEmpty) {
          merged[key] = narrativeFallback;
          continue;
        }
        final schema = config.stateSchema[key];
        final label = schema?.label.trim().isNotEmpty == true
            ? schema!.label.trim()
            : key;
        merged[key] =
            '下一轮剧情中继续体现$label的当前状态（${finalVariables[key]}），'
            '除非剧情中发生明确的反转事件。';
      }
      completeConsequence = merged;
    }
    final v5Payload = <String, dynamic>{
      'state': state,
      if (completeNarrative != null && completeNarrative.isNotEmpty)
        'narrative': completeNarrative,
      if (completeConsequence != null && completeConsequence.isNotEmpty)
        'consequence': completeConsequence,
    };
    await ChatDatabaseService.instance.upsertSessionVariables(sessionId, {
      messageStatusHtmlKey(messageId): jsonEncode(state),
      // v63：有动态解读时写 v4 快照（state + narrative），显示层优先 v4
      if (completeNarrative != null && completeNarrative.isNotEmpty)
        messageStatusSnapshotV4Key(messageId): jsonEncode({
          'state': state,
          'narrative': completeNarrative,
        }),
      // v67：v5 快照（state + narrative + consequence）——下一轮注入用
      if (v5Payload.length > 1)
        messageStatusSnapshotV5Key(messageId): jsonEncode(v5Payload),
    });
  }

  /// v65：从历史中取上一条角色消息的完整 narrative（v4/v5 快照的
  /// narrative 部分）——倒序找最近一条带快照的角色消息。
  /// 无则返回空表（合并时全部依赖本轮解读/静态回退）。
  Map<String, String> _previousNarrativeFromHistory(
    List<ChatMessage> history,
    Map<String, String> variables,
  ) {
    return _previousStoryContextFromHistory(history, variables).$1;
  }

  /// v67：从历史中取上一条角色消息的完整叙事上下文——倒序找最近一条
  /// 带 v4/v5 快照的角色消息，返回其 (narrative, consequence)。
  /// narrative 解释"当前状态为什么形成"，consequence 说明"该状态下一轮
  /// 应如何影响角色行为"——两者注入下一轮主模型，让状态成为剧情驱动器。
  /// 无则返回空表。
  (Map<String, String>, Map<String, String>)
      _previousStoryContextFromHistory(
    List<ChatMessage> history,
    Map<String, String> variables,
  ) {
    for (final msg in history.reversed) {
      if (msg.isMe || msg.id == null) {
        continue;
      }
      final raw = variables[messageStatusSnapshotV5Key(msg.id!)] ??
          variables[messageStatusSnapshotV4Key(msg.id!)];
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          continue;
        }
        final narrative = <String, String>{};
        final rawNarrative = decoded['narrative'];
        if (rawNarrative is Map) {
          rawNarrative.forEach((k, v) {
            if (k is String && v is String && v.trim().isNotEmpty) {
              narrative[k] = v.trim();
            }
          });
        }
        final consequence = <String, String>{};
        final rawConsequence = decoded['consequence'];
        if (rawConsequence is Map) {
          rawConsequence.forEach((k, v) {
            if (k is String && v is String && v.trim().isNotEmpty) {
              consequence[k] = v.trim();
            }
          });
        }
        if (narrative.isNotEmpty || consequence.isNotEmpty) {
          return (narrative, consequence);
        }
      } catch (_) {
        // 快照解析失败跳过
      }
    }
    return (const <String, String>{}, const <String, String>{});
  }

  /// 特别版：生成 Tracker 状态自然文本（无卡声明时返回 null）。
  /// 追加"回复末尾必须输出结构化状态协议"的指令——模型输出 patch 后，
  /// App 解析应用、再按角色卡模板渲染面板，状态更新才能闭环。
  /// ⚠️ 只读取 stateSchema/initialState 声明的 key，彻底排除 `__` 开头
  ///    的内部变量（__special_status_html__ / __msg_tracker_state_v3__:* 等）——
  ///    否则历史状态快照会被当成"当前状态"重新注入模型。
  String? _trackerStateText(
    Map<String, dynamic>? cardJson,
    Map<String, String> variables, {
    /// v67：上一轮完整 narrative（状态裁判/主模型生成的动态解读）——
    /// 注入下一轮主模型，让状态成为"剧情驱动器"而非"事后记录器"。
    Map<String, String> narrative = const {},
    /// v67：上一轮 consequence（下一轮剧情影响指令）。
    Map<String, String> consequence = const {},
    /// v70：是否要求主模型输出状态协议——快速模式 true（主模型是唯一
    /// 状态写入者，末尾 <TRACKER_UPDATE> 标记块）；后台/严格模式 false
    /// （主模型只输出正文，状态由独立裁判决定——单一写入者，避免主
    /// 模型 patch 与裁判 patch 相互覆盖/重复增加）。
    bool includeOutputProtocol = false,
  }) {
    final config = TrackerConfig.fromCardJson(cardJson);
    if (!config.isEnabled) {
      return null;
    }
    final trackerKeys = <String>{
      ...config.stateSchema.keys,
      ...config.initialState.keys,
    };
    if (trackerKeys.isEmpty) {
      return null;
    }
    final existingState = <String, String>{
      for (final key in trackerKeys)
        if (variables[key]?.trim().isNotEmpty == true) key: variables[key]!,
    };
    final state = existingState.isEmpty
        ? config.initialState.map((k, v) => MapEntry(k, '$v'))
        : existingState;
    final text = TrackerRuntime.formatTrackerInstruction(
      state: Map<String, dynamic>.from(state),
      config: config,
    );
    if (text.isEmpty) {
      return null;
    }
    // v67：注入上一轮动态解读（narrative）与剧情影响指令（consequence）——
    // 模型下一轮不只读到"压制中"标签，还读到"反抗正在失去效果"与
    // "除非成功脱身，否则保持行动受限"等剧情约束，正文才能持续体现状态。
    final parts = <String>[text];
    final narrativeLines = <String>[];
    for (final entry in narrative.entries) {
      if (entry.value.trim().isEmpty) {
        continue;
      }
      final label = config.stateSchema[entry.key]?.label ?? entry.key;
      narrativeLines.add('- $label：${entry.value.trim()}');
    }
    if (narrativeLines.isNotEmpty) {
      parts.add('[当前状态在剧情中的具体表现]\n${narrativeLines.join('\n')}');
    }
    final consequenceLines = <String>[];
    for (final entry in consequence.entries) {
      if (entry.value.trim().isEmpty) {
        continue;
      }
      final label = config.stateSchema[entry.key]?.label ?? entry.key;
      consequenceLines.add('- $label：${entry.value.trim()}');
    }
    if (consequenceLines.isNotEmpty) {
      parts.add('[状态对下一轮剧情的约束]\n${consequenceLines.join('\n')}');
    }
    parts.add(TrackerRuntime.kTrackerStoryInfluenceSuffix);
    // v70：按模式选择输出协议——快速=内联 <TRACKER_UPDATE> 协议
    // （主模型唯一写入者）；后台/严格=只输出正文（裁判决定状态）
    parts.add(
      includeOutputProtocol
          ? TrackerRuntime.kInlineTrackerProtocolSuffix
          : TrackerRuntime.kStoryOnlySuffix,
    );
    return parts.join('\n\n');
  }

  /// v51：从消息历史恢复 tracker 基线状态——倒序找最近一条角色消息的
  /// v3 结构化状态快照（`__msg_tracker_state_v3__:<id>`，该消息处理完成
  /// 时的状态）；无快照（如纯开场消息）回退 initialState。
  /// 用于重生成/编辑重发前把状态恢复到"被编辑消息之前"的分支时刻，
  /// 避免新分支从旧分支推进后的状态继续（v51 确认的"编辑像新消息"根因）。
  Map<String, dynamic> _trackerBaselineFromHistory(
    List<ChatMessage> history,
    Map<String, String> variables,
    TrackerConfig config,
  ) {
    for (final msg in history.reversed) {
      if (msg.isMe || msg.id == null) {
        continue;
      }
      final raw = variables[messageStatusHtmlKey(msg.id!)];
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final state = <String, dynamic>{
            for (final e in decoded.entries)
              if (e.key is String) e.key as String: e.value,
          };
          if (state.isNotEmpty) {
            return state;
          }
        }
      } catch (_) {
        // 坏快照跳过，继续找更早的角色消息
      }
    }
    return config.initialState.map((k, v) => MapEntry(k, '$v'));
  }

  /// v55：按历史消息链恢复 tracker 基线并应用本条用户消息的旁白——
  /// 重生成/编辑重发/继续生成共用（v51 的 regenerate 回滚逻辑抽公共）。
  /// ① 从历史恢复基线（最近角色消息 v3 快照，无快照用 initialState）
  /// ② 重新应用 [userTextForModel] 的旁白修改（继续生成为空则只恢复）
  /// ③ replace 写入（清除旧分支存在、当前分支不存在的 tracker 字段）
  /// 返回恢复后的变量表（调用方应替换本地引用）。
  Future<Map<String, String>> _restoreTrackerBaselineForHistory({
    required String sessionId,
    required List<ChatMessage> history,
    required String userTextForModel,
    required Map<String, dynamic>? cardJson,
    required Map<String, String> currentVariables,
    String logLabel = '分支状态回滚',
  }) async {
    final config = TrackerConfig.fromCardJson(cardJson);
    if (!config.isEnabled) {
      return currentVariables;
    }
    final baseline = _trackerBaselineFromHistory(
      history,
      currentVariables,
      config,
    );
    final narrationChanges = TrackerRuntime.parseNarrationStateChanges(
      userTextForModel,
      config,
    );
    final startingState = TrackerRuntime.applyNarrationChanges(
      baseline,
      narrationChanges,
      config,
    );
    final trackerKeys = <String>{
      ...config.stateSchema.keys,
      ...config.initialState.keys,
    };
    final replaced = Map<String, String>.from(currentVariables);
    for (final key in trackerKeys) {
      final v = startingState[key];
      if (v != null) {
        replaced[key] = '$v';
      } else {
        replaced.remove(key);
      }
    }
    await ChatDatabaseService.instance.replaceSessionVariables(
      sessionId,
      replaced,
      replaceKeys: trackerKeys,
    );
    final refreshed = await ChatDatabaseService.instance
        .getSessionVariables(sessionId);
    debugPrint(
      '[TRACKER_FLOW] $logLabel: baseline=$baseline '
      'narration=$narrationChanges -> ${startingState}',
    );
    return refreshed;
  }

  // ---- v60：状态裁判（双阶段剧情自主判断）----

  /// 裁判开关设置键（默认开启）。
  static const String kJudgeEnabledKey = 'tracker_judge_enabled';
  /// 裁判模式设置键：explicit | conservative | active（默认 conservative）。
  static const String kJudgeModeKey = 'tracker_judge_mode';

  static Future<bool> isTrackerJudgeEnabled() async {
    final saved = StorageService.instance.getBool(kJudgeEnabledKey);
    return saved ?? true;
  }

  static Future<String> getTrackerJudgeMode() async {
    final saved = StorageService.instance.getString(kJudgeModeKey);
    if (saved != null && (saved == 'explicit' || saved == 'active')) {
      return saved;
    }
    return 'conservative';
  }

  /// 状态裁判：剧情生成后**独立调用一次**，返回 JSON patch 与本轮
  /// 动态解读（narrative）与下一轮剧情影响（consequence）。
  /// 返回 null 表示未启用 / 卡无 tracker / 请求失败（不影响主流程——
  /// 状态保持主模型 patch 结果）。
  /// v66：[mainPatch] 为主模型本轮已输出的 patch——裁判不得重复叠加
  /// 同一事件（主模型已更新字段裁判不得再加）；[userText]/[assistantText]
  /// 会被裁剪（裁判只需判断状态变化，不需要读整篇长文）。
  /// v67：返回三元组 (patch, narrative, consequence)。
  Future<(StatePatch, Map<String, String>, Map<String, String>)?>
      _judgeTrackerState({
    required ResolvedApiConfig config,
    required Map<String, dynamic>? cardJson,
    required Map<String, String> variables,
    required String userText,
    required String assistantText,
    ChatCompletionCancelToken? cancellationToken,
    StatePatch? mainPatch,
  }) async {
    // v68：不再检查旧 tracker_judge_enabled 总开关——是否调用裁判已由
    // TrackerUpdateMode（quick/background/strict）决定，隐藏旧开关不能
    // 拥有第二次否决权（旧开关曾关闭的升级用户，后台/严格模式会失效）。
    final trackerConfig = TrackerConfig.fromCardJson(cardJson);
    if (!trackerConfig.isEnabled) {
      return null;
    }
    final trackerKeys = <String>{
      ...trackerConfig.stateSchema.keys,
      ...trackerConfig.initialState.keys,
    };
    final state = <String, dynamic>{
      for (final key in trackerKeys)
        if (variables[key]?.trim().isNotEmpty == true) key: variables[key]!,
    };
    final stateText = TrackerRuntime.formatTrackerInstruction(
      state: state.isEmpty
          ? trackerConfig.initialState.map((k, v) => MapEntry(k, '$v'))
          : state,
      config: trackerConfig,
    );
    if (stateText.isEmpty) {
      return null;
    }
    final mode = await getTrackerJudgeMode();
    final modeDesc = switch (mode) {
      'explicit' => '只处理明确状态描述；不因剧情自行推断',
      'active' => '允许根据整体剧情主动调整状态',
      _ => '只从非常明确的剧情结果推断小幅变化；普通对话/心理描写/重复描述不更新',
    };
    // v66：正文裁剪——裁判只需判断状态变化，不需要读整篇长文
    // （用户消息最多 1000 字、角色回复最多 3000 字，命中语义关键词的
    // 段落优先保留）
    final trimmedUserText = TrackerRuntime.selectRelevantText(
      userText,
      config: trackerConfig,
      maxChars: 1000,
    );
    final trimmedAssistantText = TrackerRuntime.selectRelevantText(
      assistantText,
      config: trackerConfig,
      maxChars: 3000,
    );
    // v66：主模型已更新的字段——裁判不得重复叠加同一事件
    final mainPatchKeys = <String>{
      if (mainPatch != null) ...mainPatch.setValues.keys,
      if (mainPatch != null) ...mainPatch.addValues.keys,
    };
    final mainPatchNote = mainPatchKeys.isEmpty
        ? ''
        : '主模型本轮已经通过 patch 更新了以下字段：'
            '${mainPatchKeys.join('，')}。\n'
            '这些字段的状态变化已经由主模型表达——裁判对它们'
            '不得再次增加（避免同一事件叠加两次）；'
            '若裁判认为主模型的更新方向/幅度不准确，可以对它们'
            '使用 set 直接修正为最终值，或不再返回这些字段。\n';
    final prompt = '$stateText\n\n'
        '（你是状态裁判，只负责根据剧情判断状态变化并生成本轮解读。\n'
        '本轮用户消息：\n$trimmedUserText\n\n'
        '本轮角色回复：\n$trimmedAssistantText\n\n'
        '判断规则（mode=$mode）：$modeDesc。\n'
        '剧情明确表示某字段上升或下降时，即使没有具体数字，也必须按 '
        'qualitative 中最匹配的程度词输出增量（下降用负数）；'
        '每轮增量不超过 maxAutoDeltaPerTurn（未声明则不限制）；'
        '同一事件每轮最多更新一次，只有本轮新发生的事件才能触发变化。\n'
        '$mainPatchNote'
        '语义提示（positive/negative/neutral）用于理解每个字段在剧情中的'
        '含义与通常影响方向——neutral 中列举的行为（普通闲聊/重复描写等）'
        '不得触发变化。\n'
        '输出格式（只输出 JSON 代码块，不要任何解释文字）：\n'
        '```json\n'
        '{\n'
        '  "patch": {\n'
        '    "set": {},\n'
        '    "add": {}\n'
        '  },\n'
        '  "narrative": {},\n'
        '  "consequence": {}\n'
        '}\n'
        '```\n'
        'number 字段增减写入 add（例如 "add":{"字段key":2}）；'
        'string 字段变化写入 set（例如 "set":{"字段key":"新状态"}）。\n'
        'narrative 是"当前状态为什么形成"的解读；consequence 是"该状态'
        '下一轮应如何影响角色行为"（持续状态的保持要求/反转条件）。\n'
        '【v70 可选最终状态】也可以输出 "state" 字段直接给出本轮结束后'
        '全部字段的最终值（{"state":{"字段key":最终值}}）——App 检测到 '
        'state 时按最终值一次性保存（不再叠加）；未输出 state 时仍用 '
        'patch 增量。\n'
        '没有实质变化时输出 {"patch":{"set":{},"add":{}}}，可只带 '
        'narrative/consequence。）\n'
        '【v65 强制规则】narrative 必须包含以下字段：\n'
        '1. patch.set 中的全部字段；\n'
        '2. patch.add 中的全部字段；\n'
        '3. 主模型已经修改的全部候选字段（对比上方 current 与本轮剧情）；\n'
        '4. 数值没有变化但本轮剧情含义明显改变的字段。\n'
        '凡是状态值发生变化的字段，禁止省略 narrative，禁止返回空字符串。\n'
        'narrative 只能使用字段 key（禁止使用中文 label/别名）。\n'
        '【v67 强制规则】consequence 与 narrative 覆盖相同的字段集合——'
        'narrative 解释状态为什么形成，consequence 说明下一轮正文应如何'
        '持续体现该状态（行动限制/心理反应/连续状态保持/反转条件）。';
    try {
      // v66：裁判专用精简预设——temperature 0、关闭思维链约束
      // （裁判只需 JSON，不需要长篇回复或思考链）。
      // v68：maxTokens 动态分配——patch+narrative+consequence 三件套
      // 在字段多时 256 tokens 会被截断（isPartial → 直接 null → 模式
      // 失效）；按字段数分配 (384 + 字段数*128)，钳到 512-1024。
      final basePreset = await _resolvePreset(null);
      final judgeMaxTokens =
          (384 + trackerConfig.stateSchema.length * 128).clamp(512, 1024);
      final preset = basePreset.copyWith(
        openaiMaxTokens: judgeMaxTokens,
        temperature: 0,
      );
      // v68：截断/解析失败补救一次——第一次被 maxTokens 截断时，
      // 第二次要求压缩并重新输出合法 JSON；仍失败才保留主模型结果
      for (var attempt = 0; attempt < 2; attempt++) {
        final completion = await _createCompletionFromMessages(
          config,
          messages: [
            {'role': 'system', 'content': prompt},
            if (attempt > 0)
              {
                'role': 'user',
                'content': '上次输出被截断或不是合法 JSON。'
                    '请只输出一个完整的 JSON 代码块，压缩文字，'
                    '确保 "patch"/"narrative"/"consequence" 都在同一个 '
                    'JSON 对象内且 JSON 语法合法。',
              }
            else
              {'role': 'user', 'content': '根据以上规则输出状态 patch 与解读。'},
          ],
          preset: preset,
          useStreaming: false,
          cancellationToken: cancellationToken,
          enforceThinkingChain: false,
        );
        if (completion.isPartial && attempt == 0) {
          debugPrint(
            '[TRACKER_JUDGE] 裁判输出被截断（maxTokens=$judgeMaxTokens），'
            '重试压缩输出…',
          );
          continue; // 截断 → 第二次重试
        }
        var patch = TrackerRuntime.extractPatch(completion.text);
        // v70：裁判可选输出最终状态 "state" 字段——检测到则按最终值
        // 一次性 set（不再增量叠加，避免"主+裁判重复增加"）。
        // v73：state 存在时**完全忽略 patch.add**——模型同时返回
        // {"state":{"like":30},"patch":{"add":{"like":5}}} 时，若保留
        // add 会在 set 30 之后再 +5 变成 35（与"一次性保存"注释矛盾）。
        final finalState = TrackerRuntime.extractFinalState(
          completion.text,
          trackerConfig,
        );
        if (finalState.isNotEmpty) {
          patch = StatePatch(
            setValues: finalState,
            addValues: const {},
            reply: patch.reply,
            protocolDetected: true,
          );
          debugPrint(
            '[TRACKER_JUDGE] 裁判输出最终状态 state=$finalState '
            '（按 set 一次性保存，忽略 patch.add）',
          );
        }
        // v65：narrative key 规范化——模型可能用中文 label/别名作键，
        // 统一映射回真实 key（patch 规范化与 narrative 规范化同一映射）
        final narrative = TrackerRuntime.canonicalizeNarrative(
          TrackerRuntime.extractNarrative(completion.text),
          trackerConfig,
        );
        // v67：consequence 同样规范化（narrative 与 consequence 共用
        // canonicalizeNarrative——都是"字段 → 文本"映射）
        final consequence = TrackerRuntime.canonicalizeNarrative(
          TrackerRuntime.extractConsequence(completion.text),
          trackerConfig,
        );
        debugPrint(
          '[TRACKER_JUDGE] mode=$mode attempt=${attempt + 1} '
          'patch=$patch narrative=$narrative consequence=$consequence',
        );
        // v68：无协议（patch 未检测到）也视为失败——第二次重试
        if (!patch.protocolDetected && attempt == 0) {
          debugPrint('[TRACKER_JUDGE] 裁判未输出合法协议，重试…');
          continue;
        }
        return (patch, narrative, consequence);
      }
      debugPrint(
        '[TRACKER_JUDGE] 裁判两次尝试均失败（截断/非法 JSON），'
        '保留主模型结果',
      );
      return null;
    } on Object catch (error) {
      // 裁判失败不影响主流程（状态保持主模型 patch 结果）
      debugPrint('[TRACKER_JUDGE] 裁判请求失败（忽略）: $error');
      return null;
    }
  }

  /// v63：应用裁判 patch——**在候选状态上叠加**（candidateState =
  /// 旁白 + 主模型 patch，即 processed.finalVariables）。
  ///
  /// v60 曾以"旁白基线"重新应用裁判 patch（裁判优先、忽略主模型
  /// patch），导致：裁判看到的状态（含主模型 patch）与实际应用基线
  /// 不一致（原始 20 → 主 +3 → 裁判看到 23 → 裁判 +2 → 基线 20+2=22，
  /// 丢 +3）；且主模型更新多个字段时裁判只返回一个 → 其余字段丢失。
  /// 现在裁判基于候选状态判断，其增量在候选状态上叠加（23+2=25），
  /// 主模型 patch 字段全部保留。
  /// 裁判 patch 同样过滤旁白受保护字段。
  /// 返回 (最终变量表, 是否需要提交)。
  (Map<String, String>, bool) _applyJudgePatch({
    required StatePatch? judgePatch,
    required ProcessedAssistantOutput processed,
    required Map<String, String> localVariables,
    required Map<String, dynamic>? cardJson,
    required Set<String> protectedKeys,
  }) {
    var finalVars = processed.finalVariables ?? localVariables;
    var needCommit = processed.finalVariables != null;
    if (judgePatch == null || judgePatch.isEmpty) {
      return (finalVars, needCommit);
    }
    final judgeConfig = TrackerConfig.fromCardJson(cardJson);
    if (!judgeConfig.isEnabled) {
      return (finalVars, needCommit);
    }
    final judgeFiltered = TrackerRuntime.filterProtectedPatch(
      judgePatch,
      protectedKeys,
    );
    // v63：在候选状态（已含主模型 patch）上叠加裁判增量
    finalVars = TrackerRuntime.applyPatchToVariables(
      variables: finalVars,
      patch: judgeFiltered,
      config: judgeConfig,
    );
    needCommit = true;
    return (finalVars, needCommit);
  }

  /// v66：后台状态裁判——正文已保存并显示后异步补算状态与解读。
  ///
  /// 流程：正文先显示（用户不等第二次请求）→ 后台调用裁判 → 完成后
  /// 更新该消息的 v4/v5 快照（state + narrative/consequence 合并）与
  /// 当前会话变量。
  /// v70：**按会话串行**——任务注册进 [_pendingTrackerJudges]，下一轮
  /// 发送前 [_awaitPendingTrackerJudge] 等待结算完成（不再因裁判返回太
  /// 晚丢弃整轮状态）；轮次令牌保留作过期兜底（极端情况下只更新旧
  /// 消息快照）。
  Future<void> _runTrackerJudgeInBackground({
    required int turn,
    required ResolvedApiConfig config,
    required Map<String, dynamic>? cardJson,
    required String sessionId,
    required String messageId,
    required ProcessedAssistantOutput processed,
    required Map<String, String> localVariables,
    required Set<String> protectedKeys,
    required List<ChatMessage> history,
    required String userText,
    required String assistantText,
  }) async {
    // v70：整个裁判任务注册进会话队列——下一轮发送前会被等待
    final task = _runTrackerJudgeTask(
      turn: turn,
      config: config,
      cardJson: cardJson,
      sessionId: sessionId,
      messageId: messageId,
      processed: processed,
      localVariables: localVariables,
      protectedKeys: protectedKeys,
      history: history,
      userText: userText,
      assistantText: assistantText,
    );
    _pendingTrackerJudges[sessionId] = task;
    await task;
    // 队列清理：仅当仍是本任务时移除（避免误删新一轮任务）
    if (identical(_pendingTrackerJudges[sessionId], task)) {
      _pendingTrackerJudges.remove(sessionId);
    }
  }

  /// v70：后台裁判任务本体（被 [ _runTrackerJudgeInBackground] 包装进
  /// 会话队列）。
  Future<void> _runTrackerJudgeTask({
    required int turn,
    required ResolvedApiConfig config,
    required Map<String, dynamic>? cardJson,
    required String sessionId,
    required String messageId,
    required ProcessedAssistantOutput processed,
    required Map<String, String> localVariables,
    required Set<String> protectedKeys,
    required List<ChatMessage> history,
    required String userText,
    required String assistantText,
  }) async {
    // 后台裁判失败/未启用不影响已显示的正文（状态保持主模型结果）
    final judgeResult = await _judgeTrackerState(
      config: config,
      cardJson: cardJson,
      variables: processed.finalVariables ?? localVariables,
      userText: userText,
      assistantText: assistantText,
      mainPatch: processed.patch,
    );
    if (judgeResult == null) {
      return;
    }
    final judgePatch = judgeResult.$1;
    final judgeNarrative = judgeResult.$2;
    final judgeConsequence = judgeResult.$3;
    // v73：按会话令牌判断——不同会话的裁判互不影响（全局令牌会
    // 串会话：会话 A 裁判返回时若 B 已发送，A 被判过期）
    final isCurrentTurn = turn == _currentTrackerJudgeTurn(sessionId);
    if (isCurrentTurn) {
      // 当前轮：裁判 patch 在候选状态上叠加 → 更新会话变量 + 快照
      final (finalVars, needCommit) = _applyJudgePatch(
        judgePatch: judgePatch,
        processed: processed,
        localVariables: localVariables,
        cardJson: cardJson,
        protectedKeys: protectedKeys,
      );
      if (needCommit) {
        await ChatDatabaseService.instance.upsertSessionVariables(
          sessionId,
          finalVars,
        );
      }
      await _persistMessageStatusHtml(
        sessionId,
        messageId,
        cardJson,
        finalVars,
        narrative: judgeNarrative,
        previousNarrative: _previousNarrativeFromHistory(history, localVariables),
        beforeVariables: localVariables,
        consequence: judgeConsequence,
      );
      debugPrint(
        '[TRACKER_JUDGE] 后台裁判完成（当前轮）：patch=$judgePatch '
        'vars=$finalVars',
      );
    } else {
      // 令牌过期（下一轮已开始）：只更新旧消息快照，不碰当前会话变量
      await _persistMessageStatusHtml(
        sessionId,
        messageId,
        cardJson,
        processed.finalVariables ?? localVariables,
        narrative: judgeNarrative,
        previousNarrative: _previousNarrativeFromHistory(history, localVariables),
        beforeVariables: localVariables,
        consequence: judgeConsequence,
      );
      debugPrint(
        '[TRACKER_JUDGE] 后台裁判过期丢弃（turn=$turn '
        '当前=${_currentTrackerJudgeTurn(sessionId)}）'
        '：仅更新旧消息快照',
      );
    }
  }

  Future<Preset> _resolvePreset(String? presetId) async {
    if (presetId != null && presetId.trim().isNotEmpty) {
      final preset = await PresetService.instance.loadById(presetId);
      if (preset != null) {
        return preset;
      }
    }

    final fallback = await PresetService.instance.loadDefaultPreset();
    if (fallback != null) {
      return fallback;
    }
    throw StateError('未找到可用预设');
  }

  UserSetting _resolveUserSetting(String? userSettingId) {
    final settings = userSettingsNotifier.value;
    if (settings.isEmpty) {
      return defaultUserSettings.first;
    }

    if (userSettingId != null) {
      for (final item in settings) {
        if (item.id == userSettingId) {
          return item;
        }
      }
    }

    return settings.first;
  }

  Future<List<WorldBook>> _loadSelectedWorldBooks(Set<String> ids) async {
    if (ids.isEmpty) {
      return const [];
    }

    final books = <WorldBook>[];
    for (final id in ids) {
      final book = await WorldBookService.instance.loadById(id);
      if (book != null) {
        books.add(book);
      }
    }
    return books;
  }

  Future<ChatCompletionResult> _createCompletion(
    ResolvedApiConfig config, {
    required PromptAssemblyResult promptAssembly,
    required Preset preset,
    required bool useStreaming,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
    bool enforceThinkingChain = false,
    void Function(int attempt, String reason)? onThinkingChainRetry,
    /// 特别版：Tracker 状态自然文本（追加到 system 段）
    String? trackerStateText,
  }) async {
    var requestMessages = [
      for (final message in promptAssembly.messages)
        {'role': message.role, 'content': message.content},
    ];

    // 特别版：状态注入——合并进**最后一条** system 消息（v50 修正：
    // 独立追加末尾 system 对部分 OpenAI 兼容接口/本地模板不稳定，模型
    // 可能忽略末尾突兀的 system；合并到最后一条 system 既不靠近开头
    // 被角色卡/预设内容冲淡，也保持消息结构稳定）。没有 system 时
    // 插入到最前。
    if (trackerStateText != null && trackerStateText.trim().isNotEmpty) {
      final systemIdx = requestMessages.lastIndexWhere(
        (m) => m['role'] == 'system',
      );
      if (systemIdx >= 0) {
        requestMessages[systemIdx] = {
          ...requestMessages[systemIdx],
          'content':
              '${requestMessages[systemIdx]['content']}\n\n$trackerStateText',
        };
      } else {
        requestMessages.insert(
          0,
          {'role': 'system', 'content': trackerStateText},
        );
      }
    }

    return _createCompletionFromMessages(
      config,
      messages: requestMessages,
      preset: preset,
      useStreaming: useStreaming,
      cancellationToken: cancellationToken,
      onStreamProgress: onStreamProgress,
      enforceThinkingChain: enforceThinkingChain,
      onThinkingChainRetry: onThinkingChainRetry,
    );
  }

  /// 在请求消息列表最前面注入【强制思维模式】模板（作为固定 system 指令），
  /// 并在消息尾部追加轻量提醒。
  ///
  /// [template] 为当前选中的思维链约束方案模板（特别版可配置）。
  /// 模板位于所有消息之前（先于角色卡/世界书/预设，保证最高优先级）；
  /// 尾部提醒紧跟在最后一条消息之后，确保每次回复都再次被提示。
  static List<Map<String, dynamic>> _injectThinkingChainTemplate(
    List<Map<String, dynamic>> messages,
    String template,
  ) {
    return [
      {'role': 'system', 'content': template.trim()},
      ...messages,
      {
        'role': 'system',
        'content': ThinkingChainGuard.thinkingChainTailReminder,
      },
    ];
  }

  /// 以独立 system 消息注入逐级强化的强制指令（第 [attempt] 次重试）。
  ///
  /// 独立成一条短消息（紧跟模板之后），比追加到模板尾部更醒目，
  /// 模型不易忽略。
  static List<Map<String, dynamic>> _injectThinkingChainRetryInstruction(
    List<Map<String, dynamic>> messages,
    int attempt,
    String reason,
  ) {
    final instruction = ThinkingChainGuard.buildRetryInstruction(
      attempt,
      reason,
    );
    return [
      messages.first,
      {'role': 'system', 'content': instruction},
      ...messages.skip(1),
    ];
  }

  /// 单次补全请求（不做思维链重试）。
  ///
  /// [enforceThinkingChain] 为 true 时，流式输出在累积到阈值（200~300 token）
  /// 处检查是否以 `<think>` 开头，流结束/非流式完成后检查模板完整性，
  /// 违规抛出 [ThinkingChainViolationException]。
  Future<ChatCompletionResult> _createCompletionOnce(
    ResolvedApiConfig config, {
    required List<Map<String, dynamic>> messages,
    required Preset preset,
    required bool useStreaming,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
    bool enforceThinkingChain = false,
  }) async {
    final api = GetIt.instance<IOpenAiApiService>();
    // 特别版：DeepSeek 官方端点判断（host 精确匹配）
    final isDeepSeek = DeepSeekBalanceService.isDeepSeekEndpoint(config.baseUrl);
    // 特别版：DeepSeek 原生 thinking 开启时用宽松校验（自由推理不承诺 12 步标题），
    // 防止最多 10 次退回重试烧 token。
    final deepSeekThinkingMode = appSettingsNotifier.value.deepSeekThinkingMode;
    final nativeThinking =
        isDeepSeek && deepSeekThinkingMode != DeepSeekThinkingMode.disabled;
    if (!useStreaming) {
      final completion = await api.createChatCompletion(
        config,
        messages: messages,
        defaults: buildCompletionDefaults(
          preset,
          useStreaming: false,
          isDeepSeek: isDeepSeek,
          deepSeekThinkingMode: deepSeekThinkingMode,
        ),
        cancellationToken: cancellationToken,
      );
      if (enforceThinkingChain) {
        final violation = nativeThinking
            ? ThinkingChainGuard.validateCompleteLenient(
                completion.text,
                completion.thinkingChain ?? '',
              )
            : ThinkingChainGuard.validateCompleteAny(
                completion.text,
                completion.thinkingChain ?? '',
              );
        if (violation != null) {
          throw ThinkingChainViolationException(violation);
        }
      }
      return completion;
    }

    final textBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    var checkpointChecked = false;
    String? violation;
    // 特别版：流式最后 chunk 携带的真实用量（stream_options 开启时）
    ChatCompletionUsage? streamUsage;
    try {
      await for (final progress
          in api.createStreamingChatCompletion(
            config,
            messages: messages,
            defaults: buildCompletionDefaults(
              preset,
              useStreaming: true,
              isDeepSeek: isDeepSeek,
              deepSeekThinkingMode: deepSeekThinkingMode,
            ),
            cancellationToken: cancellationToken,
          )) {
        if (progress.textDelta.isNotEmpty) {
          textBuffer.write(progress.textDelta);
        }
        if (progress.thinkingDelta.isNotEmpty) {
          thinkingBuffer.write(progress.thinkingDelta);
        }
        if (progress.usage != null && progress.usage!.totalTokens > 0) {
          streamUsage = progress.usage;
        }
        onStreamProgress?.call(progress);

        if (enforceThinkingChain && violation == null) {
          final text = textBuffer.toString();
          final thinking = thinkingBuffer.toString();
          if (!checkpointChecked &&
              (text.length + thinking.length) >=
                  ThinkingChainGuard.thresholdToChars(
                    ThinkingChainGuard.defaultCheckThresholdTokens,
                  )) {
            checkpointChecked = true;
            violation = nativeThinking
                ? ThinkingChainGuard.validateAtCheckpointLenient(thinking)
                : ThinkingChainGuard.validateAtCheckpointAny(text, thinking);
          }
          if (violation == null && progress.done) {
            violation = nativeThinking
                ? ThinkingChainGuard.validateCompleteLenient(text, thinking)
                : ThinkingChainGuard.validateCompleteAny(text, thinking);
          }
        }
        if (violation != null) {
          // 中断订阅：生成器 finally 会关闭底层连接；不调用 cancel token，
          // 避免污染用户取消标志（重试循环仍需复用该 token 检查停止）。
          break;
        }
      }
    } on ChatCompletionCancelledException {
      // 用户主动停止：保留已输出的部分内容（停止≠违规）。
      // 部分思考链/正文仅作展示，不入库为完整回复；
      // 什么都不输出时保持取消语义。
      final partialText = textBuffer.toString().trim();
      final partialThinking = thinkingBuffer.toString().trim();
      if (partialText.isEmpty && partialThinking.isEmpty) {
        rethrow;
      }
      return ChatCompletionResult(
        text: partialText,
        thinkingChain: partialThinking.isEmpty ? null : partialThinking,
        isPartial: true,
      );
    }

    if (violation == null && enforceThinkingChain) {
      // 流自然结束（无 [DONE]）时补一次完整性校验。
      violation = nativeThinking
          ? ThinkingChainGuard.validateCompleteLenient(
              textBuffer.toString(),
              thinkingBuffer.toString(),
            )
          : ThinkingChainGuard.validateCompleteAny(
              textBuffer.toString(),
              thinkingBuffer.toString(),
            );
    }
    if (violation != null) {
      throw ThinkingChainViolationException(violation);
    }

    final text = textBuffer.toString().trim();
    if (text.isEmpty) {
      throw const FormatException('聊天接口返回了空回复');
    }
    final thinking = thinkingBuffer.toString().trim();
    return ChatCompletionResult(
      text: text,
      thinkingChain: thinking.isEmpty ? null : thinking,
      usageTokens: streamUsage,
    );
  }

  /// 带强制思维链的补全请求：注入模板、校验，违规则自动重试直到成功或用户取消。
  ///
  /// 每次违规都会生成逐级强化的强制指令并重新发起请求（退回/摧毁循环）；
  /// 用户在 UI 点击停止（cancel token）可随时终止循环。
  Future<ChatCompletionResult> _createCompletionFromMessages(
    ResolvedApiConfig config, {
    required List<Map<String, dynamic>> messages,
    required Preset preset,
    required bool useStreaming,
    ChatCompletionCancelToken? cancellationToken,
    void Function(ChatCompletionProgress progress)? onStreamProgress,
    bool enforceThinkingChain = false,
    void Function(int attempt, String reason)? onThinkingChainRetry,
  }) async {
    if (!enforceThinkingChain) {
      return _createCompletionOnce(
        config,
        messages: messages,
        preset: preset,
        useStreaming: useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: onStreamProgress,
      );
    }
    if (!appSettingsNotifier.value.enableThinkingChainGuard) {
      // 设置中关闭了思维链约束：模板与尾部提醒仍注入（模型仍被要求
      // 按 12 步模板思考），但不校验、不退回——AI 自由输出，用户可自行
      // 查看思考链是否合规。
      final activeTemplate = await ThinkingChainPresetService.instance
          .resolveActiveTemplate();
      final guidedMessages = _injectThinkingChainTemplate(
        messages,
        activeTemplate,
      );
      return _createCompletionOnce(
        config,
        messages: guidedMessages,
        preset: preset,
        useStreaming: useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: onStreamProgress,
      );
    }

    var attempt = 0;
    var transientRetries = 0;
    final activeTemplate = await ThinkingChainPresetService.instance
        .resolveActiveTemplate();
    var requestMessages = _injectThinkingChainTemplate(messages, activeTemplate);
    while (true) {
      cancellationToken?.throwIfCancelled();
      try {
        return await _createCompletionOnce(
          config,
          messages: requestMessages,
          preset: preset,
          useStreaming: useStreaming,
          cancellationToken: cancellationToken,
          onStreamProgress: onStreamProgress,
          enforceThinkingChain: true,
        );
      } on ThinkingChainViolationException catch (error) {
        attempt++;
        // 用户点停止则终止重试循环（抛 ChatCompletionCancelledException）。
        cancellationToken?.throwIfCancelled();
        if (attempt > maxThinkingChainRetryAttempts) {
          throw StateError(
            '已连续 $attempt 次输出未按强制思维链格式（最后一次原因：${error.reason}）。'
            '已停止自动重试，可点击发送重新尝试。',
          );
        }
        onThinkingChainRetry?.call(
          attempt,
          '输出未按思维链格式（第 $attempt 次强制），已退回重写：${error.reason}',
        );
        requestMessages = _injectThinkingChainRetryInstruction(
          requestMessages,
          attempt,
          error.reason,
        );
      } on HttpException catch (error) {
        // 503/429/5xx 等瞬时服务端错误：退避重试，不消耗思维链重试次数。
        cancellationToken?.throwIfCancelled();
        if (!_isTransientHttpError(error.message) ||
            transientRetries >= maxTransientRetryAttempts) {
          rethrow;
        }
        transientRetries++;
        onThinkingChainRetry?.call(
          transientRetries,
          '服务端繁忙（HTTP ${_extractHttpStatus(error.message)}），'
          '${2 * transientRetries} 秒后自动重试',
        );
        await Future<void>.delayed(
          Duration(seconds: 2 * transientRetries),
        );
        // 等待期间用户可能已点停止。
        cancellationToken?.throwIfCancelled();
      }
    }
  }

  /// 特别版：瞬时服务端错误（503/429/5xx）的最大自动重试次数。
  static const int maxTransientRetryAttempts = 3;

  /// 判断是否为可重试的瞬时服务端错误。
  static bool _isTransientHttpError(String message) {
    return message.contains('HTTP 429') ||
        message.contains('HTTP 5') ||
        message.contains('HTTP 503') ||
        message.contains('HTTP 504');
  }

  /// 从错误消息中提取 HTTP 状态码（如 '请求失败，HTTP 503: ...' → '503'）。
  static String _extractHttpStatus(String message) {
    final match = RegExp(r'HTTP (\d{3})').firstMatch(message);
    return match?.group(1) ?? '未知';
  }

  List<ChatMessage> _truncateChatMessages(List<ChatMessage> messages) {
    return ChatMemoryService.truncateToRecentRounds(
      messages,
      memoryExtractionNotifier.value.recentRounds,
    );
  }

  Future<List<String>> _buildMemoryContext({
    required String sessionId,
    required List<ChatMessage> chatMessages,
  }) async {
    final memoryConfig = memoryExtractionNotifier.value;
    if (!memoryConfig.enabled) return const [];

    final pathIds = chatMessages
        .where((m) => m.id != null)
        .map((m) => m.id!)
        .toList();
    if (pathIds.isEmpty) return const [];

    final memories = await ChatMemoryService.instance.getRecentBranchMemories(
      sessionId: sessionId,
      pathMessageIds: pathIds,
      count: memoryConfig.recallCount,
    );
    return memories.map((m) => m.content).toList();
  }

  Future<void> _tryAutoExtractMemories({
    required String sessionId,
    required String branchLeafId,
    required List<ChatMessage> chatMessages,
    required ChatMessage userMessage,
    required ChatMessage assistantMessage,
    required String characterName,
    required String userName,
    required String currentInput,
    required Map<String, String> cardData,
  }) async {
    final memoryConfig = memoryExtractionNotifier.value;
    if (!memoryConfig.enabled) return;
    if (memoryConfig.interval <= 0) return;

    final allMessages = [...chatMessages, userMessage, assistantMessage]
        // 部分输出（用户中途停止）不参与记忆提取
        .where((m) => !m.isPartial)
        .toList();
    final pathIds = chatMessages
        .where((m) => m.id != null)
        .map((m) => m.id!)
        .toList();
    final newAssistantCount = await _countNewAssistantSinceLastExtraction(
      sessionId: sessionId,
      allMessages: allMessages,
      pathIds: pathIds,
    );
    if (newAssistantCount < memoryConfig.interval) return;

    await ChatMemoryService.instance.tryExtractAndSave(
      sessionId: sessionId,
      branchLeafId: branchLeafId,
      messages: allMessages,
      characterName: characterName,
      userName: userName,
      currentInput: currentInput,
      cardData: cardData,
    );
  }

  Future<int> _countNewAssistantSinceLastExtraction({
    required String sessionId,
    required List<ChatMessage> allMessages,
    required List<String> pathIds,
  }) async {
    final memories = await ChatMemoryService.instance.getBranchMemories(
      sessionId: sessionId,
      pathMessageIds: pathIds,
    );
    // 明确"真实完成的助手回复"：非用户消息且已持久化（id 非空），
    // 排除开场消息/未完成的占位消息等非回复内容。
    final assistantReplies =
        allMessages.where((m) => !m.isMe && m.id != null).toList();
    if (memories.isEmpty) {
      return assistantReplies.length;
    }
    // 合并**所有**记忆的 sourceMessageIds（不只最新一条）：
    // 最新一条记忆可能是手动添加（sourceMessageIds 为空），
    // 只看它会导致去重失效、每次都触发提取。
    final processedIds = <String>{};
    for (final memory in memories) {
      processedIds.addAll(memory.sourceMessageIds);
    }
    return assistantReplies
        .where((m) => !processedIds.contains(m.id))
        .length;
  }

  /// 构建请求默认参数。
  ///
  /// DeepSeek 官方端点（[isDeepSeek]）走原生 thinking mode：
  /// - [deepSeekThinkingMode] 非 disabled：传 `thinking: {type: enabled}` + `reasoning_effort`
  /// - disabled：传 `thinking: {type: disabled}`
  /// - 官方文档明确 thinking mode 下 temperature/top_p/presence/frequency 不生效，故不传
  ///
  /// 非 DeepSeek 端点保持原行为（preset.extra['enable_reasoning'] 兼容路径，
  /// reasoning_effort 默认 high——medium 不在 DeepSeek 官方取值内）。
  @visibleForTesting
  Map<String, dynamic> buildCompletionDefaults(
    Preset preset, {
    required bool useStreaming,
    // 特别版：DeepSeek 官方端点与思考档位
    bool isDeepSeek = false,
    DeepSeekThinkingMode deepSeekThinkingMode = DeepSeekThinkingMode.max,
  }) {
    // DeepSeek thinking mode：thinking/reasoning_effort 只对官方端点传；
    // 官方文档明确 temperature/top_p 等在 thinking mode 下不生效，故不传。
    if (isDeepSeek) {
      final effort = deepSeekThinkingMode.reasoningEffort;
      return {
        'stream': useStreaming,
        if (preset.openaiMaxTokens > 0) 'max_tokens': preset.openaiMaxTokens,
        if (effort != null) ...{
          'thinking': {'type': 'enabled'},
          'reasoning_effort': effort,
        } else
          'thinking': {'type': 'disabled'},
      };
    }
    return {
      'stream': useStreaming,
      if (preset.temperature != null) 'temperature': preset.temperature,
      if (preset.openaiMaxTokens > 0) 'max_tokens': preset.openaiMaxTokens,
      if (preset.extra['enable_reasoning'] == true) ...{
        // 修正：非 DeepSeek 的 reasoning_effort 默认值 medium 不在
        // DeepSeek 官方取值内；这里仅保留非 DeepSeek 兼容路径。
        'reasoning_effort': preset.extra['reasoning_effort'] ?? 'high',
      },
    };
  }

  static Map<String, String> _extractCardData(Map<String, dynamic> cardJson) {
    final data = (cardJson['data'] as Map<String, dynamic>?) ?? cardJson;
    return {
      'personality': (data['personality'] as String?) ?? '',
      'description': (data['description'] as String?) ?? '',
      'scenario': (data['scenario'] as String?) ?? '',
    };
  }
}
