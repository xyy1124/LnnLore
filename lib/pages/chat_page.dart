import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';
import '../data/api_configs.dart';
import '../data/mock_user_settings.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/quick_command.dart';
import '../pages/api_config_page.dart';
import '../pages/api_request_log_page.dart';
import '../pages/chat/chat_view_model.dart';
import '../pages/chat/context_usage_page.dart';
import '../pages/chat/widgets/api_selector_sheet.dart';
import '../pages/chat/widgets/chat_input_area.dart';
import '../pages/chat/widgets/chat_message_list.dart';
import '../pages/chat/widgets/chat_selector_menus.dart';
import '../pages/chat/widgets/chat_title_dialog.dart';
import '../pages/chat/widgets/memory_tree_page.dart';
import '../pages/chat/widgets/message_edit_dialog.dart';
import '../pages/chat/widgets/quick_command_marks.dart';
import '../pages/chat/widgets/quick_command_text_editing_controller.dart';
import '../pages/chat_sidebar_page.dart';
import '../pages/preset_edit_page.dart';
import '../pages/user_settings_page.dart';
import '../pages/world_book_edit_page.dart';
import '../services/chat_database_service.dart';
import '../services/preset_service.dart';
import '../services/quick_command_service.dart';
import '../services/world_book_service.dart';

/// 聊天页面
class ChatPage extends StatefulWidget {
  final String? sessionId;
  final String? draftCharacterId;
  final String? draftTitle;
  final String? draftSelectedUserSettingId;
  final String? draftSelectedPresetId;
  final List<String> draftSelectedWorldBookIds;
  final List<String> draftOpeningAssistantMessages;
  /// 特别版：草稿开场里提取的特殊状态栏 HTML
  final String? draftOpeningStatusHtml;
  /// 特别版：群聊（创建时传入）
  final String? draftGroupId;
  final String? draftGroupTitle;
  final List<String> draftGroupCharacterIds;

  const ChatPage({super.key, this.sessionId})
    : draftCharacterId = null,
      draftTitle = null,
      draftSelectedUserSettingId = null,
      draftSelectedPresetId = null,
      draftSelectedWorldBookIds = const [],
      draftOpeningAssistantMessages = const [],
      draftOpeningStatusHtml = null,
      draftGroupId = null,
      draftGroupTitle = null,
      draftGroupCharacterIds = const [];

  const ChatPage.draft({
    super.key,
    String? characterId,
    String? title,
    String? selectedUserSettingId,
    String? selectedPresetId,
    List<String> selectedWorldBookIds = const [],
    List<String> openingAssistantMessages = const [],
    String? openingStatusHtml,
    String? groupId,
    String? groupTitle,
    List<String> groupCharacterIds = const [],
  }) : sessionId = null,
       draftCharacterId = characterId,
       draftTitle = title,
       draftSelectedUserSettingId = selectedUserSettingId,
       draftSelectedPresetId = selectedPresetId,
       draftSelectedWorldBookIds = selectedWorldBookIds,
       draftOpeningAssistantMessages = openingAssistantMessages,
       draftOpeningStatusHtml = openingStatusHtml,
       draftGroupId = groupId,
       draftGroupTitle = groupTitle,
       draftGroupCharacterIds = groupCharacterIds;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // 特别版：快捷指令富文本控制器（占位标记斜体彩色显示）
  final TextEditingController _textController =
      QuickCommandTextEditingController();

  final FocusNode _inputFocusNode = FocusNode();
  final Object _inputTapRegionGroupId = Object();
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  String _inputText = '';

  late final ChatViewModel _viewModel;

  /// 特别版：快捷指令列表。
  List<QuickCommand> _quickCommands = const [];

  @override
  void initState() {
    super.initState();
    _viewModel = ChatViewModel(
      preferredSessionId: widget.sessionId,
      draftCharacterId: widget.draftCharacterId,
      draftTitle: widget.draftTitle,
      draftSelectedUserSettingId: widget.draftSelectedUserSettingId,
      draftSelectedPresetId: widget.draftSelectedPresetId,
      draftSelectedWorldBookIds: widget.draftSelectedWorldBookIds,
      initialDraftOpeningMessages: widget.draftOpeningAssistantMessages,
      draftOpeningStatusHtml: widget.draftOpeningStatusHtml,
      draftGroupId: widget.draftGroupId,
      draftGroupTitle: widget.draftGroupTitle,
      draftGroupCharacterIds: widget.draftGroupCharacterIds,
    );
    _viewModel.addListener(_onViewModelChanged);
    _textController.addListener(_onTextChanged);
    // 用户滚动监听改走 NotificationListener（真实手势才保存，
    // controller listener 会误记录自动跳底/布局校正）。
    _viewModel.onSessionReloaded = _onSessionReloaded;
    _viewModel.initialize();
    _loadQuickCommands();
    // v74：快捷指令在管理页新增/编辑/删除后自动重载——
    // 之前只在 initState 加载一次，新指令要等下次进聊天页才显示
    QuickCommandService.instance.addListener(_onQuickCommandsChanged);
  }

  /// v74：快捷指令变化（新增/编辑/删除）时重载列表。
  void _onQuickCommandsChanged() {
    _loadQuickCommands();
  }

