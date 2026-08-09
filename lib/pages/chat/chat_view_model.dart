import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/service_locator.dart';
import '../../data/api_configs.dart';
import '../../data/app_settings.dart';
import '../../data/mock_user_settings.dart';
import '../../data/preset_selection.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/group_chat_session.dart';
import '../../models/preset.dart';
import '../../models/prompt_assembly.dart';
import '../../models/quick_command.dart';
import '../../models/tracker_config.dart';
import '../../models/world_book.dart';
import '../../services/api_config_service.dart';
import '../../services/chat_character_resolver.dart';
import '../../services/chat_database_service.dart';
import '../../services/chat_opening_message_builder.dart';
import '../../services/context_usage_breakdown.dart';
import '../../services/preset_service.dart';
import '../../services/thinking_chain_guard.dart';
import '../../services/thinking_chain_preset_service.dart';
import '../../services/chat_service.dart';
import '../../services/chat_display_sanitizer.dart';
import '../../services/chat_variable_service.dart';
import '../../services/group_chat_service.dart';
import '../../services/openai_compatible_api_service.dart';
import '../../services/tracker_runtime.dart';
import '../../services/world_book_service.dart';
import 'widgets/message_edit_dialog.dart';

/// 聊天页面的视图模型。
///
/// 持有原 [_ChatPageState] 的全部业务状态，通过 [ChangeNotifier]
/// 通知 UI 刷新。UI 层（[ChatPage]）仅负责组装子 Widget 与转发
/// 用户事件，不再直接持有 service 或业务状态。
///
/// 设计约束：
/// - 不持有 [BuildContext]，所有 SnackBar / 对话框 / 导航由 UI 层处理。
/// - 业务方法在失败时抛出异常，由 UI 层捕获并展示。
/// - [ChatCompletionCancelledException] 为用户主动终止，内部吞没不抛出。
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    this.preferredSessionId,
    this.draftCharacterId,
    this.draftTitle,
    this.draftSelectedUserSettingId,
    this.draftSelectedPresetId,
    this.draftSelectedWorldBookIds = const [],
    this.draftGroupId,
    this.draftGroupTitle,
    this.draftGroupCharacterIds = const [],
    List<String> initialDraftOpeningMessages = const [],
    this.draftOpeningStatusHtml,
  }) : _initialDraftOpeningMessages = initialDraftOpeningMessages {
    _draftOpeningStatusHtml = _cleanupHtml(draftOpeningStatusHtml);
    // 缓存 notifier 引用，避免 dispose 时再次查找 getIt（DI 容器可能已重置）。
    _chatDbChangeNotifier = getIt<ChatDatabaseService>().changeNotifier;
    _presetChangeNotifier = getIt<PresetService>().changeNotifier;
    apiConfigsNotifier.addListener(onApiConfigsChanged);
    selectedApiModelIdNotifier.addListener(onApiConfigsChanged);
    // v68：ValueNotifier 的 addListener 需要无参 VoidCallback——事件值
    // 从 notifier.value 读取（onChatDatabaseChanged 内部取 change 参数）
    _chatDbChangeNotifier.addListener(_onDbChangedBroadcast);
    _presetChangeNotifier.addListener(onPresetsChanged);
  }

  /// v68：ValueNotifier 无参回调适配——读取最新事件值分派给
  /// [onChatDatabaseChanged]（带类型分流）。
  void _onDbChangedBroadcast() {
    final change = _chatDbChangeNotifier.value;
    if (change != null) {
      unawaited(onChatDatabaseChanged(change));
    }
  }

  /// 来自 [ChatPage] 的初始会话偏好 ID。
  final String? preferredSessionId;

  /// 草稿会话相关参数（来自 [ChatPage.draft]）。
  final String? draftCharacterId;
  final String? draftTitle;
  final String? draftSelectedUserSettingId;
  final String? draftSelectedPresetId;
  final List<String> draftSelectedWorldBookIds;
  final List<String> _initialDraftOpeningMessages;

  /// 特别版：群聊参数（来自 [ChatPage.draft]）。
  final String? draftGroupId;
  final String? draftGroupTitle;
  final List<String> draftGroupCharacterIds;

  /// 草稿会话开场里提取的特殊状态栏 HTML（来自 [ChatPage.draft]）。
  final String? draftOpeningStatusHtml;
  String? _draftOpeningStatusHtml;

  /// 开场状态栏（draft 阶段直接渲染，建立真实会话后持久化）。
  String? get effectiveDraftStatusHtml => _draftOpeningStatusHtml;

  /// 缓存构造时获取的 notifier，用于 dispose 时安全移除监听。
  /// v68：带类型的数据变化事件（kind 分流用）。
  late final ValueNotifier<ChatDatabaseChange?> _chatDbChangeNotifier;
  late final ValueNotifier<int> _presetChangeNotifier;

  /// 去空白/脚本：开场 HTML 直接来自角色卡（可含 ```html 包裹），
  /// 存之前剥离代码块围栏与脚本标签。
  static String? _cleanupHtml(String? value) {
    var html = value?.trim();
    if (html == null || html.isEmpty) {
      return null;
    }
    html = html.replaceAll(
      RegExp(r'^```(?:html|xml)?\s*|\s*```$', caseSensitive: false),
      '',
    );
    return html.trim();
  }

  // --- 业务状态字段 ---
  ChatSession? _activeSession;
  ResolvedChatCharacter? _activeCharacter;
  List<ChatMessage> _messages = [];

  /// 特别版：当前会话变量缓存（{{getvar}} 显示解析数据源）。
  /// 会话加载/发送后由 [_refreshSessionVariables] 刷新。
  Map<String, String> _sessionVariablesCache = const {};
  Map<String, String> get sessionVariablesCache => _sessionVariablesCache;

  Future<void> _refreshSessionVariables(String sessionId) async {
    final variables = await ChatDatabaseService.instance
        .getSessionVariables(sessionId);
    if (_isDisposed) {
      return;
    }
    _sessionVariablesCache = variables;
    notifyListeners();
  }
  List<WorldBook> _worldBooks = [];
  List<PresetSummary> _presets = [];
  /// 特别版：群聊成员角色（当前回复角色为 [_activeCharacter]）
  List<ResolvedChatCharacter> _groupCharacters = [];

  /// 特别版：手动指定本次发言角色（轮流制群聊；一次性，发送后清除）。
  String? _manualSpeakerId;

  /// 特别版：当前群聊的回复模式（rotation 轮流制 / everyone 全员回复）。
  GroupChatReplyMode _groupReplyMode = GroupChatReplyMode.rotation;

  final Set<String> _selectedWorldBookIds = {};
  String? _selectedPresetId;
  String? _selectedUserSettingId;
  bool _isLoading = true;
  bool _isSwitchingSession = false;
  bool _isSending = false;
  bool _isImpersonating = false;
  bool _useStreaming = true;
  bool _isCheckingApiStatus = false;
  String? _apiStatusModelId;
  ApiConnectionTestResult? _apiStatusResult;
  ChatCompletionCancelToken? _activeCompletionCancelToken;
  ChatMessage? _pendingUserMessage;
  String? _regeneratingUserMessageId;
  /// 特别版：冻结视图——AI 输出期间与完成后，ListView 数据完全
  /// 不变（显示此快照），新消息只进 [_messages]；用户点击
  /// "查看最新回复" 后解冻。null = 未冻结。
  List<ChatMessage>? _frozenVisibleMessages;
  String _streamingAssistantText = '';
  /// 流式显示缓存（避免每 token rebuild 重复正则扫描）
  String _streamingDisplayCache = '';
  int _streamingDisplayCacheLen = -1;
  String _streamingThinkingChain = '';
  String _streamingImpersonationText = '';
  String _thinkingChainRetryNotice = '';
  bool _isDraftSession = false;
  List<String> _draftOpeningAssistantMessages = const [];
  int _draftOpeningMessageIndex = 0;
  int _sessionLoadGeneration = 0;
  bool _isDisposed = false;

  /// 会话重新加载完成后的回调（由 UI 层注册，用于清理输入框等 UI 状态）。
  ///
  /// 原实现中 [_loadSession] 末尾会清空文本控制器；VM 不持有 UI 控件，
  /// 故通过此回调通知 UI 在每次会话加载完成后执行等价清理。
  VoidCallback? onSessionReloaded;

  // --- 状态读取器 ---
  ChatSession? get activeSession => _activeSession;
  ResolvedChatCharacter? get activeCharacter => _activeCharacter;
  List<ChatMessage> get messages => _messages;
  List<WorldBook> get worldBooks => _worldBooks;
  List<PresetSummary> get presets => _presets;
  Set<String> get selectedWorldBookIds => _selectedWorldBookIds;
  String? get selectedPresetId => _selectedPresetId;
  String? get selectedUserSettingId => _selectedUserSettingId;
  bool get isLoading => _isLoading;
  bool get isSwitchingSession => _isSwitchingSession;
  bool get isSending => _isSending;
  bool get isImpersonating => _isImpersonating;
  bool get useStreaming => _useStreaming;

  /// 特别版：最近一次发送成功的提示词组装结果（用于上下文用量详情）。
  PromptAssemblyResult? get lastPromptAssembly => _lastPromptAssembly;
  PromptAssemblyResult? _lastPromptAssembly;

  /// 特别版：最近一次请求的上下文用量（估算 token）与最大上下文。
  int get lastContextTotal => _lastContextTotal;

  /// v61：为模型回复预留的输出 token 与协议/消息格式安全余量。
  static const int kReservedOutputTokens = 8000;
  static const int kSafetyMarginTokens = 2000;

  /// v61：安全输入上限 = 模型窗口 - 输出预留 - 安全余量。
  /// 进度条分母与"可用"显示应使用该值（剩余 10K 不意味着还能安全
  /// 输入 10K——输出也要占空间）。
  int get lastContextSafeLimit {
    final max = _lastContextMax;
    if (max <= 0) {
      return 0;
    }
    return (max - kReservedOutputTokens - kSafetyMarginTokens).clamp(0, max);
  }
  int get lastContextMax => _lastContextMax;
  int _lastContextTotal = 0;
  int _lastContextMax = 128000;
  bool get isCheckingApiStatus => _isCheckingApiStatus;
  String? get apiStatusModelId => _apiStatusModelId;
  ApiConnectionTestResult? get apiStatusResult => _apiStatusResult;
  bool get isDraftSession => _isDraftSession;
  List<String> get draftOpeningAssistantMessages =>
      _draftOpeningAssistantMessages;
  int get draftOpeningMessageIndex => _draftOpeningMessageIndex;
  ChatMessage? get pendingUserMessage => _pendingUserMessage;
  String? get regeneratingUserMessageId => _regeneratingUserMessageId;
  String get streamingAssistantText => _streamingAssistantText;

  /// 特别版：流式显示文本——用**轻量清洗**（只剥协议块/setvar/注释，
  /// 不提取 div/details，避免破坏性 extract 把流式正文剥空）。
  /// 带长度缓存：流式每 token 变化时只重算一次。
  String get streamingDisplayText {
    final raw = _streamingAssistantText;
    if (raw.isEmpty) {
      return raw;
    }
    if (raw.length == _streamingDisplayCacheLen) {
      return _streamingDisplayCache;
    }
    final display = ChatDisplaySanitizer.stripStoredMessageForDisplay(raw);
    _streamingDisplayCache = display;
    _streamingDisplayCacheLen = raw.length;
    return display;
  }
  String get streamingThinkingChain => _streamingThinkingChain;

  /// 特别版：当前是否正在流式输出思考链（用于悬浮面板"思考中"）。
  bool get isStreamingThinking =>
      _isSending && _streamingThinkingChain.isNotEmpty;

  /// 特别版：当前流式发言人名字（群聊悬浮面板头部显示）。
  String? get streamingSpeakerName {
    if (!_isSending || _activeCharacter == null) {
      return null;
    }
    final id = _resolveSpeaker(_activeCharacter)?.id;
    if (id == null) {
      return null;
    }
    return _groupNameMap[id];
  }

  /// 特别版：当前是否有正在流式输出的内容（思考链或正文）。
  /// 用于视口锚定：发送后、首个流式内容到达前保持跟随（让用户
  /// 看到自己发送的消息），流式内容出现后才开始冻结视口。
  bool get hasStreamingContent =>
      _streamingAssistantText.isNotEmpty || _streamingThinkingChain.isNotEmpty;

  /// 思维链违规重试时的提示文本（如"已退回重新生成（第 N 次强制）"）。
  String get thinkingChainRetryNotice => _thinkingChainRetryNotice;

  /// 特别版：当前列表是否处于冻结状态（AI 输出中/已完成的浮层模式）。
  bool get isMessagesFrozen => _frozenVisibleMessages != null;

  /// 特别版：冻结当前列表视图（复制，发送前状态）。
  void _freezeMessages() {
    _frozenVisibleMessages = List<ChatMessage>.from(_messages);
  }

  /// 特别版：解冻（恢复显示真实数据）。
  void _unfreezeMessages() {
    _frozenVisibleMessages = null;
  }

  /// 当前生效的可见消息列表（含待发送、流式中、重新生成占位）。
  List<ChatMessage> get visibleMessages {
    // 特别版：AI 输出期间与完成后列表冻结——ListView 数据完全
    // 不变（新消息只进数据层），从根本上杜绝视口跳动。
    final frozen = _frozenVisibleMessages;
    if (frozen != null) {
      return List<ChatMessage>.from(frozen);
    }
    final items = List<ChatMessage>.from(_messages);
    final regeneratingUserMessageId = _regeneratingUserMessageId;
    if (regeneratingUserMessageId != null &&
        items.isNotEmpty &&
        !items.last.isMe &&
        items.last.parentId == regeneratingUserMessageId) {
      items.removeLast();
    }
    final pendingUserMessage = _pendingUserMessage;
    if (pendingUserMessage != null) {
      items.add(pendingUserMessage);
    }

    // 特别版：流式输出由列表外的悬浮面板（StreamingPanel）展示，
    // 列表在流式期间完全零增长——发消息后主界面彻底定住。
    return items;
  }

  /// 当前选中的用户设定（若未选中则回退到列表首项）。
  UserSetting? currentUserSetting() {
    final settings = userSettingsNotifier.value;
    if (settings.isEmpty) {
      return null;
    }
    final selectedId = _selectedUserSettingId;
    if (selectedId != null) {
      for (final item in settings) {
        if (item.id == selectedId) {
          return item;
        }
      }
    }
    return settings.first;
  }

  /// 解析当前用户名。
  String resolvedUserName() {
    return currentUserSetting()?.name ?? '默认用户';
  }

  /// 替换聊天变量占位符。
  String replaceChatVariables(String input) {
    return ChatVariableService.replacePlaceholders(
      input,
      characterName: _activeCharacter?.name ?? '角色',
      userName: resolvedUserName(),
    );
  }

  // --- 生命周期 ---

  /// 初始化页面：加载世界书、预设，随后加载草稿会话或常规会话。
  /// 同时并发刷新 API 状态（与原 initState 中 _refreshEnabledApiStatus 并行）。
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    // 并发触发 API 状态刷新（不等待，匹配原 initState 行为）。
    _refreshSelectedApiStatus();

    final books = await getIt<WorldBookService>().loadAll();
    final presets = await getIt<PresetService>().loadAllSummaries();

    if (_isDisposed) {
      return;
    }

    _worldBooks = books;
    _presets = presets;
    notifyListeners();

    if (draftCharacterId != null) {
      await _loadDraftSession();
      return;
    }

    if (draftGroupId != null) {
      await _loadDraftGroupSession();
      return;
    }

    await _loadSession(preferredSessionId: preferredSessionId);
  }

  /// 特别版：是否群聊会话。
  bool get isGroupChat => _groupCharacters.length > 1;

  /// 特别版：手动指定本次发言角色（一次性，发送后自动清除）。
  String? get manualSpeakerId => _manualSpeakerId;

  /// 特别版：当前群聊的回复模式。
  GroupChatReplyMode get groupReplyMode => _groupReplyMode;

  /// 特别版：是否为全员回复模式的群聊。
  bool get isEveryoneGroupChat =>
      _groupCharacters.length > 1 &&
      _groupReplyMode == GroupChatReplyMode.everyone;

  /// 特别版：手动指定本次发言角色（轮流制群聊）。
  void selectGroupSpeaker(String characterId) {
    if (_groupCharacters.any((c) => c.id == characterId)) {
      _manualSpeakerId = characterId;
      notifyListeners();
    }
  }

  /// 特别版：解析本次发言角色——手动指定优先，否则当前轮转角色。
  ResolvedChatCharacter? _resolveSpeaker(ResolvedChatCharacter? fallback) {
    final manualId = _manualSpeakerId;
    if (manualId != null) {
      for (final character in _groupCharacters) {
        if (character.id == manualId) {
          return character;
        }
      }
    }
    return fallback;
  }

  /// 特别版：解析本次请求的世界书集合——会话选择的 +
  /// 群聊发言角色的配套世界书（成员世界书分别注入）。
  Set<String> _resolvedWorldBookIds(ResolvedChatCharacter? speaker) {
    final worldBookId = speaker?.worldBookId;
    if (_groupCharacters.isNotEmpty && worldBookId != null) {
      return {..._selectedWorldBookIds, worldBookId};
    }
    return _selectedWorldBookIds;
  }

  /// 特别版：群聊发言人名字映射（characterId → 角色名），
  /// 供提示词历史消息带发言人前缀。
  Map<String, String> get _groupNameMap => {
    for (final character in _groupCharacters) character.id: character.name,
  };

  /// 特别版：群聊成员角色列表。
  List<ResolvedChatCharacter> get groupCharacters =>
      List.unmodifiable(_groupCharacters);

  /// 特别版：加载群聊草稿会话（成员轮转回复）。
  Future<void> _loadDraftGroupSession() async {
    final groupId = draftGroupId;
    final characterIds = draftGroupCharacterIds;
    if (groupId == null || characterIds.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    final loadGeneration = ++_sessionLoadGeneration;
    final resolver = getIt<ChatCharacterResolver>();
    final resolved = <ResolvedChatCharacter>[];
    for (final characterId in characterIds) {
      final character = await resolver.resolveById(characterId);
      if (character != null) {
        resolved.add(character);
      }
    }
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }
    if (resolved.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _groupCharacters = resolved;
    // 特别版：加载群聊配置一次，用于游标恢复与回复模式
    final groupForCursor = await GroupChatService.instance.loadById(groupId);
    // await 之后重新检查（草稿初始化期间可能已退出页面）
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }
    // 特别版：按轮转游标恢复当前发言人（与 _restoreGroupChat 一致），
    // 避免草稿群聊每次重载都重置为第一个成员（轮流失效）。
    var speakerIndex = 0;
    if (groupForCursor != null && groupForCursor.characterIds.isNotEmpty) {
      speakerIndex =
          groupForCursor.turnIndex % groupForCursor.characterIds.length;
      // 游标指向的角色解析失败时向后找下一个可解析成员
      final resolvedIds = resolved.map((c) => c.id).toSet();
      var guard = 0;
      while (speakerIndex < groupForCursor.characterIds.length &&
          !resolvedIds.contains(groupForCursor.characterIds[speakerIndex])) {
        speakerIndex =
            (speakerIndex + 1) % groupForCursor.characterIds.length;
        guard++;
        if (guard >= groupForCursor.characterIds.length) {
          speakerIndex = 0;
          break;
        }
      }
    }
    _activeCharacter = resolved[speakerIndex % resolved.length];
    // 特别版：按 id 精确定位发言人（group 顺序与 resolved 顺序可能
    // 不一致——成员解析失败会缩短 resolved），与 _restoreGroupChat 一致
    if (groupForCursor != null &&
        speakerIndex < groupForCursor.characterIds.length) {
      final targetId = groupForCursor.characterIds[speakerIndex];
      for (final character in resolved) {
        if (character.id == targetId) {
          _activeCharacter = character;
          break;
        }
      }
    }
    // 特别版：解析群聊回复模式（草稿会话首次聊天也要生效）
    if (groupForCursor != null) {
      _groupReplyMode = groupForCursor.parsedReplyMode;
    }
    _manualSpeakerId = null;

    final now = DateTime.now();
    final openingMessages = _initialDraftOpeningMessages
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final title = draftGroupTitle?.trim().isNotEmpty == true
        ? draftGroupTitle!.trim()
        : resolved.map((c) => c.name).join(' × ');

    _activeSession = ChatSession(
      id: '__draft_group__$groupId',
      title: title,
      characterId: 'group:$groupId',
      selectedUserSettingId: draftSelectedUserSettingId,
      selectedWorldBookIds: List<String>.from(draftSelectedWorldBookIds),
      selectedPresetId: draftSelectedPresetId,
      currentLeafMessageId: null,
      lastMessagePreview: openingMessages.isNotEmpty
          ? openingMessages.first
          : '',
      createdAt: now,
      updatedAt: now,
    );
    _draftOpeningMessageIndex = 0;
    _messages = _buildDraftOpeningMessages(openingMessages);
    _selectedUserSettingId = draftSelectedUserSettingId;
    _selectedPresetId = draftSelectedPresetId;
    _selectedWorldBookIds
      ..clear()
      ..addAll(draftSelectedWorldBookIds);
    _isDraftSession = true;
    _isLoading = false;
    _isSwitchingSession = false;
    notifyListeners();
  }

  /// 特别版：群聊轮转——发送成功后切换到下一位回复角色。
  /// 群组 id 优先从会话标记解析（已持久化的群聊会话也生效），
  /// 草稿会话回退到 [draftGroupId]。
  Future<void> _advanceGroupTurn() async {
    if (_groupCharacters.length < 2) {
      return;
    }
    String? groupId = draftGroupId;
    if (groupId == null) {
      final session = _activeSession;
      if (session != null) {
        groupId = parseGroupChatId(session.characterId);
      }
    }
    if (groupId == null) {
      return;
    }
    final nextId = await GroupChatService.instance.nextTurnCharacterId(
      groupId,
    );
    if (nextId == null || _isDisposed) {
      return;
    }
    for (final character in _groupCharacters) {
      if (character.id == nextId) {
        _activeCharacter = character;
        notifyListeners();
        return;
      }
    }
  }

  /// 特别版：全员回复模式——用户消息后，其余成员按顺序自动依次回复
  /// （每个成员对上一条消息发言，中间短暂停顿）。任一轮被停止/取消
  /// 或出错即终止整条链；所有成员都回过本轮后结束。
  /// 调用前 [_isSending] 保持 true（停止键常驻），由外层 finally 复位。
  ///
  /// [speakerId] 为刚完成发言的成员（用户消息的回复者），计入本轮已回；
  /// [firstReplyNodeId] 为该回复的消息 id（第一轮后续发言挂在其下，
  /// 之后每轮自动挂在上一轮回复之后，保证消息链完整）。
  Future<void> _runEveryoneTurn({
    required String firstReplyNodeId,
    required String speakerId,
  }) async {
    if (!isEveryoneGroupChat) {
      return;
    }
    // 本轮已回复成员：初始只含刚发言的回复者（历史轮次不计入）
    final repliedThisRound = <String>{speakerId};
    var isFirstRound = true;

    while (!_isDisposed && !(_activeCompletionCancelToken?.isCancelled ?? false)) {
      // 全员已回过本轮 → 结束
      if (_groupCharacters.every((c) => repliedThisRound.contains(c.id))) {
        break;
      }
      await _advanceGroupTurn();
      if (_isDisposed) {
        break;
      }
      final speaker = _activeCharacter;
      if (speaker == null) {
        break;
      }
      if (repliedThisRound.contains(speaker.id)) {
        // 游标已绕回已发言成员：本轮全员完成
        break;
      }
      // 短暂停顿，模拟自然轮流发言节奏
      await Future.delayed(const Duration(milliseconds: 600));
      if (_isDisposed || (_activeCompletionCancelToken?.isCancelled ?? false)) {
        break;
      }

      final cancellationToken = ChatCompletionCancelToken();
      _activeCompletionCancelToken = cancellationToken;
      _streamingAssistantText = '';
      _streamingThinkingChain = '';
      // 全员链每轮重置：清除上一轮残留的重试提示
      _thinkingChainRetryNotice = '';
      notifyListeners();

      try {
        final session = _activeSession;
        if (session == null) {
          break;
        }
        final result = await getIt<ChatService>().generateGroupReply(
          session: session,
          character: speaker,
          chatMessages: _messages,
          // 第一轮挂在刚完成的回复之后，后续轮自动挂上一轮回复
          parentMessageId: isFirstRound ? firstReplyNodeId : null,
          selectedPresetId: _selectedPresetId,
          selectedUserSettingId: _selectedUserSettingId,
          selectedWorldBookIds: _resolvedWorldBookIds(speaker),
          groupCharacterNames: _groupNameMap,
          useStreaming: _useStreaming,
          cancellationToken: cancellationToken,
          onStreamProgress: (progress) {
            if (_isDisposed) {
              return;
            }
            if (progress.textDelta.isNotEmpty) {
              _streamingAssistantText += progress.textDelta;
              // 重试收到首个正文 delta：清除重试提示（面板显示正文）
              if (_thinkingChainRetryNotice.isNotEmpty) {
                _thinkingChainRetryNotice = '';
              }
            }
            if (progress.thinkingDelta.isNotEmpty) {
              _streamingThinkingChain += progress.thinkingDelta;
            }
            notifyListeners();
          },
          onThinkingChainRetry: _onThinkingChainRetry,
        );
        if (result.completion.isPartial) {
          // 用户中途停止产生的部分回复：终止整条链
          break;
        }
        // 乐观追加到消息列表（供下一轮上下文与界面展示）
        final node = result.assistantNode;
        _messages = [
          ..._messages,
          ChatMessage(
            id: node.id,
            sessionId: node.sessionId,
            parentId: node.parentId,
            text: node.text,
            isMe: false,
            characterId: node.characterId,
            isPartial: node.isPartial,
            thinkingChain: node.thinkingChain,
            modelText: node.modelText,
            index: 1,
            total: 1,
            siblingIds: const [],
          ),
        ];
        _lastPromptAssembly = result.promptAssembly;
        repliedThisRound.add(speaker.id);
        isFirstRound = false;
        notifyListeners();
      } on ChatCompletionCancelledException {
        // 用户主动停止：终止整条链
        break;
      } catch (error) {
        // 单轮生成失败（含思维链 10 次重试耗尽）：终止链，错误由外层
        // 异常提示展示
        rethrow;
      }
    }
  }

  /// 全局 API 配置或选中模型变化时刷新 API 状态。
  Future<void> onApiConfigsChanged() => _refreshSelectedApiStatus();

  /// 聊天数据库变化时按类型分流：messages/session 重载会话；
  /// variables 只刷新变量缓存（不重载消息树——后台状态裁判写入
  /// 快照时禁止触发跳底）；choices 只刷新该消息动作按钮。
  /// v69：`_isSending` 保护只作用于 messages/session（重载消息树）；
  /// variables/choices 只刷新轻量缓存，**不受发送中状态限制**——后台
  /// 裁判在正文显示后（isSending 可能仍为 true）写库时也必须刷新，
  /// 否则"状态已写库但 UI 显示旧值"（v68 遗漏：_isSending 检查在
  /// switch 之前拦截了所有类型）。
  Future<void> onChatDatabaseChanged(ChatDatabaseChange change) async {
    if (_isDraftSession) {
      return;
    }
    final sessionId = _activeSession?.id ?? preferredSessionId;
    if (sessionId == null || _isLoading || _isSwitchingSession) {
      return;
    }
    // v75：非当前会话的事件直接忽略——后台裁判完成会话 A 的写入时，
    // 若当前在查看会话 B，刷新 B 的变量会把 A 的状态串进来
    // （之前 variables 分支直接用 change.sessionId，切换会话后状态栏
    // 短暂显示另一张卡的数值）
    if (change.sessionId != null && change.sessionId != sessionId) {
      return;
    }
    switch (change.kind) {
      case ChatDatabaseChangeKind.variables:
        // v68/v69：Tracker 变量/状态快照更新——只刷新变量缓存与状态
        // 面板，不重载消息树（后台裁判写入发生在正文显示后，重载会
        // 跳底；发送中也要刷新，否则状态栏显示旧值）
        // v75：只刷新当前活动会话（事件已过滤非当前会话）
        await _refreshSessionVariables(sessionId);
        return;
      case ChatDatabaseChangeKind.choices:
        // v68：choices 更新——消息动作按钮由 FutureBuilder 按 messageId
        // 加载，变量缓存刷新即可触发重建（无需重载会话）
        await _refreshSessionVariables(sessionId);
        return;
      case ChatDatabaseChangeKind.messages:
      case ChatDatabaseChangeKind.session:
        if (_isSending) {
          // v69：发送中不重载消息树（流式输出期间重载会打断/跳底）；
          // 消息树由发送流程本身在完成后刷新
          return;
        }
        await _loadSession(preferredSessionId: sessionId);
        return;
    }
  }

  /// 预设列表变化时重新加载预设摘要。
  Future<void> onPresetsChanged() async {
    final presets = await getIt<PresetService>().loadAllSummaries();
    if (_isDisposed) {
      return;
    }
    _presets = presets;
    notifyListeners();
  }

  // --- 会话加载 ---

  Future<void> _loadDraftSession() async {
    final characterId = draftCharacterId;
    if (characterId == null) {
      return;
    }

    final loadGeneration = ++_sessionLoadGeneration;
    final resolvedCharacter = await getIt<ChatCharacterResolver>().resolveById(
      characterId,
    );
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }

    if (resolvedCharacter == null) {
      _activeSession = null;
      _activeCharacter = null;
      _messages = [];
      _isDraftSession = false;
      _draftOpeningAssistantMessages = const [];
      _isLoading = false;
      _isSwitchingSession = false;
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final openingMessages = _initialDraftOpeningMessages
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final title = draftTitle?.trim().isNotEmpty == true
        ? draftTitle!.trim()
        : resolvedCharacter.name;

    final initialWorldBookIds = List<String>.from(draftSelectedWorldBookIds);
    _activeSession = ChatSession(
      id: '__draft_chat__${resolvedCharacter.id}',
      title: title,
      characterId: resolvedCharacter.id,
      selectedUserSettingId: draftSelectedUserSettingId,
      selectedWorldBookIds: initialWorldBookIds,
      selectedPresetId: draftSelectedPresetId,
      currentLeafMessageId: null,
      lastMessagePreview: openingMessages.isNotEmpty
          ? openingMessages.first
          : '',
      createdAt: now,
      updatedAt: now,
    );
    _activeCharacter = resolvedCharacter;
    _draftOpeningMessageIndex = 0;
    _messages = _buildDraftOpeningMessages(openingMessages);
    _selectedUserSettingId = draftSelectedUserSettingId;
    _selectedPresetId = draftSelectedPresetId;
    _selectedWorldBookIds
      ..clear()
      ..addAll(initialWorldBookIds);
    _isDraftSession = true;
    _draftOpeningAssistantMessages = openingMessages;
    _isLoading = false;
    _isSwitchingSession = false;
    notifyListeners();
  }

  List<ChatMessage> _buildDraftOpeningMessages(List<String> openingMessages) {
    if (openingMessages.isEmpty) {
      return const [];
    }
    final index = _draftOpeningMessageIndex.clamp(
      0,
      openingMessages.length - 1,
    );
    return [
      ChatMessage(
        text: openingMessages[index],
        isMe: false,
        index: index + 1,
        total: openingMessages.length,
      ),
    ];
  }

  Future<void> loadWorldBooks() async {
    final books = await getIt<WorldBookService>().loadAll();
    if (_isDisposed) {
      return;
    }
    _worldBooks = books;
    notifyListeners();
  }

  Future<void> _loadSession({String? preferredSessionId}) async {
    final loadGeneration = ++_sessionLoadGeneration;
    final summaries = await getIt<ChatDatabaseService>().loadSessionSummaries();
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }

    if (summaries.isEmpty) {
      _activeSession = null;
      _activeCharacter = null;
      _messages = [];
      // 会话切换/加载：解除列表冻结（回到真实数据）。
      // 仅主动切换会话（_isSwitchingSession）时解冻；发送后的
      // _loadSession 不触碰冻结（自动合入由 finally 统一解冻负责）。
      if (_isSwitchingSession) {
        _unfreezeMessages();
      }
      _selectedUserSettingId = null;
      _selectedPresetId = null;
      _selectedWorldBookIds.clear();
      _isDraftSession = false;
      _draftOpeningAssistantMessages = const [];
      _draftOpeningMessageIndex = 0;
      _isLoading = false;
      _isSwitchingSession = false;
      notifyListeners();
      return;
    }

    final targetSummary = summaries.firstWhere(
      (item) => item.id == preferredSessionId,
      orElse: () => summaries.first,
    );
    final bundle = await getIt<ChatDatabaseService>().loadSessionBundle(
      targetSummary.id,
    );
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }
    if (bundle == null) {
      // 加载失败：解除列表冻结（避免残留）
      _unfreezeMessages();
      _isLoading = false;
      _isSwitchingSession = false;
      notifyListeners();
      return;
    }

    final resolvedCharacter = await getIt<ChatCharacterResolver>().resolveById(
      bundle.session.characterId,
    );
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }

    _activeSession = bundle.session;
    _activeCharacter = resolvedCharacter;
    _messages = bundle.activeMessages;
    // 特别版：会话加载即刷新变量缓存（消息/状态栏 getvar 显示解析用）。
    // v46：显式等待完成——发送/重生成/继续/群聊后的 _loadSession 也走
    // 这里，若 unawaited 则 UI 可能在变量刷新完成前渲染（状态栏显示
    // 旧值直到下一次 notify）。await 保证气泡拿到的是数据库最终值。
    await _refreshSessionVariables(bundle.session.id);
    // v51：分支状态恢复——切换分支/删除分支/重新打开会话后，把 tracker
    // 状态恢复到当前分支最后一条角色消息的时刻（v3 快照），否则全局
    // 变量停留在旧分支推进后的状态。仅当最后一条不是用户消息时恢复
    // （用户消息后无回复时旁白已实时落地、无快照可回，强回滚会丢旁白）。
    if (_messages.isNotEmpty && !_messages.last.isMe) {
      await _restoreTrackerBaseline();
    }
    // 特别版：会话切换/加载时清空上一次的接口真实用量
    _lastRealUsage = null;
    // 会话切换/加载：解除列表冻结（回到真实数据）。
    // 仅主动切换会话（_isSwitchingSession）时解冻；发送后的
    // _loadSession 不触碰冻结（自动合入由 finally 统一解冻负责）。
    if (_isSwitchingSession) {
      _unfreezeMessages();
    }
    _selectedUserSettingId = bundle.session.selectedUserSettingId;
    _selectedPresetId = bundle.session.selectedPresetId;
    // 特别版：群聊会话未记录预设（旧群聊/创建时未选）时继承全局预设，
    // 上下文上限与单聊保持一致（否则群聊回退模型默认 128K）
    if (_selectedPresetId == null &&
        parseGroupChatId(bundle.session.characterId) != null) {
      _selectedPresetId = selectedPresetIdNotifier.value;
    }
    _selectedWorldBookIds
      ..clear()
      ..addAll(bundle.session.selectedWorldBookIds);
    _isDraftSession = false;
    _draftOpeningAssistantMessages = const [];
    _draftOpeningMessageIndex = 0;
    _isLoading = false;
    if (_isSwitchingSession) {
      _resetPendingMessages();
    }
    _isSwitchingSession = false;
    notifyListeners();
    onSessionReloaded?.call();

    // 特别版：会话打开即估算上下文用量（常驻显示；发送后精确值覆盖）
    unawaited(_refreshContextEstimate());

    // 特别版：群聊会话恢复——加载成员角色并按轮转游标恢复当前发言人
    final groupId = parseGroupChatId(bundle.session.characterId);
    if (groupId != null) {
      await _restoreGroupChat(groupId, loadGeneration);
    } else {
      // 普通会话：清空群聊成员残留，避免群聊→单聊切换后
      // assistant 消息被错误标记发言人
      if (_groupCharacters.isNotEmpty) {
        _groupCharacters = [];
        notifyListeners();
      }
    }
  }

  /// 特别版：恢复群聊成员与轮转游标。
  /// [loadGeneration] 用于防止快速切换会话时旧恢复覆盖新会话状态。
  Future<void> _restoreGroupChat(
    String groupId,
    int loadGeneration,
  ) async {
    final group = await GroupChatService.instance.loadById(groupId);
    if (group == null || group.characterIds.isEmpty || _isDisposed) {
      return;
    }
    if (loadGeneration != _sessionLoadGeneration) {
      return;
    }
    // 特别版：同步群聊回复模式（轮流制 / 全员回复）
    _groupReplyMode = group.parsedReplyMode;
    _manualSpeakerId = null;
    final resolver = getIt<ChatCharacterResolver>();
    final resolved = <ResolvedChatCharacter>[];
    for (final characterId in group.characterIds) {
      final character = await resolver.resolveById(characterId);
      if (loadGeneration != _sessionLoadGeneration || _isDisposed) {
        return;
      }
      if (character != null) {
        resolved.add(character);
      }
    }
    if (resolved.isEmpty) {
      // 全部成员已被删除：清空残留，避免上一会话的成员泄漏
      _groupCharacters = [];
      _activeCharacter = null;
      notifyListeners();
      return;
    }
    _groupCharacters = resolved;
    // 游标与 nextTurnCharacterId 同一取模口径（characterIds.length）；
    // 若游标指向的角色解析失败（已被删除），向后找下一个可解析角色。
    final memberCount = group.characterIds.length;
    var turnIndex = group.turnIndex % memberCount;
    final resolvedIds = resolved.map((c) => c.id).toSet();
    var guard = 0;
    while (!resolvedIds.contains(group.characterIds[turnIndex])) {
      turnIndex = (turnIndex + 1) % memberCount;
      guard++;
      if (guard >= memberCount) {
        break;
      }
    }
    final nextSpeakerId = group.characterIds[turnIndex];
    for (final character in resolved) {
      if (character.id == nextSpeakerId) {
        _activeCharacter = character;
        break;
      }
    }
    notifyListeners();
  }

  /// v51：按当前消息链恢复 tracker 基线状态——倒序找最近一条角色消息
  /// 的 v3 快照（该消息时刻的最终状态），用 replace 写入变量表（清除
  /// 旧分支存在、当前分支不存在的 tracker 字段），并刷新变量缓存。
  Future<void> _restoreTrackerBaseline() async {
    final session = _activeSession;
    final character = _activeCharacter;
    if (session == null || character == null || _messages.isEmpty) {
      return;
    }
    final config = TrackerConfig.fromCardJson(character.cardJson);
    if (!config.isEnabled) {
      return;
    }
    final variables = await ChatDatabaseService.instance
        .getSessionVariables(session.id);
    Map<String, dynamic>? baseline;
    for (final msg in _messages.reversed) {
      if (msg.isMe || msg.id == null) {
        continue;
      }
      final raw = variables[ChatService.messageStatusHtmlKey(msg.id!)];
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
            baseline = state;
            break;
          }
        }
      } catch (_) {
        // 坏快照跳过，继续找更早的角色消息
      }
    }
    if (baseline == null) {
      return; // 无快照不恢复（保持现状）
    }
    final trackerKeys = <String>{
      ...config.stateSchema.keys,
      ...config.initialState.keys,
    };
    final replaced = Map<String, String>.from(variables);
    for (final key in trackerKeys) {
      final v = baseline[key];
      if (v != null) {
        replaced[key] = '$v';
      } else {
        replaced.remove(key);
      }
    }
    await ChatDatabaseService.instance.replaceSessionVariables(
      session.id,
      replaced,
      replaceKeys: trackerKeys,
    );
    await _refreshSessionVariables(session.id);
  }

  /// 从侧边栏选择一个会话。返回是否已开始切换（false 表示当前正在发送）。
  bool selectSession(String sessionId) {
    if (_isSending || _isImpersonating) {
      return false;
    }
    if (sessionId == _activeSession?.id) {
      return false;
    }
    _isSwitchingSession = true;
    notifyListeners();
    _loadSession(preferredSessionId: sessionId);
    return true;
  }

  Future<void> _persistSessionConfig() async {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    if (_isDraftSession) {
      _activeSession = session.copyWith(
        selectedUserSettingId: _selectedUserSettingId,
        selectedWorldBookIds: _selectedWorldBookIds.toList(),
        selectedPresetId: _selectedPresetId,
      );
      notifyListeners();
      return;
    }

    await getIt<ChatDatabaseService>().updateSessionConfig(
      sessionId: session.id,
      selectedUserSettingId: _selectedUserSettingId,
      selectedWorldBookIds: _selectedWorldBookIds.toList(),
      selectedPresetId: _selectedPresetId,
    );
    if (_isDisposed) {
      return;
    }
    _activeSession = session.copyWith(
      selectedUserSettingId: _selectedUserSettingId,
      selectedWorldBookIds: _selectedWorldBookIds.toList(),
      selectedPresetId: _selectedPresetId,
    );
    notifyListeners();
  }

  Future<ChatSession> _persistDraftSession() async {
    final session = _activeSession;
    final character = _activeCharacter;
    if (!_isDraftSession || session == null || character == null) {
      if (session == null) {
        throw StateError('当前没有可保存的聊天');
      }
      return session;
    }

    final createdSession = await getIt<ChatDatabaseService>().createSession(
      // 特别版：群聊会话以 'group:<groupId>' 标记身份
      characterId: draftGroupId != null ? 'group:$draftGroupId' : character.id,
      title: session.title,
      selectedUserSettingId: _selectedUserSettingId,
      selectedWorldBookIds: _selectedWorldBookIds.toList(),
      selectedPresetId: _selectedPresetId,
      openingAssistantMessages: _draftOpeningAssistantMessages,
      activeOpeningMessageIndex: _draftOpeningMessageIndex,
    );

    _activeSession = createdSession;
    _isDraftSession = false;
    _draftOpeningAssistantMessages = const [];
    _draftOpeningMessageIndex = 0;
    // 开场状态栏在真实会话建立后持久化（TrackerStatusBar 从变量读）
    await _persistSpecialStatusHtml(createdSession.id, _draftOpeningStatusHtml);
    if (!_isDisposed) {
      notifyListeners();
    }

    return createdSession;
  }

  /// 持久化特殊状态栏 HTML 到会话变量表（空值跳过）。
  Future<void> _persistSpecialStatusHtml(
    String sessionId,
    String? html,
  ) async {
    final value = html?.trim();
    if (value == null || value.isEmpty) {
      return;
    }
    final variables = await ChatDatabaseService.instance
        .getSessionVariables(sessionId);
    variables[kSpecialStatusHtmlKey] = value;
    await ChatDatabaseService.instance.upsertSessionVariables(
      sessionId,
      variables,
    );
  }

  // --- API 状态 ---

  Future<void> _refreshSelectedApiStatus() async {
    final config = resolvedSelectedApi;
    if (config == null) {
      if (_isDisposed) {
        return;
      }
      _isCheckingApiStatus = false;
      _apiStatusModelId = null;
      _apiStatusResult = null;
      notifyListeners();
      return;
    }

    _isCheckingApiStatus = true;
    _apiStatusModelId = selectedApiModelIdNotifier.value;
    notifyListeners();

    final result = await getIt<OpenAICompatibleApiService>().testConnection(
      config,
    );
    if (_isDisposed ||
        selectedApiModelIdNotifier.value != _apiStatusModelId) {
      return;
    }

    _isCheckingApiStatus = false;
    _apiStatusModelId = selectedApiModelIdNotifier.value;
    _apiStatusResult = result;
    notifyListeners();
  }

  /// 选择某个模型。直接委托给全局 [selectApiModel]（来自 data/api_configs.dart）。
  ///
  /// 选择状态变化会触发 [selectedApiModelIdNotifier]，本 VM 在构造时已注册监听，
  /// 故 [_refreshSelectedApiStatus] 会自动执行，无需在此显式调用。
  Future<void> selectApiModel(String modelId) async {
    // 显式调用顶层函数（通过 getIt 间接拿到 Service 不可行，
    // 这里直接复用全局辅助），使用 ApiConfigService 单例完成持久化。
    selectedApiModelIdNotifier.value = modelId;
    await ApiConfigService.instance.saveSelectedModelId(modelId);
  }

  // --- 发送 / 重新生成 ---

  /// 发送一条用户消息。[rawText] 为未经变量替换的原始输入。
  /// [modelText] 特别版：发送给模型的完整内容（快捷指令场景）。
  Future<void> sendMessage(String rawText, {String? modelText}) async {
    final session = _activeSession;
    // 特别版：手动指定发言人优先，否则当前轮转角色
    final character = _resolveSpeaker(_activeCharacter);
    final text = replaceChatVariables(rawText.trim()).trim();
    if (text.isEmpty ||
        session == null ||
        character == null ||
        _isSwitchingSession ||
        _isSending ||
        _isImpersonating) {
      return;
    }

    final cancellationToken = ChatCompletionCancelToken();
    _activeCompletionCancelToken = cancellationToken;
    _isSending = true;
    _pendingUserMessage = ChatMessage(text: text, isMe: true);
    _streamingAssistantText = '';
    _streamingThinkingChain = '';
    // 特别版：冻结列表——AI 输出期间与完成后，ListView 数据完全
    // 不变（新消息只进数据层），从根本上杜绝视口跳动。
    _freezeMessages();
    notifyListeners();

    ChatSession? persistedSession;

    try {
      final result = await getIt<ChatService>().sendMessage(
        session: session,
        character: character,
        chatMessages: _messages,
        input: text,
        selectedPresetId: _selectedPresetId,
        selectedUserSettingId: _selectedUserSettingId,
        selectedWorldBookIds: _resolvedWorldBookIds(character),
        groupCharacterNames: _groupNameMap,
        useStreaming: _useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: (progress) {
          if (_isDisposed) {
            return;
          }
          if (progress.textDelta.isNotEmpty) {
            _streamingAssistantText += progress.textDelta;
            // 重试收到首个正文 delta：清除重试提示（面板显示正文）
            if (_thinkingChainRetryNotice.isNotEmpty) {
              _thinkingChainRetryNotice = '';
            }
          }
          if (progress.thinkingDelta.isNotEmpty) {
            _streamingThinkingChain += progress.thinkingDelta;
          }
          notifyListeners();
        },
        onThinkingChainRetry: _onThinkingChainRetry,
        persistSession: _isDraftSession
            ? () async {
                final createdSession = await _persistDraftSession();
                persistedSession = createdSession;
                return createdSession;
              }
            : null,
        modelText: modelText,
        assistantCharacterId: _groupCharacters.isNotEmpty
            ? character.id
            : null,
      );
      // 用户中途停止的部分回复不算完整发言，不推进群聊轮转
      if (!result.completion.isPartial) {
        _lastPromptAssembly = result.promptAssembly;
        // 特别版：记录接口真实用量（usage），供用量页校准展示
        _lastRealUsage = result.completion.usageTokens;
        await _refreshContextUsage(result.promptAssembly);
        _manualSpeakerId = null;
        if (isEveryoneGroupChat) {
          // 特别版：全员回复模式——其余成员按顺序自动依次回复
          // （游标由链内统一推进，避免双重切换）
          await _runEveryoneTurn(
            firstReplyNodeId: result.assistantNode.id,
            speakerId: character.id,
          );
        } else {
          await _advanceGroupTurn();
        }
      }
    } on ChatCompletionCancelledException {
      // 用户主动终止，不弹错误提示。
    } finally {
      _resetPendingMessages();
      final reloadSessionId = persistedSession?.id;
      // v51：先加载（保持冻结，一次性更新消息）再解冻——避免先解冻
      // 再加载产生多次中间重建、流式结束后视口跳动
      try {
        if (reloadSessionId != null || !_isDraftSession) {
          await _loadSession(preferredSessionId: reloadSessionId ?? session.id);
        }
      } finally {
        _unfreezeMessages();
      }
      if (!_isDisposed) {
        // v78：发送状态在重载完成后复位——此前先复位再 await 重载，
        // 用户可在重载完成前的窗口立刻再发，第二条消息拿到旧会话
        // （currentLeafMessageId 未更新）入库成兄弟分支，上一轮对话
        // 从主链消失。重载抛异常也会走到这里复位，不会锁死。
        _isSending = false;
        // 无条件清空：全员回复链中途会替换 token，identical 检查会漏
        _activeCompletionCancelToken = null;
      }
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// 快捷指令：发送一条以 [command.name] 显示、以 [command.prompt] 作为
  /// 实际模型内容的用户消息。
  /// [extraText] 特别版：询问型指令的用户补充内容（追加到提示词后）。
  Future<void> sendQuickCommand(
    QuickCommand command, {
    String? extraText,
  }) async {
    final session = _activeSession;
    // 特别版：手动指定发言人优先，否则当前轮转角色
    final character = _resolveSpeaker(_activeCharacter);
    final name = command.name.trim();
    final prompt = command.prompt.trim();
    if (name.isEmpty ||
        prompt.isEmpty ||
        session == null ||
        character == null ||
        _isSwitchingSession ||
        _isSending ||
        _isImpersonating) {
      return;
    }
    final extra = extraText?.trim();
    final modelText = extra == null || extra.isEmpty
        ? prompt
        : '$prompt\n【用户补充】$extra';

    final cancellationToken = ChatCompletionCancelToken();
    _activeCompletionCancelToken = cancellationToken;
    _isSending = true;
    _pendingUserMessage = ChatMessage(text: name, isMe: true);
    _streamingAssistantText = '';
    _streamingThinkingChain = '';
    // 特别版：冻结列表（与 sendMessage 一致）
    _freezeMessages();
    notifyListeners();

    ChatSession? persistedSession;

    try {
      final result = await getIt<ChatService>().sendMessage(
        session: session,
        character: character,
        chatMessages: _messages,
        input: name,
        // 特别版：状态解析文本 = 用户补充内容。快捷指令的 [input] 只是
        // 指令名（如"旁白"），补充（如"烙印值提高40%"）只在 modelText 里，
        // 必须单独传 trackerText，否则本地状态解析看不到补充、状态不落地
        // （v49 确认的"快捷指令下状态不更新"根因）。
        trackerText: extra,
        selectedPresetId: _selectedPresetId,
        selectedUserSettingId: _selectedUserSettingId,
        selectedWorldBookIds: _resolvedWorldBookIds(character),
        groupCharacterNames: _groupNameMap,
        useStreaming: _useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: (progress) {
          if (_isDisposed) {
            return;
          }
          if (progress.textDelta.isNotEmpty) {
            _streamingAssistantText += progress.textDelta;
            // 重试收到首个正文 delta：清除重试提示（面板显示正文）
            if (_thinkingChainRetryNotice.isNotEmpty) {
              _thinkingChainRetryNotice = '';
            }
          }
          if (progress.thinkingDelta.isNotEmpty) {
            _streamingThinkingChain += progress.thinkingDelta;
          }
          notifyListeners();
        },
        onThinkingChainRetry: _onThinkingChainRetry,
        persistSession: _isDraftSession
            ? () async {
                final createdSession = await _persistDraftSession();
                persistedSession = createdSession;
                return createdSession;
              }
            : null,
        modelText: modelText,
        assistantCharacterId: _groupCharacters.isNotEmpty
            ? character.id
            : null,
      );
      // 用户中途停止的部分回复不算完整发言，不推进群聊轮转
      if (!result.completion.isPartial) {
        _lastPromptAssembly = result.promptAssembly;
        // 特别版：记录接口真实用量（usage），供用量页校准展示
        _lastRealUsage = result.completion.usageTokens;
        await _refreshContextUsage(result.promptAssembly);
        _manualSpeakerId = null;
        if (isEveryoneGroupChat) {
          // 特别版：全员回复模式——其余成员按顺序自动依次回复
          // （游标由链内统一推进，避免双重切换）
          await _runEveryoneTurn(
            firstReplyNodeId: result.assistantNode.id,
            speakerId: character.id,
          );
        } else {
          await _advanceGroupTurn();
        }
      }
    } on ChatCompletionCancelledException {
      // 用户主动终止，不弹错误提示。
    } finally {
      _resetPendingMessages();
      final reloadSessionId = persistedSession?.id;
      // v51：先加载（保持冻结，一次性更新消息）再解冻——避免先解冻
      // 再加载产生多次中间重建、流式结束后视口跳动
      try {
        if (reloadSessionId != null || !_isDraftSession) {
          await _loadSession(preferredSessionId: reloadSessionId ?? session.id);
        }
      } finally {
        _unfreezeMessages();
      }
      if (!_isDisposed) {
        // v78：发送状态在重载完成后复位——此前先复位再 await 重载，
        // 用户可在重载完成前的窗口立刻再发，第二条消息拿到旧会话
        // （currentLeafMessageId 未更新）入库成兄弟分支，上一轮对话
        // 从主链消失。重载抛异常也会走到这里复位，不会锁死。
        _isSending = false;
        // 无条件清空：全员回复链中途会替换 token，identical 检查会漏
        _activeCompletionCancelToken = null;
      }
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// 终止当前进行中的流式请求。
  void stopStreaming() {
    _activeCompletionCancelToken?.cancel();
  }

  Future<void> regenerateFromUserMessage({
    required int userMessageIndex,
    String? editedText,
    /// 特别版：编辑后发送给模型的完整内容（快捷指令占位展开后）。
    String? editedModelText,
    ChatMessage? userMessageOverride,
    List<ChatMessage>? historyBeforeOverride,
  }) async {
    final session = _activeSession;
    final character = _activeCharacter;
    if (session == null || character == null || _isSending || _isImpersonating) {
      return;
    }
    if (userMessageIndex < 0 || userMessageIndex >= _messages.length) {
      return;
    }

    final originalUserMessage =
        userMessageOverride ?? _messages[userMessageIndex];
    if (!originalUserMessage.isMe || originalUserMessage.id == null) {
      return;
    }

    final userMessage = ChatMessage(
      id: originalUserMessage.id,
      sessionId: originalUserMessage.sessionId,
      parentId: originalUserMessage.parentId,
      text: editedText ?? originalUserMessage.text,
      isMe: true,
      index: originalUserMessage.index,
      total: originalUserMessage.total,
      siblingIds: originalUserMessage.siblingIds,
      // 特别版：快捷指令消息重新生成时沿用其完整提示词
      modelText: editedText == null
          ? originalUserMessage.modelText
          : editedModelText,
    );
    final historyBeforeUserMessage =
        historyBeforeOverride ??
        _messages.take(userMessageIndex).toList(growable: false);

    _isSending = true;
    _pendingUserMessage = null;
    _regeneratingUserMessageId = userMessage.id;
    _streamingAssistantText = '';
    _streamingThinkingChain = '';
    // 特别版：冻结列表（AI 输出期间/完成后列表不变）
    _freezeMessages();
    notifyListeners();

    final cancellationToken = ChatCompletionCancelToken();
    _activeCompletionCancelToken = cancellationToken;
    try {
      await getIt<ChatService>().regenerateAssistantResponse(
        session: session,
        character: character,
        historyBeforeUserMessage: historyBeforeUserMessage,
        userMessage: userMessage,
        selectedPresetId: _selectedPresetId,
        selectedUserSettingId: _selectedUserSettingId,
        selectedWorldBookIds: _resolvedWorldBookIds(character),
        groupCharacterNames: _groupNameMap,
        useStreaming: _useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: (progress) {
          if (_isDisposed) {
            return;
          }
          if (progress.textDelta.isNotEmpty) {
            _streamingAssistantText += progress.textDelta;
            // 重试收到首个正文 delta：清除重试提示（面板显示正文）
            if (_thinkingChainRetryNotice.isNotEmpty) {
              _thinkingChainRetryNotice = '';
            }
          }
          if (progress.thinkingDelta.isNotEmpty) {
            _streamingThinkingChain += progress.thinkingDelta;
          }
          notifyListeners();
        },
        onThinkingChainRetry: _onThinkingChainRetry,
      );
    } on ChatCompletionCancelledException {
      // 用户主动终止，不弹错误提示；列表解冻恢复真实数据
      _unfreezeMessages();
    } catch (error) {
      // 其他异常：列表解冻恢复真实数据（错误由 UI 提示）
      _unfreezeMessages();
      rethrow;
    } finally {
      _resetPendingMessages();
      // v51：先加载（保持冻结，一次性更新消息）再解冻——避免先解冻
      // 再加载产生多次中间重建、流式结束后视口跳动
      try {
        await _loadSession(preferredSessionId: session.id);
      } finally {
        _unfreezeMessages();
      }
      if (!_isDisposed) {
        // v78：发送状态在重载完成后复位（重载抛异常也会走到这里复位）
        _isSending = false;
        // 无条件清空：全员回复链中途会替换 token，identical 检查会漏
        _activeCompletionCancelToken = null;
      }
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// 重新生成指定位置的角色消息（其上一条为用户消息）。
  Future<void> regenerateMessage(int assistantMessageIndex) async {
    if (_isSending || _isImpersonating) {
      return;
    }
    final session = _activeSession;
    final character = _activeCharacter;
    if (session == null || character == null) {
      return;
    }
    if (assistantMessageIndex <= 0 ||
        assistantMessageIndex >= _messages.length) {
      return;
    }

    final userMessage = _messages[assistantMessageIndex - 1];
    if (!userMessage.isMe || userMessage.id == null) {
      return;
    }

    await regenerateFromUserMessage(
      userMessageIndex: assistantMessageIndex - 1,
    );
  }

  /// 继续推进：基于最后一条角色消息生成新的角色消息。
  Future<void> continueAssistantMessage(int assistantMessageIndex) async {
    if (_isSending || _isImpersonating) {
      return;
    }
    final session = _activeSession;
    final character = _activeCharacter;
    if (session == null || character == null) {
      return;
    }
    if (assistantMessageIndex < 0 ||
        assistantMessageIndex >= _messages.length) {
      return;
    }
    if (assistantMessageIndex != _messages.length - 1) {
      return;
    }

    final lastAssistantMessage = _messages[assistantMessageIndex];
    if (lastAssistantMessage.isMe || lastAssistantMessage.id == null) {
      return;
    }

    final cancellationToken = ChatCompletionCancelToken();
    _activeCompletionCancelToken = cancellationToken;
    _isSending = true;
    _pendingUserMessage = null;
    _regeneratingUserMessageId = null;
    _streamingAssistantText = '';
    _streamingThinkingChain = '';
    // 特别版：冻结列表（AI 输出期间/完成后列表不变），
    // 先冻结再通知（与 sendMessage 一致）
    _freezeMessages();
    notifyListeners();

    try {
      await getIt<ChatService>().continueAssistantResponse(
        session: session,
        character: character,
        chatMessages: _messages,
        selectedPresetId: _selectedPresetId,
        selectedUserSettingId: _selectedUserSettingId,
        selectedWorldBookIds: _resolvedWorldBookIds(character),
        groupCharacterNames: _groupNameMap,
        useStreaming: _useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: (progress) {
          if (_isDisposed) {
            return;
          }
          if (progress.textDelta.isNotEmpty) {
            _streamingAssistantText += progress.textDelta;
            // 重试收到首个正文 delta：清除重试提示（面板显示正文）
            if (_thinkingChainRetryNotice.isNotEmpty) {
              _thinkingChainRetryNotice = '';
            }
          }
          if (progress.thinkingDelta.isNotEmpty) {
            _streamingThinkingChain += progress.thinkingDelta;
          }
          notifyListeners();
        },
        onThinkingChainRetry: _onThinkingChainRetry,
      );
    } on ChatCompletionCancelledException {
      // 用户主动终止，不弹错误提示；列表解冻恢复真实数据
      _unfreezeMessages();
    } catch (error) {
      // 其他异常：列表解冻恢复真实数据（错误由 UI 提示）
      _unfreezeMessages();
      rethrow;
    } finally {
      _resetPendingMessages();
      // v51：先加载（保持冻结，一次性更新消息）再解冻——避免先解冻
      // 再加载产生多次中间重建、流式结束后视口跳动
      try {
        await _loadSession(preferredSessionId: session.id);
      } finally {
        _unfreezeMessages();
      }
      if (!_isDisposed) {
        // v78：发送状态在重载完成后复位（重载抛异常也会走到这里复位）
        _isSending = false;
        // 无条件清空：全员回复链中途会替换 token，identical 检查会漏
        _activeCompletionCancelToken = null;
      }
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// 助手帮答：生成一条用户回复文本，由 UI 层填入输入框。
  /// 返回 null 表示当前不可用或被取消。
  /// [onProgress] 在流式生成时回调累积文本。
  Future<String?> generateUserReply({
    void Function(String accumulatedText)? onProgress,
  }) async {
    final session = _activeSession;
    final character = _activeCharacter;
    if (session == null || character == null) {
      return null;
    }
    if (_isSending || _isImpersonating || _isSwitchingSession) {
      return null;
    }
    if (_messages.isEmpty) {
      return null;
    }

    final cancellationToken = ChatCompletionCancelToken();
    _activeCompletionCancelToken = cancellationToken;
    _isImpersonating = true;
    _streamingImpersonationText = '';
    notifyListeners();

    try {
      return await getIt<ChatService>().generateUserReply(
        session: session,
        character: character,
        chatMessages: _messages,
        selectedPresetId: _selectedPresetId,
        selectedUserSettingId: _selectedUserSettingId,
        selectedWorldBookIds: _selectedWorldBookIds,
        useStreaming: _useStreaming,
        cancellationToken: cancellationToken,
        onStreamProgress: (progress) {
          if (_isDisposed) {
            return;
          }
          if (progress.textDelta.isNotEmpty) {
            _streamingImpersonationText += progress.textDelta;
            onProgress?.call(_streamingImpersonationText);
          }
        },
      );
    } on ChatCompletionCancelledException {
      return null;
    } finally {
      _isImpersonating = false;
      _streamingImpersonationText = '';
      if (identical(_activeCompletionCancelToken, cancellationToken)) {
        _activeCompletionCancelToken = null;
      }
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  // --- 消息操作 ---

  /// 编辑消息。[text] 为对话框返回的已规范化文本（用户消息未做变量替换）。
  Future<void> editMessage(
    int index,
    String text,
    MessageEditAction action, {
    /// 特别版：编辑后发送给模型的完整内容（快捷指令占位展开后）。
    /// null 时与 [text] 一致。
    String? modelText,
  }) async {
    final session = _activeSession;
    final message = index >= 0 && index < _messages.length
        ? _messages[index]
        : null;
    if (session == null ||
        message == null ||
        message.id == null ||
        _isSending) {
      return;
    }
    final editingMessage = message;

    var normalizedText = text;
    if (editingMessage.isMe) {
      normalizedText = replaceChatVariables(normalizedText).trim();
    } else {
      normalizedText = normalizedText.trim();
    }

    if (editingMessage.isMe && action == MessageEditAction.saveAndSend) {
      final editedNode = await getIt<ChatDatabaseService>()
          .branchMessageFromEdit(
            sessionId: session.id,
            messageId: editingMessage.id!,
            text: normalizedText,
            // 特别版：分支消息保留展开后的快捷指令提示词
            modelText: modelText,
          );

      await regenerateFromUserMessage(
        userMessageIndex: index,
        userMessageOverride: ChatMessage(
          id: editedNode.id,
          sessionId: editedNode.sessionId,
          parentId: editedNode.parentId,
          text: editedNode.text,
          isMe: true,
          modelText: modelText,
        ),
        historyBeforeOverride: _messages.take(index).toList(growable: false),
      );
      return;
    }

    await getIt<ChatDatabaseService>().updateMessage(
      sessionId: session.id,
      messageId: editingMessage.id!,
      text: normalizedText,
      thinkingChain: editingMessage.isMe ? null : editingMessage.thinkingChain,
      clearThinkingChain:
          editingMessage.isMe || editingMessage.thinkingChain == null,
      modelText: modelText,
    );

    if (action == MessageEditAction.saveAndSend) {
      await regenerateFromUserMessage(
        userMessageIndex: index,
        editedText: normalizedText,
        editedModelText: modelText,
      );
      return;
    }

    await _loadSession(preferredSessionId: session.id);
  }

  /// 编辑草稿会话的开场消息。
  Future<void> editDraftOpeningMessage(String text) async {
    final session = _activeSession;
    if (!_isDraftSession ||
        session == null ||
        _isSending ||
        _draftOpeningAssistantMessages.isEmpty) {
      return;
    }
    final editingIndex = _draftOpeningMessageIndex.clamp(
      0,
      _draftOpeningAssistantMessages.length - 1,
    );

    final normalizedText = text.trim();
    final nextOpeningMessages = List<String>.from(
      _draftOpeningAssistantMessages,
    );
    nextOpeningMessages[editingIndex] = normalizedText;
    _draftOpeningAssistantMessages = nextOpeningMessages;
    _messages = _buildDraftOpeningMessages(nextOpeningMessages);
    _activeSession = session.copyWith(lastMessagePreview: normalizedText);
    notifyListeners();
  }

  /// 删除指定位置的消息分支。
  Future<void> deleteMessage(int index) async {
    final session = _activeSession;
    final message = index >= 0 && index < _messages.length
        ? _messages[index]
        : null;
    if (session == null || message?.id == null || _isSending) {
      return;
    }

    await getIt<ChatDatabaseService>().deleteMessageBranch(
      sessionId: session.id,
      messageId: message!.id!,
    );
    await _loadSession(preferredSessionId: session.id);
  }

  /// 切换消息变体（分支）。[delta] 为 -1 或 1。
  Future<void> switchMessageVariant(ChatMessage message, int delta) async {
    if (_isDraftSession) {
      if (message.isMe || _draftOpeningAssistantMessages.length <= 1) {
        return;
      }
      final nextIndex = (_draftOpeningMessageIndex + delta).clamp(
        0,
        _draftOpeningAssistantMessages.length - 1,
      );
      if (nextIndex == _draftOpeningMessageIndex) {
        return;
      }
      _draftOpeningMessageIndex = nextIndex;
      _messages = _buildDraftOpeningMessages(_draftOpeningAssistantMessages);
      _activeSession = _activeSession?.copyWith(
        lastMessagePreview:
            _draftOpeningAssistantMessages[_draftOpeningMessageIndex],
      );
      notifyListeners();
      return;
    }

    final session = _activeSession;
    if (session == null || message.id == null || message.siblingIds.isEmpty) {
      return;
    }

    final currentIndex = message.index - 1;
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= message.siblingIds.length) {
      return;
    }

    await getIt<ChatDatabaseService>().switchActiveBranch(
      sessionId: session.id,
      parentMessageId: message.parentId,
      childMessageId: message.siblingIds[nextIndex],
    );
    await _loadSession(preferredSessionId: session.id);
  }

  // --- 会话配置操作 ---

  /// 更新选中的用户设定并持久化。
  Future<void> setSelectedUserSettingId(String id) async {
    _selectedUserSettingId = id;
    notifyListeners();
    await _persistSessionConfig();
  }

  /// 切换世界书选中状态并持久化。
  Future<void> toggleWorldBook(String id) async {
    if (_selectedWorldBookIds.contains(id)) {
      _selectedWorldBookIds.remove(id);
    } else {
      _selectedWorldBookIds.add(id);
    }
    notifyListeners();
    await _persistSessionConfig();
  }

  /// 更新选中的预设并持久化。
  Future<void> setSelectedPresetId(String id) async {
    _selectedPresetId = id;
    notifyListeners();
    await _persistSessionConfig();
  }

  /// 更新流式开关。
  void setUseStreaming(bool value) {
    _useStreaming = value;
    notifyListeners();
  }

  /// 重命名当前会话标题。
  Future<void> renameChatTitle(String title) async {
    final session = _activeSession;
    if (session == null) {
      return;
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty || normalizedTitle == session.title) {
      return;
    }

    if (_isDraftSession) {
      _activeSession = session.copyWith(title: normalizedTitle);
      notifyListeners();
      return;
    }

    await getIt<ChatDatabaseService>().updateSessionTitle(
      sessionId: session.id,
      title: normalizedTitle,
    );
    if (_isDisposed) {
      return;
    }
    _activeSession = session.copyWith(title: normalizedTitle);
    notifyListeners();
  }

  /// 重置当前聊天（按当前选择重新初始化）。成功完成不抛异常。
  Future<void> resetChat(String nextTitle) async {
    final session = _activeSession;
    final character = _activeCharacter;
    if (session == null || character == null || _isSending) {
      return;
    }
    // 特别版：重置会话时解除列表冻结（避免旧快照残留）
    _unfreezeMessages();

    final selectedUserSettingId = currentUserSetting()?.id;
    final opening = ChatDisplaySanitizer.extractOpeningMessages(
      ChatOpeningMessageBuilder.build(
        characterCardData: character.cardJson,
        characterName: character.name,
        userName: resolvedUserName(),
      ),
    );
    final openingMessages = opening.messages;
    final openingStatusHtml = opening.specialStatusHtml;

    if (_isDraftSession) {
      _resetPendingMessages();
      _draftOpeningMessageIndex = 0;
      _draftOpeningAssistantMessages = openingMessages;
      _draftOpeningStatusHtml = ChatViewModel._cleanupHtml(openingStatusHtml);
      _messages = _buildDraftOpeningMessages(openingMessages);
      _selectedUserSettingId = selectedUserSettingId;
      _activeSession = session.copyWith(
        title: nextTitle,
        selectedUserSettingId: selectedUserSettingId,
        selectedWorldBookIds: _selectedWorldBookIds.toList(),
        selectedPresetId: _selectedPresetId,
        lastMessagePreview: openingMessages.isNotEmpty
            ? openingMessages.first
            : '',
      );
      notifyListeners();
      return;
    }

    _isLoading = true;
    _resetPendingMessages();
    notifyListeners();

    try {
      await getIt<ChatDatabaseService>().resetSession(
        sessionId: session.id,
        title: nextTitle,
        selectedUserSettingId: selectedUserSettingId,
        selectedWorldBookIds: _selectedWorldBookIds.toList(),
        selectedPresetId: _selectedPresetId,
        openingAssistantMessages: openingMessages,
      );
      // 非 draft：resetSession 之后再写开场状态栏（避免被 reset 清掉）
      await _persistSpecialStatusHtml(session.id, openingStatusHtml);
      await _loadSession(preferredSessionId: session.id);
    } catch (error) {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// 处理用户设定被删除后的状态同步。
  Future<void> handleUserSettingDeleted(String settingId) async {
    await deleteUserSetting(settingId);
    if (_selectedUserSettingId == settingId) {
      _selectedUserSettingId = userSettingsNotifier.value.isNotEmpty
          ? userSettingsNotifier.value.first.id
          : null;
    }
    notifyListeners();
  }

  /// 处理用户设定被更新。
  Future<void> handleUserSettingUpdated(UserSetting setting) async {
    await updateUserSetting(setting);
    notifyListeners();
  }

  // --- 测试辅助 ---

  /// 仅供测试使用：批量覆盖内部状态，便于在不依赖 service 的前提下
  /// 测试 [visibleMessages]、[sendMessage] 守卫等纯逻辑。
  @visibleForTesting
  void setStateForTesting({
    ChatSession? activeSession,
    ResolvedChatCharacter? activeCharacter,
    List<ChatMessage>? messages,
    bool? isSending,
    bool? isSwitchingSession,
    bool? useStreaming,
    ChatMessage? pendingUserMessage,
    String? regeneratingUserMessageId,
    String? streamingAssistantText,
    String? streamingThinkingChain,
    bool? isDraftSession,
    String? selectedUserSettingId,
    String? selectedPresetId,
    /// 特别版：冻结视图（测试用）
    List<ChatMessage>? frozenVisibleMessages,
  }) {
    if (activeSession != null) _activeSession = activeSession;
    if (activeCharacter != null) _activeCharacter = activeCharacter;
    if (messages != null) _messages = messages;
    if (isSending != null) _isSending = isSending;
    if (isSwitchingSession != null) _isSwitchingSession = isSwitchingSession;
    if (useStreaming != null) _useStreaming = useStreaming;
    _pendingUserMessage = pendingUserMessage;
    _regeneratingUserMessageId = regeneratingUserMessageId;
    if (streamingAssistantText != null) {
      _streamingAssistantText = streamingAssistantText;
    }
    if (streamingThinkingChain != null) {
      _streamingThinkingChain = streamingThinkingChain;
    }
    if (isDraftSession != null) _isDraftSession = isDraftSession;
    if (selectedUserSettingId != null) {
      _selectedUserSettingId = selectedUserSettingId;
    }
    if (selectedPresetId != null) _selectedPresetId = selectedPresetId;
    if (frozenVisibleMessages != null) {
      _frozenVisibleMessages = frozenVisibleMessages;
    }
  }

  // --- 私有辅助 ---

  void _resetPendingMessages() {
    _pendingUserMessage = null;
    _regeneratingUserMessageId = null;
    _streamingAssistantText = '';
    _streamingThinkingChain = '';
    _thinkingChainRetryNotice = '';
  }

  /// 思维链重试/瞬时错误重试回调：清空本次输出并显示重试提示。
  /// [reason] 由调用方提供完整提示文案。
  void _onThinkingChainRetry(int attempt, String reason) {
    if (_isDisposed) {
      return;
    }
    _streamingAssistantText = '';
    _streamingThinkingChain = '';
    _thinkingChainRetryNotice = '⚠️ $reason';
    notifyListeners();
  }

  /// 特别版：接口返回的真实 token 用量（发送成功后更新；会话切换清空）。
  ChatCompletionUsage? _lastRealUsage;

  /// 特别版：最近一次接口真实用量（发送后可用；null 表示尚无/流式未返回）。
  ChatCompletionUsage? get lastRealUsage => _lastRealUsage;

  /// 特别版：会话打开时的轻量用量估算（不组装完整 prompt，不卡 UI）。
  ///
  /// 口径与发送后的精确统计一致：中文≈1 字/token、英文≈4 字符/token；
  /// 统计历史消息文本 + 角色卡 description/personality/scenario +
  /// 思维链模板与尾部提醒。发送成功后由 [_refreshContextUsage] 精确覆盖。
  /// v61：Tracker 状态指令估算——与 chat_service._trackerStateText
  /// 同源（formatTrackerInstruction + 固定协议尾部），避免上下文用量
  /// 漏算 Tracker 每轮常驻指令。返回 null 表示卡未启用 tracker。
  /// v73：按状态更新模式选协议尾部——快速=kInlineTrackerProtocolSuffix
  /// （<TRACKER_UPDATE> 标记协议），后台/严格=kStoryOnlySuffix（只输出
  /// 正文，状态由裁判决定）——与实际发送的提示一致（之前固定用旧
  /// kTrackerProtocolSuffix，估算与实发不符）。
  String? _estimateTrackerInstructionText() {
    final card = _activeCharacter?.cardJson;
    if (card == null) {
      return null;
    }
    final config = TrackerConfig.fromCardJson(card);
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
    final variables = _sessionVariablesCache;
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
    // v73：估算与实际发送同源（模式决定协议尾部）
    final protocolTail =
        appSettingsNotifier.value.trackerUpdateMode == TrackerUpdateMode.quick
            ? TrackerRuntime.kInlineTrackerProtocolSuffix
            : TrackerRuntime.kStoryOnlySuffix;
    return '$text\n\n$protocolTail';
  }

  Future<void> _refreshContextEstimate() async {
    final loadGeneration = _sessionLoadGeneration;
    var total = 0;
    for (final msg in _messages) {
      total += estimateContextTokens(msg.text);
    }
    final card = _activeCharacter?.cardJson;
    if (card != null) {
      try {
        final data = (card['data'] as Map<String, dynamic>?) ?? card;
        total += estimateContextTokens((data['description'] as String?) ?? '');
        total += estimateContextTokens((data['personality'] as String?) ?? '');
        total += estimateContextTokens((data['scenario'] as String?) ?? '');
      } catch (_) {
        // 角色卡字段类型不规范时忽略角色卡部分
      }
    }
    try {
      final template = await getIt<ThinkingChainPresetService>()
          .resolveActiveTemplate();
      total += estimateContextTokens(template);
    } catch (_) {
      // 模板解析失败时忽略
    }
    total += estimateContextTokens(ThinkingChainGuard.thinkingChainTailReminder);
    // v61：Tracker 每轮常驻指令计入估算（状态 + 规则 + 输出协议）
    final trackerText = _estimateTrackerInstructionText();
    if (trackerText != null) {
      total += estimateContextTokens(trackerText);
    }
    // 估算期间会话已切换：丢弃旧值（发送后精确值会覆盖）
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }
    _lastContextTotal = total;
    _lastContextMax = await _resolveContextMax();
    if (_isDisposed || loadGeneration != _sessionLoadGeneration) {
      return;
    }
    notifyListeners();
  }

  /// 特别版：刷新上下文用量缓存（发送成功后调用）。
  /// 与用量页面口径一致：模板 + 尾部提醒 + Tracker 指令计入总量。
  Future<void> _refreshContextUsage(PromptAssemblyResult assembly) async {
    String template = '';
    try {
      template = await getIt<ThinkingChainPresetService>()
          .resolveActiveTemplate();
    } catch (_) {
      // 模板解析失败时仅按消息统计
    }
    final breakdown = breakdownContextTokens(
      assembly,
      templateText: template,
      tailReminder: ThinkingChainGuard.thinkingChainTailReminder,
    );
    var total = breakdown.sections.values.fold<int>(
          0, (s, v) => s + v) +
        breakdown.worldBookEntries.fold<int>(0, (s, e) => s + e.tokens) +
        breakdown.chatHistory.fold<int>(0, (s, m) => s + m.tokens);
    // v61：Tracker 每轮常驻指令计入（注入发生在组装之后，分解不含）
    final trackerText = _estimateTrackerInstructionText();
    if (trackerText != null) {
      total += estimateContextTokens(trackerText);
    }
    _lastContextTotal = total;
    _lastContextMax = await _resolveContextMax();
  }

  /// 特别版：解析最大上下文——预设"高级参数"里的上下文（用户改过时）
  /// 优先，其次当前模型的 contextWindow，最后默认 128000。
  Future<int> _resolveContextMax() async {
    var modelWindow = 128000;
    final selectedId = selectedApiModelIdNotifier.value;
    var found = false;
    for (final config in apiConfigsNotifier.value) {
      for (final model in config.models) {
        if (model.id == selectedId) {
          // 首个匹配即采用（与 chat_page 打开页面的口径一致）
          modelWindow = model.contextWindow;
          found = true;
          break;
        }
      }
      if (found) break;
    }
    final presetId = _selectedPresetId;
    if (presetId != null && presetId.isNotEmpty) {
      try {
        final preset = await getIt<PresetService>().loadById(presetId);
        if (preset != null &&
            preset.openaiMaxContext > 0 &&
            preset.openaiMaxContext != 131072) {
          return preset.openaiMaxContext;
        }
      } catch (_) {
        // 预设加载失败时回退模型配置
      }
    }
    return modelWindow;
  }

  @override
  void dispose() {
    _isDisposed = true;
    apiConfigsNotifier.removeListener(onApiConfigsChanged);
    selectedApiModelIdNotifier.removeListener(onApiConfigsChanged);
    _chatDbChangeNotifier.removeListener(_onDbChangedBroadcast);
    _presetChangeNotifier.removeListener(onPresetsChanged);
    _activeCompletionCancelToken?.cancel();
    super.dispose();
  }
}