  /// 加载快捷指令（供输入框上方的快捷指令栏使用）。
  Future<void> _loadQuickCommands() async {
    final commands = await QuickCommandService.instance.loadAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _quickCommands = commands;
    });
  }

  void _onTextChanged() {
    if (_inputText == _textController.text) {
      return;
    }
    setState(() {
      _inputText = _textController.text;
    });
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    // v74：移除快捷指令监听
    QuickCommandService.instance.removeListener(_onQuickCommandsChanged);
    _textController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  /// 特别版：AI 输出期间与完成后的视口锁定。
  ///
  /// 采用"列表冻结 + 普通列表（reverse: false）"方案：发送时 VM 把
  /// 列表快照冻结（_frozenVisibleMessages），AI 输出期间 ListView 数据
  /// 完全不变（流式文本在列表外悬浮面板）；输出结束 VM 自动解冻，
  /// 新消息追加到非 reverse 列表尾部**不顶动视口**——从头到尾
  /// 界面都不动，无需任何滚动补偿。
  ///
  /// 会话打开/切换的滚动策略：
  /// - 每个 sessionId 手动保存浏览位置（[keepScrollOffset] 保持 false，
  ///   仅影响打开/切换历史会话，不干扰当前会话内输出稳定）；
  /// - 切换会话时优先恢复该会话上次保存的 offset；
  /// - 从未打开过（无保存记录）的会话：多帧等待布局稳定后再跳到底部
  ///   （长列表 / 图片 / Markdown / 群成员恢复都会让 maxScrollExtent
  ///   在首帧之后继续变化，不能只 jumpTo 一次）；
  /// - 同一会话内的 reload、AI streaming、回复完成、正文合入、
  ///   [_onViewModelChanged] 均不触发任何 jumpTo/animateTo。
  String? _lastLoadedSessionId;

  /// 特别版：列表末尾的真实底部锚点（bottom anchor）。
  /// 跳底统一走 Scrollable.ensureVisible 对齐该锚点，不再只信
  /// maxScrollExtent（ListView.builder 估算偏大时会出现"假底部"白空白）。
  final GlobalKey _bottomAnchorKey = GlobalKey();

  /// 每个会话上次的浏览位置（进程内记忆；退出 app 后重置为跳底）。
  /// 保存 pixels + wasAtBottom：上次在底部时不再恢复旧 pixels
  /// （图片/Markdown 高度变化后旧 pixels ≠ 新底部），而是重新可靠跳底。
  final Map<String, ChatScrollState> _sessionScrollStates = {};

  /// 自动滚动恢复/跳底的竞态令牌：新会话切换使旧恢复链立即失效。
  int _scrollRestoreToken = 0;

  /// v59：解冻后像素恢复令牌（_preserveOffsetAfterUnfreeze 用）。
  int _viewportRestoreToken = 0;

  /// 是否正在执行自动滚动恢复（此期间禁止把位置写回保存 Map）。
  bool _restoringScroll = false;

  /// 待恢复的会话（消息真正加载完成前只登记，不执行）。
  String? _pendingRestoreSessionId;
  double? _pendingRestoreTarget;
  bool _pendingRestoreWasAtBottom = false;

  void _onSessionReloaded() {
    // 注意：不清空输入框——发送后 reload 会触发本回调，用户等待
    // 回复期间新打的草稿不能被误删（发送时 UI 已清一次）。
    final session = _viewModel.activeSession;
    final id = session?.id;
    if (id == null) {
      return;
    }
    if (id == _lastLoadedSessionId) {
      // 同一会话 reload（发送/重生成/删除后）：保持视口不动；
      // 但若存在未执行的 pending 恢复（消息尚未加载完时触发的切换），
      // 不能直接吞掉——等消息真正加载完成后继续。
      if (_pendingRestoreSessionId == id) {
        _drainPendingRestoreIfReady(id);
      }
      return;
    }
    _lastLoadedSessionId = id;
    // 新会话登记时重置尝试计数（避免继承旧会话的计数）
    _pendingRestoreAttempts = 0;
    final saved = _sessionScrollStates[id];
    if (saved != null && !saved.wasAtBottom) {
      // 上次浏览位置在中间：登记待恢复，等消息加载完成后恢复
      _pendingRestoreSessionId = id;
      _pendingRestoreTarget = saved.pixels;
      _pendingRestoreWasAtBottom = false;
      _drainPendingRestoreIfReady(id);
    } else {
      // 从未打开过，或上次就在底部：登记可靠跳底
      _pendingRestoreSessionId = id;
      _pendingRestoreTarget = null;
      _pendingRestoreWasAtBottom = saved?.wasAtBottom ?? false;
      _drainPendingRestoreIfReady(id);
    }
  }

  /// 消息列表已挂载且（视情况）非空时，执行挂起的滚动恢复。
  /// 同一会话 reload 不再吞掉 pending；超过重试上限后放弃（防止空
  /// draft 会话永不 attach 导致无限帧循环）。
  int _pendingRestoreAttempts = 0;
  void _drainPendingRestoreIfReady(String id) {
    if (_pendingRestoreSessionId != id) {
      return;
    }
    // 等待列表挂载（hasClients）+ 至少一帧布局；中间位置恢复需等
    // 消息非空（避免空列表/半列表时恢复）。
    if (!_scrollController.hasClients) {
      _pendingRestoreAttempts++;
      if (_pendingRestoreAttempts > 30) {
        _clearPendingRestore();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingRestoreSessionId == id) {
          _drainPendingRestoreIfReady(id);
        }
      });
      return;
    }
    if (!_pendingRestoreWasAtBottom &&
        _viewModel.visibleMessages.isEmpty) {
      _pendingRestoreAttempts++;
      if (_pendingRestoreAttempts > 30) {
        _clearPendingRestore();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingRestoreSessionId == id) {
          _drainPendingRestoreIfReady(id);
        }
      });
      return;
    }
    final target = _pendingRestoreTarget;
    _clearPendingRestore();
    if (target == null) {
      unawaited(_scrollToBottomReliably(id));
    } else {
      _scheduleScrollRestore(id, target);
    }
  }

  void _clearPendingRestore() {
    _pendingRestoreSessionId = null;
    _pendingRestoreTarget = null;
    _pendingRestoreWasAtBottom = false;
    _pendingRestoreAttempts = 0;
  }

  /// 可靠跳到底部：先用 maxScrollExtent 粗滚到底部区域，等末尾 bottom
  /// anchor 被构建出来后，用 Scrollable.ensureVisible 显式对齐真实底部。
  /// ensureVisible 既能继续往下滚，也能在滚过头（白空白）时往回修正。
  /// 仅会话切换与"到底"按钮调用；输出期间不调用。
  Future<void> _scrollToBottomReliably(
    String sessionId, {
    bool animated = false,
  }) async {
    final token = ++_scrollRestoreToken;
    _restoringScroll = true;

    try {
      var stableCount = 0;
      double? lastTarget;

      for (var i = 0; i < 40; i++) {
        await WidgetsBinding.instance.endOfFrame;

        // v51：生成/重生成期间立即放弃滚动恢复——否则打开会话后的
        // 自动跳底循环会在发送期间继续 ensureVisible，把视口拉走
        if (_viewModel.isSending) {
          return;
        }

        if (!mounted ||
            token != _scrollRestoreToken ||
            _viewModel.activeSession?.id != sessionId) {
          return;
        }

        if (!_scrollController.hasClients) {
          continue;
        }

        final anchorContext = _bottomAnchorKey.currentContext;
        if (anchorContext == null) {
          // 锚点尚未构建：先粗滚到估算底部，下一轮等锚点出现
          // v59：执行前再查令牌/生成状态（布局等待期间可能开始生成）
          if (token != _scrollRestoreToken || _viewModel.isSending) {
            return;
          }
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent.clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            ),
          );
          continue;
        }

        // v59：ensureVisible 前再查令牌/生成状态
        if (token != _scrollRestoreToken || _viewModel.isSending) {
          return;
        }
        await Scrollable.ensureVisible(
          anchorContext,
          alignment: 1.0,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: animated && i == 0
              ? const Duration(milliseconds: 220)
              : Duration.zero,
          curve: Curves.easeOut,
        );

        await WidgetsBinding.instance.endOfFrame;

        if (!_scrollController.hasClients ||
            token != _scrollRestoreToken) {
          return;
        }

        final target = _scrollController.position.pixels;
        final last = lastTarget;
        final stable = last != null && (target - last).abs() < 0.5;
        lastTarget = target;

        if (stable) {
          stableCount++;
        } else {
          stableCount = 0;
        }

        if (stableCount >= 2) {
          return;
        }
      }
    } finally {
      if (token == _scrollRestoreToken) {
        _restoringScroll = false;
      }
    }
  }

  /// 多帧等待布局稳定后滚动到目标（已保存的浏览位置恢复）。
  /// 仅会话切换时调用；当前会话内的任何数据变化都不走这里。
  /// v59：加统一令牌 + isSending/frozen/sessionId 检查——之前无令牌，
  /// 用户在等待期间开始生成/手动滚动时，它仍会在布局稳定后突然
  /// jumpTo（"有时跳底、有时不跳"根因之一）。
  void _scheduleScrollRestore(String sessionId, double? target) {
    final token = ++_scrollRestoreToken;
    var attempts = 0;
    double? lastMax;
    void attempt() {
      if (!mounted ||
          token != _scrollRestoreToken ||
          _viewModel.isSending ||
          _viewModel.isMessagesFrozen ||
          _viewModel.activeSession?.id != sessionId) {
        // 令牌失效（生成开始/用户拖动/会话切换）或等待期间开始生成
        // 或冻结：放弃本次恢复
        return;
      }
      if (!_scrollController.hasClients) {
        // 列表尚未挂载（重建时序偏差）：下一帧再试，而非静默丢失
        if (attempts < 30) {
          attempts++;
          WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
        }
        return;
      }
      final position = _scrollController.position;
      final max = position.maxScrollExtent;
      final settled = lastMax != null && (max - lastMax!).abs() < 0.5;
      lastMax = max;
      if (!settled && attempts < 30) {
        // 布局仍在变化（异步加载/群成员恢复）：下一帧再检查
        attempts++;
        WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
        return;
      }
      // 布局稳定（或重试上限兜底）：执行前再查一次令牌/生成状态
      if (token != _scrollRestoreToken ||
          _viewModel.isSending ||
          _viewModel.isMessagesFrozen) {
        return;
      }
      _restoringScroll = true;
      _scrollController.jumpTo(target!.clamp(0.0, max));
      _restoringScroll = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
  }

  /// 滚动位置记录（仅真实用户滚动期间保存；自动恢复期间不写回）。
  void _onUserScroll() {
    if (_restoringScroll) {
      // 自动跳底/恢复产生的 offset 不污染保存位置
      return;
    }
    // v59：用户开始拖动时统一取消所有待执行自动滚动任务——
    // 之前只让 _scrollToBottomReliably 令牌失效，无令牌的
    // _scheduleScrollRestore 仍会在布局稳定后突然 jumpTo。
    _cancelAutomaticScrollWork();
    final id = _lastLoadedSessionId;
    if (id == null || !_scrollController.hasClients) {
      return;
    }
    final pos = _scrollController.position;
    _sessionScrollStates[id] = ChatScrollState(
      pixels: pos.pixels,
      wasAtBottom: pos.extentAfter <= 24,
    );
  }

  /// v59：统一取消所有待执行的自动滚动任务（跳底 / 位置恢复 /
  /// pending restore）。生成开始、用户拖动、会话切换时调用。
  void _cancelAutomaticScrollWork() {
    _scrollRestoreToken++;
    _viewportRestoreToken++;
    _clearPendingRestore();
    _restoringScroll = false;
  }

  /// "到底"按钮统一走可靠跳底（bottom anchor 对齐真实底部）。
  void _onScrollToBottomPressed() {
    final id = _viewModel.activeSession?.id;
    if (id == null || _viewModel.isSending) {
      return;
    }
    unawaited(_scrollToBottomReliably(id, animated: true));
  }

  /// v59：解冻后恢复原像素位置——在解冻通知发生、新列表尚未布局前
  /// 取得当前 pixels，下一帧布局完成后 jumpTo 回去。用户在流式期间
  /// 手动滚动到哪里，完成后就停在哪里（不再依赖"尾部追加不会动"）。
  void _preserveOffsetAfterUnfreeze() {
    if (!_scrollController.hasClients) {
      return;
    }
    final sessionId = _viewModel.activeSession?.id;
    final pixels = _scrollController.position.pixels;
    final token = ++_viewportRestoreToken;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _viewportRestoreToken ||
          sessionId != _viewModel.activeSession?.id ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      _restoringScroll = true;
      position.jumpTo(
        pixels.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      _restoringScroll = false;
    });
  }

  bool _previouslySending = false;
  bool _previouslyFrozen = false;

  void _onViewModelChanged() {
    // v59：统一滚动任务生命周期——
    // ① 生成开始（isSending 上升沿）：取消所有待执行滚动任务，防止
    //    遗留的跳底/位置恢复在生成期间落下 jumpTo（"有时跳底"根因）；
    // ② 解冻（frozen 下降沿）：显式恢复解冻前像素位置。
    final sending = _viewModel.isSending;
    final frozen = _viewModel.isMessagesFrozen;

    if (!_previouslySending && sending) {
      _cancelAutomaticScrollWork();
    }

    if (_previouslyFrozen && !frozen) {
      _preserveOffsetAfterUnfreeze();
    }

    _previouslySending = sending;
    _previouslyFrozen = frozen;
  }

  void _dismissInputKeyboard() {
    _inputFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// 特别版：群聊发言人条。
  /// 轮流制：显示当前发言人，点击可手动指定本次发言角色；
  /// 全员回复模式：显示模式标签（成员自动依次回复）。
  Widget _buildGroupSpeakerBar() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_viewModel.isEveryoneGroupChat) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '全员回复模式：发消息后所有成员依次回复',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // 轮流制：发言人选择
    final manualId = _viewModel.manualSpeakerId;
    final speakerName = _viewModel.groupCharacters
        .where((c) => c.id == manualId)
        .map((c) => c.name)
        .firstOrNull ??
        _viewModel.activeCharacter?.name ??
        '未知';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<String>(
          tooltip: '选择本次发言角色',
          onSelected: _viewModel.selectGroupSpeaker,
          itemBuilder: (context) => [
            for (final character in _viewModel.groupCharacters)
              PopupMenuItem<String>(
                value: character.id,
                child: Row(
                  children: [
                    if (character.id ==
                        (manualId ?? _viewModel.activeCharacter?.id))
                      Icon(Icons.check, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(character.name),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.record_voice_over, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '发言人：$speakerName',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- 侧边栏 / 会话切换 ---

  void _onChatListPressed() {
    _dismissInputKeyboard();
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _selectSessionFromSidebar(ChatSessionSummary summary) async {
    _dismissInputKeyboard();
    if (_viewModel.isSending || _viewModel.isImpersonating) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复生成中，稍后再切换聊天')));
      return;
    }
    final started = _viewModel.selectSession(summary.id);
    if (started) {
      _textController.clear();
    }
  }

  // --- API 状态 / 配置 ---

  Future<void> _openApiConfigPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OpenAICompatibleConfigPage()),
    );
    await _viewModel.onApiConfigsChanged();
  }

  Future<void> _openApiRequestLogPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ApiRequestLogPage()));
  }

  /// 特别版：打开上下文用量详情（最近一次请求的分解统计）。
  Future<void> _openContextUsagePage() async {
    // 最大上下文：发送后由 VM 按"预设高级参数 > 模型上下文窗口 > 默认"解析；
    // 未发送过时回退当前模型的 contextWindow
    var contextWindow = _viewModel.lastContextMax;
    String? modelName;
    final selectedId = selectedApiModelIdNotifier.value;
    for (final config in apiConfigsNotifier.value) {
      for (final model in config.models) {
        if (model.id == selectedId) {
          if (contextWindow == 128000 && _viewModel.lastContextTotal == 0) {
            contextWindow = model.contextWindow;
          }
          modelName = model.modelId;
          break;
        }
      }
      if (modelName != null) break;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContextUsagePage(
          assembly: _viewModel.lastPromptAssembly,
          contextWindow: contextWindow,
          modelName: modelName,
          // 特别版：接口真实用量（发送后可用，null 则隐藏真实用量区）
          realUsage: _viewModel.lastRealUsage,
        ),
      ),
    );
  }

  Future<void> _openMemoryManager() async {
    final session = _viewModel.activeSession;
    if (session == null) return;
    final activeLeafId = _viewModel.messages.isNotEmpty
        ? _viewModel.messages.last.id
        : null;
    final jumpedTo = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MemoryTreePage(
          sessionId: session.id,
          activeLeafMessageId: activeLeafId,
        ),
      ),
    );
    if (!mounted) return;
    if (jumpedTo != null || _viewModel.activeSession?.id == session.id) {
      // v68：记忆管理器可能新增消息/记忆——按 messages 变化重载会话
      await _viewModel.onChatDatabaseChanged(
        const ChatDatabaseChange(kind: ChatDatabaseChangeKind.messages),
      );
    }
  }

  Future<void> _showApiSelectorSheet() async {
    await showApiSelectorSheet(
      context: context,
      statusProvider: () => ApiStatusInfo(
        isChecking: _viewModel.isCheckingApiStatus,
        modelId: _viewModel.apiStatusModelId,
        result: _viewModel.apiStatusResult,
      ),
      useStreamingProvider: () => _viewModel.useStreaming,
      isSendingProvider: () => _viewModel.isSending,
      onStreamingChanged: _viewModel.setUseStreaming,
      onSelectModel: _viewModel.selectApiModel,
      onRefreshStatus: _viewModel.onApiConfigsChanged,
      onOpenConfigPage: _openApiConfigPage,
      onOpenRequestLogPage: _openApiRequestLogPage,
      onOpenContextUsagePage: _openContextUsagePage,
      onOpenMemoryManager: _openMemoryManager,
    );
  }

  // --- 标题 / 重置 ---

  Future<void> _renameChatTitle() async {
    final session = _viewModel.activeSession;
    if (session == null) {
      return;
    }

    final result = await showDialog<ChatTitleDialogResult>(
      context: context,
      builder: (_) => ChatTitleDialog(initialTitle: session.title),
    );

    if (!mounted || result == null) {
      return;
    }

    final normalizedTitle = result.title.trim();
    if (result.action == ChatTitleDialogAction.reset) {
      final nextTitle = normalizedTitle.isEmpty
          ? session.title
          : normalizedTitle;
      await _confirmAndResetChat(nextTitle);
      return;
    }

    await _viewModel.renameChatTitle(normalizedTitle);
  }

  Future<void> _confirmAndResetChat(String nextTitle) async {
    final session = _viewModel.activeSession;
    final character = _viewModel.activeCharacter;
    if (session == null || character == null || _viewModel.isSending) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重置聊天'),
          content: const Text('将清空当前聊天记录，并按当前选择重新初始化聊天。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('重置'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    _textController.clear();
    setState(() {
      _inputText = '';
    });

    try {
      await _viewModel.resetChat(nextTitle);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已按当前选择重置聊天')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  // --- 选择菜单（用户设定 / 世界书 / 预设） ---

  Future<void> _onWorldBookEditPressed(String worldBookId) async {
    final worldBook = await WorldBookService.instance.loadById(worldBookId);
    if (worldBook == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorldBookEditPage(worldBook: worldBook),
      ),
    );

    await _viewModel.loadWorldBooks();
  }

  Future<void> _onUserSettingEditPressed(String settingId) async {
    final settings = userSettingsNotifier.value;
    final setting = settings.firstWhere((s) => s.id == settingId);
    final result = await showEditUserSettingDialog(context, setting);
    if (result == null || !mounted) return;

    if (result.deleted) {
      await _viewModel.handleUserSettingDeleted(settingId);
    } else {
      await _viewModel.handleUserSettingUpdated(result.setting);
    }
  }

  Future<void> _onPresetEditPressed(String presetId) async {
    final preset = await PresetService.instance.loadById(presetId);
    if (preset == null || !mounted) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PresetEditPage(preset: preset)),
    );

    if (saved == true && mounted) {
      await _viewModel.onPresetsChanged();
    }
  }

  void _onUserSettingsPressed(BuildContext context) {
    showUserSettingMenu(
      context: context,
      settings: userSettingsNotifier.value,
      selectedId: _viewModel.selectedUserSettingId,
      inputTapRegionGroupId: _inputTapRegionGroupId,
      onSelected: (value) async {
        await _viewModel.setSelectedUserSettingId(value);
      },
      onEdit: _onUserSettingEditPressed,
    );
  }

  void _onWorldBookPressed(BuildContext context) {
    showWorldBookMenu(
      context: context,
      worldBooks: _viewModel.worldBooks,
      selectedIds: _viewModel.selectedWorldBookIds,
      inputTapRegionGroupId: _inputTapRegionGroupId,
      onToggle: (id) => _viewModel.toggleWorldBook(id),
      onEdit: _onWorldBookEditPressed,
    );
  }

  void _onPresetPressed(BuildContext context) {
    showPresetMenu(
      context: context,
      presets: _viewModel.presets,
      selectedId: _viewModel.selectedPresetId,
      inputTapRegionGroupId: _inputTapRegionGroupId,
      onSelected: (value) async {
        await _viewModel.setSelectedPresetId(value);
      },
      onEdit: _onPresetEditPressed,
    );
  }

  // --- 发送 / 终止 ---

  Future<void> _onSendPressed() async {
    final text = _inputText.trim();
    if (text.isEmpty ||
        _viewModel.isSwitchingSession ||
        _viewModel.isSending ||
        _viewModel.activeSession == null) {
      return;
    }

    _textController.clear();
    try {
      // 特别版：展开输入框中的快捷指令占位标记 → 发送给模型的是提示词，
      // 界面文本（text）保留占位形式，消息渲染时显示【快捷指令：名】。
      final expanded = expandQuickCommandMarks(text, _quickCommands);
      await _viewModel.sendMessage(text, modelText: expanded);
    } catch (error) {
      if (!mounted) return;
      // v78：发送失败把草稿写回输入框（此前先清空再发，失败时用户
      // 输入的长消息无法找回）
      _textController.text = text;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _onStopGeneratingPressed() {
    _viewModel.stopStreaming();
  }

  /// v79：快捷指令发送统一带错误处理——此前 unawaited 无 catch，
  /// 失败静默吞掉且成为未处理异步错误（普通发送有 SnackBar、快捷
  /// 指令没有）；询问型失败时把补充内容写回输入框（弹窗已关内容
  /// 原本会丢）。
  Future<void> _sendQuickCommand(
    QuickCommand command, {
    String? extraText,
  }) async {
    try {
      await _viewModel.sendQuickCommand(command, extraText: extraText);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (extraText != null && extraText.isNotEmpty) {
        _textController.text = extraText;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: extraText.length),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  /// 特别版：消息动作按钮（模型 choices）点击：把动作作为消息发送给模型。
  void _onChoicePressed(String label, String action) {
    final text = action.isNotEmpty ? action : label;
    if (text.isEmpty ||
        _viewModel.isSending ||
        _viewModel.activeSession == null) {
      return;
    }
    _viewModel.sendMessage(text).catchError((Object error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    });
  }

  // --- 消息操作 ---

  void _onCopyMessage(ChatMessage msg) {
    // 特别版：复制时还原快捷指令占位（不暴露私有区字符）
    Clipboard.setData(ClipboardData(text: restoreQuickCommandMarks(msg.text)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _onEditMessage(int index) async {
    final character = _viewModel.activeCharacter;
    final message = index >= 0 && index < _viewModel.messages.length
        ? _viewModel.messages[index]
        : null;
    if (message == null || message.id == null || _viewModel.isSending) {
      return;
    }
    final editingMessage = message;

    final result = await showDialog<MessageEditDialogResult>(
      context: context,
      builder: (context) => MessageEditDialog(
        // 特别版：快捷指令消息的完整发送内容（提示词 + 【用户补充】）
        // 存于 modelText——编辑时预填它，用户可修改当时填写的内容；
        // 普通消息回退到显示文本。
        initialText:
            editingMessage.modelText?.isNotEmpty == true && editingMessage.isMe
            ? editingMessage.modelText!
            : editingMessage.text,
        title: editingMessage.isMe ? '编辑用户消息' : '编辑角色消息',
        canSaveAndSend: editingMessage.isMe && character != null,
        // 特别版：编辑时也可插入快捷指令（占位标记，发送时展开）
        quickCommands: editingMessage.isMe ? _quickCommands : const [],
      ),
    );

    if (result == null || !mounted) {
      return;
    }
    final normalizedText = result.text.trim();
    if (normalizedText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('消息不能为空')));
      return;
    }

    try {
      // 特别版：编辑框内容可能含快捷指令占位标记（编辑时插入），
      // 发送给模型的 modelText 必须先展开为提示词；
      // 界面则把展开文本中匹配的提示词（原消息标记 + 编辑新插入标记）
      // 替换回占位显示——无论用户是否改了补充内容，界面都不暴露提示词原文。
      final originalModelText = editingMessage.isMe
          ? editingMessage.modelText
          : null;
      final expanded = expandQuickCommandMarks(normalizedText, _quickCommands);
      String displayText = normalizedText;
      String? modelTextForSend;
      final hasOriginalPrompt = originalModelText?.isNotEmpty == true;
      final hasAnyMark =
          hasQuickCommandMark(normalizedText) ||
          hasQuickCommandMark(editingMessage.text);
      if (hasOriginalPrompt || hasAnyMark) {
        modelTextForSend = expanded;
        if (hasOriginalPrompt) {
          // 合并原消息标记 + 编辑新插入标记（按序），前缀优先还原；
          // 询问型消息的 text 是纯指令名（无占位标记）——无条件把指令名
          // 放最前（restorePromptsToMarks 对 commands 中不存在的 name 跳过，
          // 普通消息 hasOriginalPrompt=false 不会进入本分支）
          final oldSegments = splitQuickCommandMarks(editingMessage.text);
          final newSegments = splitQuickCommandMarks(normalizedText);
          final markNames = <String>[];
          if (editingMessage.text.trim().isNotEmpty) {
            markNames.add(editingMessage.text.trim());
          }
          for (final (isMark, name) in [...oldSegments, ...newSegments]) {
            if (isMark && name.isNotEmpty) {
              markNames.add(name);
            }
          }
          displayText = restorePromptsToMarks(
            expanded,
            _quickCommands,
            markNames,
          );
        } else {
          // 仅有新插入标记（原消息无提示词）：界面保留占位形式
          displayText = normalizedText;
        }
      }
      await _viewModel.editMessage(
        index,
        displayText,
        result.action,
        modelText: modelTextForSend,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _onEditDraftOpeningMessage() async {
    if (!_viewModel.isDraftSession ||
        _viewModel.isSending ||
        _viewModel.draftOpeningAssistantMessages.isEmpty) {
      return;
    }

    final result = await showDialog<MessageEditDialogResult>(
      context: context,
      builder: (context) => MessageEditDialog(
        initialText:
            _viewModel.draftOpeningAssistantMessages[_viewModel
                .draftOpeningMessageIndex
                .clamp(0, _viewModel.draftOpeningAssistantMessages.length - 1)],
        title: '编辑角色消息',
        canSaveAndSend: false,
      ),
    );

    if (result == null || !mounted) {
      return;
    }
    final normalizedText = result.text.trim();
    if (normalizedText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('消息不能为空')));
      return;
    }

    await _viewModel.editDraftOpeningMessage(normalizedText);
  }

  Future<void> _onDeleteMessage(int index) async {
    final message = index >= 0 && index < _viewModel.messages.length
        ? _viewModel.messages[index]
        : null;
    if (message?.id == null || _viewModel.isSending) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除消息'),
          content: Text(message!.isMe ? '确定删除这条用户消息吗？' : '确定删除这条角色消息吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    await _viewModel.deleteMessage(index);
  }

  Future<void> _onRegenerateMessage(int assistantMessageIndex) async {
    try {
      await _viewModel.regenerateMessage(assistantMessageIndex);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _onContinueMessage(int assistantMessageIndex) async {
    try {
      await _viewModel.continueAssistantMessage(assistantMessageIndex);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _onImpersonate() async {
    // v80：点帮答时输入框已有草稿 → 不自动填充（此前生成结果整体
    // 覆盖草稿）；生成期间用户手动输入 → 停止填充（不再覆盖）。
    final hadDraft = _textController.text.trim().isNotEmpty;
    var lastWritten = '';
    try {
      final reply = await _viewModel.generateUserReply(
        onProgress: (text) {
          if (!mounted || hadDraft) {
            return;
          }
          // 用户中途自己输入/修改过就不再自动填充
          if (_textController.text != lastWritten) {
            return;
          }
          lastWritten = text;
          _textController.text = text;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
        },
      );
      if (reply == null || reply.isEmpty || !mounted) {
        return;
      }
      if (hadDraft) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('输入框已有内容，帮答结果未填入（清空后重新点击即可）'),
          ),
        );
        return;
      }
      // 用户生成期间输入过内容：不覆盖
      if (_textController.text != lastWritten) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('生成期间你已输入内容，帮答结果未覆盖'),
          ),
        );
        return;
      }
      _textController.text = reply;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: reply.length),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _onRegenerateFromUserMessage(int userMessageIndex) async {
    try {
      await _viewModel.regenerateFromUserMessage(
        userMessageIndex: userMessageIndex,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _onSwitchMessageVariant(ChatMessage message, int delta) async {
    await _viewModel.switchMessageVariant(message, delta);
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drawerEdgeDragWidth = (MediaQuery.sizeOf(context).width * 0.45).clamp(
      128.0,
      320.0,
    );
    final topContentPadding = 0.0;
    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: drawerEdgeDragWidth,
      onDrawerChanged: (isOpened) {
        if (isOpened) {
          _dismissInputKeyboard();
        }
      },
      drawer: Drawer(
        child: SafeArea(
          child: ChatSidebarPage(
            activeSessionId: _viewModel.activeSession?.id,
            onChatSelected: _selectSessionFromSidebar,
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle,
        leading: IconButton(
          icon: const Icon(Icons.format_list_bulleted),
          onPressed: _onChatListPressed,
          tooltip: '聊天列表',
        ),
        title: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final session = _viewModel.activeSession;
            return InkWell(
              onTap: session == null ? null : _renameChatTitle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  session?.title ?? '聊天',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
        centerTitle: true,
        actions: [
          ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) {
              return ApiStatusActionButton(
                status: ApiStatusInfo(
                  isChecking: _viewModel.isCheckingApiStatus,
                  modelId: _viewModel.apiStatusModelId,
                  result: _viewModel.apiStatusResult,
                ),
                onPressed: _showApiSelectorSheet,
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<AppSettings>(
        valueListenable: appSettingsNotifier,
        builder: (context, settings, _) {
          return ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) {
              final session = _viewModel.activeSession;
              final character = _viewModel.activeCharacter;
              final backgroundPath = character?.imagePath ?? '';
              final hasBackground = backgroundPath.isNotEmpty;
              if (_viewModel.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (session == null) {
                return const Center(child: Text('暂无聊天记录'));
              }
              final isSendEnabled =
                  !_viewModel.isSwitchingSession &&
                  !_viewModel.isSending &&
                  !_viewModel.isImpersonating &&
                  _inputText.trim().isNotEmpty;
              return Stack(
                children: [
                  if (hasBackground)
                    Positioned.fill(
                      child: character?.isAssetImage == true
                          ? Image.asset(
                              backgroundPath,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox.shrink();
                              },
                            )
                          : Image.file(
                              File(backgroundPath),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox.shrink();
                              },
                            ),
                    ),
                  if (hasBackground)
                    Positioned.fill(
                      child: Container(
                        color: Theme.of(context).colorScheme.surface.withValues(
                          alpha: settings.backgroundOpacity,
                        ),
                      ),
                    ),
                  // 特别版：SafeArea 顶部留白——extendBodyBehindAppBar
                  // 时 body 延伸到系统状态栏后（背景图仍延伸，内容不重叠）
                  SafeArea(
                    bottom: false,
                    child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: topContentPadding),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              // 仅真实用户滚动（拖动开始/惯性滚动）保存浏览位置；
                              // 自动跳底/ensureVisible/布局校正不保存。
                              final isUserDrag = notification
                                      is ScrollStartNotification &&
                                  notification.dragDetails != null;
                              final isUserInertia =
                                  notification is UserScrollNotification;
                              if (isUserDrag) {
                                // 用户开始拖动：统一取消所有待执行自动
                                // 滚动任务（v59——之前只失效跳底令牌，
                                // 无令牌的 _scheduleScrollRestore 仍会
                                // 在布局稳定后突然 jumpTo）
                                _cancelAutomaticScrollWork();
                              }
                              if (isUserDrag || isUserInertia) {
                                _onUserScroll();
                              }
                              // 视口锁定由 _onViewModelChanged 统一处理
                              // （输出结束瞬间快照恢复）；此处不再干预
                              // 用户滚动。
                              return false;
                            },
                            child: ChatMessageList(
                            visibleMessages: _viewModel.visibleMessages,
                            scrollController: _scrollController,
                            // 特别版：底部真实锚点（跳底/恢复统一对齐）
                            bottomAnchorKey: _bottomAnchorKey,
                            onScrollToBottom: _onScrollToBottomPressed,
                            inputTapRegionGroupId: _inputTapRegionGroupId,
                            isSending: _viewModel.isSending,
                            // 特别版：流式悬浮面板数据（列表外显示）
                            streamingText: _viewModel.streamingDisplayText,
                            streamingThinking: _viewModel.streamingThinkingChain,
                            streamingIsThinking:
                                _viewModel.isStreamingThinking,
                            streamingRetryNotice:
                                _viewModel.thinkingChainRetryNotice,
                            streamingSpeakerName: _viewModel.isGroupChat
                                ? _viewModel.streamingSpeakerName
                                : null,
                            // 特别版：流式期间列表冻结（禁用列表操作）
                            messagesFrozen: _viewModel.isMessagesFrozen,
                            isImpersonating: _viewModel.isImpersonating,
                            regeneratingUserMessageId:
                                _viewModel.regeneratingUserMessageId,
                            isDraftSession: _viewModel.isDraftSession,
                            activeCharacter: _viewModel.activeCharacter,
                            currentUserSetting: _viewModel.currentUserSetting(),
                            sessionId: session.id,
                            groupCharacterNames: {
                              for (final character
                                  in _viewModel.groupCharacters)
                                character.id: character.name,
                            },
                            groupCharactersById: {
                              for (final character
                                  in _viewModel.groupCharacters)
                                character.id: character,
                            },
                            onCopyMessage: _onCopyMessage,
                            onEditMessage: _onEditMessage,
                            onEditDraftOpeningMessage:
                                _onEditDraftOpeningMessage,
                            onDeleteMessage: _onDeleteMessage,
                            onRegenerateFromUserMessage:
                                _onRegenerateFromUserMessage,
                            onRegenerateMessage: _onRegenerateMessage,
                            onContinueMessage: _onContinueMessage,
                            onImpersonate: _onImpersonate,
                            onSwitchMessageVariant: _onSwitchMessageVariant,
                            onChoicePressed: _onChoicePressed,
                            sessionVariables:
                                _viewModel.sessionVariablesCache,
                          ),
                          ),
                        ),
                      ),
                      // 特别版：群聊发言人条（轮流制可选发言人 / 全员回复模式标签）
                      if (_viewModel.isGroupChat) _buildGroupSpeakerBar(),
                      ChatInputArea(
                        textController: _textController,
                        focusNode: _inputFocusNode,
                        inputTapRegionGroupId: _inputTapRegionGroupId,
                        sessionKey: ValueKey(_viewModel.activeSession?.id),
                        isSendEnabled: isSendEnabled,
                        isSending: _viewModel.isSending,
                        hasBackground: hasBackground,
                        settings: settings,
                        worldBooks: _viewModel.worldBooks,
                        selectedWorldBookIds: _viewModel.selectedWorldBookIds,
                        currentUserSetting: _viewModel.currentUserSetting(),
                        onUserSettingsPressed: _onUserSettingsPressed,
                        onWorldBookPressed: _onWorldBookPressed,
                        onPresetPressed: _onPresetPressed,
                        onSendPressed: _onSendPressed,
                        onStopGeneratingPressed: _onStopGeneratingPressed,
                        quickCommands: _quickCommands,
                        onQuickCommand: (command) {
                          _sendQuickCommand(command);
                        },
                        onQuickCommandWithExtra: (command, extra) {
                          _sendQuickCommand(command, extraText: extra);
                        },
                        contextUsedTokens: _viewModel.lastContextTotal,
                        // v61：分母用安全输入上限（窗口-输出预留-余量）
                        contextMaxTokens: _viewModel.lastContextSafeLimit,
                        onOpenContextUsage: _openContextUsagePage,
                      ),
                    ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 特别版：会话浏览位置快照。
///
/// 仅保存裸 pixels 会在图片/Markdown 高度重建变化后恢复错位；
/// 保存 wasAtBottom，上次在底部时下次打开重新可靠跳底。
class ChatScrollState {
  const ChatScrollState({
    required this.pixels,
    required this.wasAtBottom,
  });

  final double pixels;
  final bool wasAtBottom;
}
