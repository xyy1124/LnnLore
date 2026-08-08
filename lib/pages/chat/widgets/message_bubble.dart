import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/app_settings.dart';
import '../../../models/chat_message.dart';
import '../../../models/tracker_config.dart';
import '../../../models/user_setting.dart';
import '../../../services/chat_character_resolver.dart';
import '../../../services/chat_database_service.dart';
import '../../../services/chat_display_sanitizer.dart';
import '../../../services/chat_service.dart';
import '../../../services/chat_variable_service.dart';
import '../../../services/regex_script_service.dart';
import '../../../services/tracker_runtime.dart';
import '../../../widgets/chat_markdown_body.dart';
import 'special_status_panel.dart';
import 'thinking_chain_widget.dart';
import '../utils/pseudo_thinking_chain.dart';

/// v64：消息长按菜单动作（showMenu 路由方案）。
enum _MessageMenuAction {
  copy,
  edit,
  delete,
}

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.userSetting,
    required this.character,
    /// 特别版：群聊消息的发言人角色（按消息 characterId 解析），
    /// 用于头像/名字渲染（不随全局 activeCharacter 变化）。
    this.resolvedSpeaker,
    required this.inputTapRegionGroupId,
    required this.isLastUserMessageWithoutReply,
    required this.isLastCharacterMessage,
    required this.showActions,
    /// v51：操作区"可用"标记——生成/冻结期间 false：操作区保留布局
    /// （AnimatedOpacity 淡出）但禁用点击，避免按钮消失导致消息高度
    /// 变化、流式输出期间视口跳动。
    this.actionsEnabled = true,
    required this.canEdit,
    required this.canDelete,
    required this.isBusyRegenerating,
    required this.isBusyImpersonating,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    this.onGenerate,
    this.onRegenerate,
    this.onContinue,
    this.onImpersonate,
    this.onSelectPreviousVariant,
    this.onSelectNextVariant,
    /// 特别版：消息动作按钮（模型 choices）点击回调（label, action）
    this.onChoicePressed,
    /// 特别版：会话变量表（{{getvar::key}} 显示解析数据源）
    this.sessionVariables = const {},
  });

  final ChatMessage message;
  final UserSetting? userSetting;
  final ResolvedChatCharacter? character;
  final ResolvedChatCharacter? resolvedSpeaker;
  final Object inputTapRegionGroupId;
  final bool isLastUserMessageWithoutReply;
  final bool isLastCharacterMessage;
  final bool showActions;
  final bool actionsEnabled;
  final bool canEdit;
  final bool canDelete;
  final bool isBusyRegenerating;
  final bool isBusyImpersonating;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onGenerate;
  final VoidCallback? onRegenerate;
  final VoidCallback? onContinue;
  final VoidCallback? onImpersonate;
  final VoidCallback? onSelectPreviousVariant;
  final VoidCallback? onSelectNextVariant;

  /// 特别版：消息动作按钮（模型 choices）点击回调（label, action）
  final void Function(String label, String action)? onChoicePressed;

  /// 特别版：会话变量表（{{getvar::key}} 显示解析数据源）。
  final Map<String, String> sessionVariables;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  /// 特别版：choices 查询 future 缓存（按 messageId，避免每 build 重建查询）
  Future<List<Map<String, dynamic>>>? _choicesFuture;
  String? _choicesFutureMessageId;

  Future<List<Map<String, dynamic>>> _loadChoices() {
    final messageId = widget.message.id;
    if (messageId == null) {
      return Future.value(const []);
    }
    if (_choicesFuture == null || _choicesFutureMessageId != messageId) {
      _choicesFutureMessageId = messageId;
      _choicesFuture =
          ChatDatabaseService.instance.getMessageChoices(messageId);
    }
    return _choicesFuture!;
  }

  /// v62：统一菜单可用判断（显示操作区且可用）。
  bool get _canOpenActionPopup => widget.showActions && widget.actionsEnabled;

  /// v64：防止同一条消息重复发起菜单请求（showMenu 弹出期间忽略后续长按）。
  bool _openingActionMenu = false;

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v64：消息身份/内容变化时关闭菜单——旧 OverlayPortal 方案在
    // 父组件重建时下一帧隐藏菜单（刚弹出就被关闭）；showMenu 是
    // Navigator 路由，不随消息组件重建，这里不再需要 didUpdateWidget
    // 干预菜单生命周期。
  }

  /// v64：长按消息弹出操作菜单——由 Navigator 管理的 showMenu 路由，
  /// 替代旧方案"每条消息一个 OverlayPortalController + 全局 owner +
  /// 下一帧延迟显示"（排队回调不失效导致偶尔不弹/再次长按延迟）。
  Future<void> _showActionMenu(Offset globalPosition) async {
    if (_openingActionMenu || !mounted || !_canOpenActionPopup) {
      return;
    }
    _openingActionMenu = true;
    try {
      final overlayState = Overlay.of(context, rootOverlay: true);
      final renderObject = overlayState.context.findRenderObject();
      if (renderObject is! RenderBox) {
        return;
      }
      final overlayRect = Offset.zero & renderObject.size;
      final anchorRect = globalPosition & const Size(1, 1);

      final result = await showMenu<_MessageMenuAction>(
        context: context,
        useRootNavigator: true,
        position: RelativeRect.fromRect(anchorRect, overlayRect),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
        items: [
          PopupMenuItem<_MessageMenuAction>(
            value: _MessageMenuAction.copy,
            // v64：保留 TapRegion 组——点击菜单项不收起输入框键盘
            child: TextFieldTapRegion(
              groupId: widget.inputTapRegionGroupId,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('复制'),
                ],
              ),
            ),
          ),
          if (widget.canEdit)
            PopupMenuItem<_MessageMenuAction>(
              value: _MessageMenuAction.edit,
              child: TextFieldTapRegion(
                groupId: widget.inputTapRegionGroupId,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('编辑'),
                  ],
                ),
              ),
            ),
          if (widget.canDelete)
            PopupMenuItem<_MessageMenuAction>(
              value: _MessageMenuAction.delete,
              child: TextFieldTapRegion(
                groupId: widget.inputTapRegionGroupId,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '删除',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

      if (!mounted || result == null) {
        return;
      }
      switch (result) {
        case _MessageMenuAction.copy:
          widget.onCopy();
          break;
        case _MessageMenuAction.edit:
          widget.onEdit();
          break;
        case _MessageMenuAction.delete:
          widget.onDelete();
          break;
      }
    } finally {
      _openingActionMenu = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.message.isMe;
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<AppSettings>(
      valueListenable: appSettingsNotifier,
      builder: (context, settings, _) {
        final showAvatar = settings.showAvatar;

        if (isMe) {
          return _buildUserBubble(context, colorScheme, settings, showAvatar);
        } else {
          return _buildCharacterBubble(
            context,
            colorScheme,
            settings,
            showAvatar,
          );
        }
      },
    );
  }

  Widget _buildUserBubble(
    BuildContext context,
    ColorScheme colorScheme,
    AppSettings settings,
    bool showAvatar,
  ) {
    final bubbleColor = colorScheme.primaryContainer;
    final textColor = colorScheme.onPrimaryContainer;

    // 特别版：用户消息按原文显示（用户输入不属系统内容，无需清洗）；
    // 空消息不渲染空气泡。
    final displayText = widget.message.text.trim();
    if (displayText.isEmpty) {
      return const SizedBox.shrink();
    }
    final inlineCodeColor = colorScheme.primary.withValues(alpha: 0.12);
    final codeBlockColor = colorScheme.primary.withValues(alpha: 0.08);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // v64：长按菜单改用 showMenu（Navigator 路由）——不再需要
              // OverlayPortal 附着在消息组件上；菜单外点击由路由自带关闭。
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: _canOpenActionPopup
                    ? (details) => unawaited(
                          _showActionMenu(details.globalPosition),
                        )
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Semantics(
                    container: true,
                    child: ChatMarkdownBody(
                      text: displayText,
                      settings: settings,
                      textColor: textColor,
                      inlineCodeColor: inlineCodeColor,
                      codeBlockColor: codeBlockColor,
                      applyBodyTextColor: false,
                      selectable: false,
                    ),
                  ),
                ),
              ),
              // v51：操作区保留布局——生成/冻结时禁用交互并淡出
              // （不移除布局，避免消息高度变化导致视口跳动）
              IgnorePointer(
                ignoring: !widget.actionsEnabled,
                child: AnimatedOpacity(
                  opacity: widget.actionsEnabled ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: _buildActionButtons(context, colorScheme),
                ),
              ),
            ],
          ),
        ),
        if (showAvatar) ...[
          const SizedBox(width: 8),
          _buildUserAvatar(colorScheme),
        ],
      ],
    );
  }

  /// 特别版：消息动作按钮（模型 choices）——按消息从 DB 加载，
  /// 渲染为可点击的动作条。点击后回调发送对应动作。
  Widget _buildChoicesRow(BuildContext context, ColorScheme colorScheme) {
    final onChoicePressed = widget.onChoicePressed;
    final messageId = widget.message.id;
    if (onChoicePressed == null ||
        messageId == null ||
        widget.message.isMe) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadChoices(),
      builder: (context, snapshot) {
        final choices = snapshot.data ?? const [];
        if (choices.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final choice in choices)
                ActionChip(
                  label: Text(
                    '${choice['label']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  backgroundColor: colorScheme.primaryContainer,
                  side: BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                  ),
                  onPressed: () => onChoicePressed(
                    '${choice['label']}',
                    '${choice['action'] ?? ''}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 特别版：本条消息对应的角色卡（群聊按消息发言人解析，而非全局
  /// activeCharacter——否则轮到角色 B 后，角色 A 的历史消息也会套用
  /// B 的状态模板/正则）。单聊消息 characterId 为空，回退全局角色。
  ResolvedChatCharacter? get _messageCharacter => widget.message.characterId !=
          null
      ? widget.resolvedSpeaker
      : widget.character;

  /// 特别版：对 AI 输出应用角色卡自带正则脚本（显示阶段）。
  /// 仅角色消息生效；总开关关闭或卡无脚本时原样返回。
  /// 两次串联：先应用普通脚本，再应用 markdownOnly 脚本
  /// （markdownOnly 语义=仅 Markdown 渲染通道执行）。
  String _applyRegexScripts(String text) {
    if (!appSettingsNotifier.value.regexScriptsEnabled) {
      return text;
    }
    final scripts = RegexScriptService.scriptsFromCharacterCard(
      _messageCharacter?.cardJson,
    );
    if (scripts.isEmpty) {
      return text;
    }
    var result = RegexScriptService.applyToOutput(text, scripts);
    result = RegexScriptService.applyToOutput(
      result,
      scripts,
      forMarkdown: true,
    );
    return result;
  }

  Widget _buildCharacterBubble(
    BuildContext context,
    ColorScheme colorScheme,
    AppSettings settings,
    bool showAvatar,
  ) {
    final textColor = colorScheme.onSurface;
    final inlineCodeColor = colorScheme.surfaceContainerHigh;
    final codeBlockColor = colorScheme.surfaceContainerLow;
    final (pseudoChain, cleanedText, pseudoChainComplete) =
        extractPseudoThinkingChain(widget.message.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAvatar) ...[
              _buildCharacterAvatar(colorScheme),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.message.hasThinkingChain)
                    _buildThinkingChain(context, colorScheme),
                  if (pseudoChain != null)
                    ThinkingChainWidget(
                      thinkingChain: pseudoChain,
                      colorScheme: colorScheme,
                      initiallyExpanded: !pseudoChainComplete,
                    ),
                  // v64：同用户消息——长按菜单改用 showMenu（Navigator
                  // 路由），菜单外点击由路由自带关闭
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: _canOpenActionPopup
                        ? (details) => unawaited(
                              _showActionMenu(details.globalPosition),
                            )
                        : null,
                    child: Semantics(
                      container: true,
                      child: Builder(builder: (context) {
                        // 显示层轻量清洗（不提取 div/details，避免
                        // 破坏性 extract 把正文剥空）+ 解析 getvar；
                        // 为空（纯协议块）不渲染空气泡
                        final displayText =
                            ChatVariableService.resolveGetVars(
                              ChatDisplaySanitizer
                                  .stripStoredMessageForDisplay(
                                _applyRegexScripts(cleanedText),
                              ),
                              widget.sessionVariables,
                            ).trim();
                        if (displayText.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return ChatMarkdownBody(
                          text: displayText,
                          settings: settings,
                          textColor: textColor,
                          inlineCodeColor: inlineCodeColor,
                          codeBlockColor: codeBlockColor,
                          selectable: false,
                        );
                      }),
                    ),
                  ),
                  // v51：操作区保留布局——生成/冻结时禁用交互并淡出
                  // （不移除布局，避免消息高度变化导致视口跳动）
                  IgnorePointer(
                    ignoring: !widget.actionsEnabled,
                    child: AnimatedOpacity(
                      opacity: widget.actionsEnabled ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: _buildActionButtons(context, colorScheme),
                    ),
                  ),
                  // 特别版：消息动作按钮（模型 choices）
                  _buildChoicesRow(context, colorScheme),
                  // 特别版：本条消息的状态面板（跟随消息渲染，
                  // 从会话变量表按消息 id 关联）
                  ?_buildMessageStatusPanel(context),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 本条消息的状态面板：两路兜底——
  /// ①消息级结构化状态快照（v4 `__msg_tracker_state_v4__:<id>` 含
  /// state + narrative；v3 `__msg_tracker_state_v3__:<id>` 仅 state，
  /// 该消息处理完成时的 tracker 状态 JSON）→ 用**当前角色卡模板**
  /// 动态渲染（模板来自 post_history_instructions 的 <!--panel--> HTML，
  /// 样式始终与卡一致；数值=消息时刻状态，不随后续轮次漂移）
  /// ②运行时生成面板（卡的 tracker 声明 + 当前变量表 + **initialState
  /// 兜底**，新会话/开场/旧会话无快照消息也能显示）
  ///
  /// 注意：不再读取任何预渲染 HTML 快照——v3/v4 只存状态值不存 HTML，
  /// 旧版 v2（`__msg_status_html_v2__:<id>`）/v1（`__msg_status_html__:<id>`）
  /// /全局（`__special_status_html__`）快照一律忽略（v2 含错误纯文本模板
  /// 生成的统一面板，会掩盖新实现）。
  Widget? _buildMessageStatusPanel(BuildContext context) {
    if (widget.message.isMe) {
      return null;
    }
    // 注意：draft/未落库消息 id 可能为 null——不能因此拦截（否则
    // 新会话开场消息下无状态栏），id 缺失时跳过消息级快照即可。
    String? html;
    if (widget.message.id != null) {
      final messageId = widget.message.id!;
      // v63：优先 v4 快照（state + narrative），回退 v3（仅 state）
      final rawV4 = widget.sessionVariables[
          ChatService.messageStatusSnapshotV4Key(messageId)];
      if (rawV4 != null && rawV4.trim().isNotEmpty) {
        final parsedV4 = _decodeStatusSnapshotV4(rawV4);
        if (parsedV4 != null) {
          html = TrackerRuntime.renderStatusPanelHtml(
            cardJson: _messageCharacter?.cardJson,
            variables: parsedV4.$1,
            narrative: parsedV4.$2,
          );
        }
      }
      if (html == null || html.trim().isEmpty) {
        final rawState = widget.sessionVariables[
            ChatService.messageStatusHtmlKey(messageId)];
        final decoded = rawState == null ? null : _decodeStatusState(rawState);
        if (decoded != null && decoded.isNotEmpty) {
          // v3 结构化状态：用消息时刻的状态值 + 当前角色卡模板动态渲染
          html = TrackerRuntime.renderStatusPanelHtml(
            cardJson: _messageCharacter?.cardJson,
            variables: decoded,
          );
        }
      }
    }
    if (html == null || html.trim().isEmpty) {
      html = _generateStatusPanelHtml();
    }
    if (html == null || html.trim().isEmpty) {
      return null;
    }
    // 统一清洗：模型可能按卡模板"原样输出"（输出指令要求），把
    // {{match}} 与"状态栏未更新"前缀也带进面板——显示层必须剥掉，
    // 否则所有卡都顶着"状态栏未更新"+{{match}} 原文，渲染很奇怪。
    // v49：summary 标题不再丢弃——提取为折叠标题（SpecialStatusPanel
    // 原生渲染标题栏，点击折叠/展开）；details 标签剥掉让面板内容
    // 直接展开显示（折叠由 Flutter 控制，HtmlWidget 对 details 不可靠）。
    String? panelTitle;
    final summaryMatch = RegExp(
      r'<summary\b[^>]*>([\s\S]*?)</summary>',
      caseSensitive: false,
    ).firstMatch(html);
    if (summaryMatch != null) {
      panelTitle = summaryMatch.group(1)?.trim();
    }
    html = html
        .replaceAll('{{match}}', '')
        .replaceAll('状态栏未更新，当前：', '')
        .replaceAll('状态栏未更新，当前:', '')
        .replaceAll('状态栏未更新', '')
        .replaceAll(
          RegExp(
            r'<summary\b[^>]*>[\s\S]*?</summary>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'</?details\b[^>]*>', caseSensitive: false),
          '',
        )
        .trim();
    if (html.isEmpty) {
      return null;
    }
    // v50：面板默认收起——标题栏兜底"状态面板"（无 summary 的面板
    // 也必须有可点击标题栏，否则无法展开），点击展开/收起。
    // v54：初始展开状态跟随卡声明 tracker.defaultExpanded（默认收起）。
    // v56：用户手动展开/收起偏好持久化在会话变量表
    // （`__tracker_expanded__:<角色id>`）——优先级：手动偏好 > 卡
    // defaultExpanded > 默认收起；并给面板稳定 key，避免列表重建时
    // 一条消息的折叠状态被复用到另一条。
    final effectiveTitle =
        panelTitle != null && panelTitle.trim().isNotEmpty
            ? panelTitle.trim()
            : '状态面板';
    final trackerConfig = TrackerConfig.fromCardJson(
      _messageCharacter?.cardJson ?? widget.character?.cardJson,
    );
    final trackerCharacterId = _messageCharacter?.id ?? widget.character?.id;
    final expandedPrefKey =
        '__tracker_expanded__:${trackerCharacterId ?? ''}';
    // v58：折叠偏好三态判断——'1' 展开 / '0' 收起 / 未保存回退卡声明。
    // 之前 `pref == '1' ? true : defaultExpanded` 把 '0' 与未保存等同，
    // defaultExpanded=true 时用户手动收起后重建又会被展开。
    final initialExpanded = switch (
      widget.sessionVariables[expandedPrefKey]
    ) {
      '1' => true,
      '0' => false,
      _ => trackerConfig.defaultExpanded,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SpecialStatusPanel(
        key: ValueKey<String>(
          'tracker_${widget.message.id}_${trackerCharacterId ?? ''}',
        ),
        html: html,
        title: effectiveTitle,
        expanded: initialExpanded,
        onExpandedChanged: (expanded) {
          final sessionId = widget.message.sessionId;
          if (sessionId == null || trackerCharacterId == null) {
            return;
          }
          // 异步持久化用户偏好（不阻塞 UI）
          unawaited(
            ChatDatabaseService.instance.upsertSessionVariables(
              sessionId,
              {expandedPrefKey: expanded ? '1' : '0'},
            ),
          );
        },
      ),
    );
  }

  /// 解析 v3 结构化状态快照 JSON（`{"yw_brand":"30",...}`）。
  /// 解析失败返回 null（走运行时生成兜底）。
  static Map<String, String>? _decodeStatusState(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map((key, value) => MapEntry(
            key.toString(),
            value.toString(),
          ));
    } catch (_) {
      return null;
    }
  }

  /// v63：解析 v4 快照 JSON（`{"state":{...},"narrative":{...}}`）。
  /// 返回 (state 变量表, narrative 解读表)；解析失败返回 null。
  static (Map<String, String>, Map<String, String>)? _decodeStatusSnapshotV4(
    String raw,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final rawState = decoded['state'];
      final rawNarrative = decoded['narrative'];
      final state = <String, String>{};
      if (rawState is Map) {
        rawState.forEach((k, v) {
          if (k is String && v != null) {
            state[k] = '$v';
          }
        });
      }
      final narrative = <String, String>{};
      if (rawNarrative is Map) {
        rawNarrative.forEach((k, v) {
          if (k is String && v is String && v.trim().isNotEmpty) {
            narrative[k] = v.trim();
          }
        });
      }
      if (state.isEmpty) {
        return null;
      }
      return (state, narrative);
    } catch (_) {
      return null;
    }
  }

  /// 运行时生成状态面板：无消息级快照时，按卡内 StatusFallback 模板
  /// 渲染（`{{getvar::key}}` 用当前变量表值/initialState 填充）——与
  /// 快照生成共用 [TrackerRuntime.renderStatusPanelHtml]（同一套逻辑）；
  /// 卡无模板时回退内置深色卡片。
  String? _generateStatusPanelHtml() => TrackerRuntime.renderStatusPanelHtml(
        cardJson: _messageCharacter?.cardJson,
        variables: widget.sessionVariables,
      );

  Widget _buildThinkingChain(BuildContext context, ColorScheme colorScheme) {
    return ThinkingChainWidget(
      thinkingChain: widget.message.thinkingChain!,
      colorScheme: colorScheme,
    );
  }

  Widget _buildUserAvatar(ColorScheme colorScheme) {
    final currentUser = widget.userSetting;
    if (currentUser != null) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: currentUser.color,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Text(
          currentUser.avatarText.isEmpty ? '我' : currentUser.avatarText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person, size: 20, color: colorScheme.onPrimary),
    );
  }

  Widget _buildCharacterAvatar(ColorScheme colorScheme) {
    // 特别版：群聊头像按消息发言人解析（而非全局 activeCharacter），
    // 避免'轮到谁，所有历史消息头像都变谁'；群聊成员已删除导致
    // 查不到时用中性机器人图标（不回退全局角色）
    final ResolvedChatCharacter? avatarCharacter = widget.message.characterId !=
            null
        ? widget.resolvedSpeaker
        : widget.character;
    final imagePath =
        avatarCharacter?.thumbnailPath ?? avatarCharacter?.imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final imageProvider = imagePath.startsWith('assets/')
          ? AssetImage(imagePath) as ImageProvider
          : FileImage(File(imagePath));
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image(
            image: imageProvider,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.smart_toy_outlined,
                size: 20,
                color: colorScheme.onSecondaryContainer,
              );
            },
          ),
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.smart_toy_outlined,
        size: 20,
        color: colorScheme.onSecondaryContainer,
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ColorScheme colorScheme) {
    if (!widget.showActions) {
      if (!widget.message.hasMultiple) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [const Spacer(), _buildIndexSelector(colorScheme)],
        ),
      );
    }

    final actionWidgets = <Widget>[
      if (widget.isLastUserMessageWithoutReply && widget.onGenerate != null)
        _buildActionButton(
          icon: widget.isBusyRegenerating
              ? Icons.hourglass_top
              : Icons.auto_awesome,
          tooltip: widget.isBusyRegenerating ? '生成中' : '生成回复',
          onPressed: widget.onGenerate!,
          colorScheme: colorScheme,
        ),
      if (widget.isLastCharacterMessage &&
          widget.onRegenerate != null &&
          !widget.isBusyImpersonating)
        _buildActionButton(
          icon: Icons.refresh,
          tooltip: '重新生成',
          onPressed: widget.onRegenerate!,
          colorScheme: colorScheme,
        ),
      if (widget.isLastCharacterMessage &&
          widget.onContinue != null &&
          !widget.isBusyImpersonating)
        _buildActionButton(
          icon: Icons.arrow_forward,
          tooltip: '继续推进',
          onPressed: widget.onContinue!,
          colorScheme: colorScheme,
        ),
      if (widget.isLastCharacterMessage && widget.onImpersonate != null)
        _buildActionButton(
          icon: widget.isBusyImpersonating
              ? Icons.hourglass_top
              : Icons.lightbulb_outline,
          tooltip: widget.isBusyImpersonating ? '生成中' : '助手帮答',
          onPressed: widget.isBusyImpersonating ? null : widget.onImpersonate,
          colorScheme: colorScheme,
        ),
    ];

    if (actionWidgets.isEmpty && !widget.message.hasMultiple) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (widget.message.isMe) const Spacer(),
          ...actionWidgets,
          if (!widget.message.isMe) const Spacer(),
          if (widget.message.hasMultiple) _buildIndexSelector(colorScheme),
        ],
      ),
    );
  }

  Widget _buildIndexSelector(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSmallActionButton(
          icon: Icons.chevron_left,
          tooltip: '上一条',
          onPressed: widget.message.index > 1
              ? widget.onSelectPreviousVariant
              : null,
          colorScheme: colorScheme,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${widget.message.index}/${widget.message.total}',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        _buildSmallActionButton(
          icon: Icons.chevron_right,
          tooltip: '下一条',
          onPressed: widget.message.index < widget.message.total
              ? widget.onSelectNextVariant
              : null,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildSmallActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
  }) {
    return IconButton(
      icon: Icon(icon, size: 16),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      style: IconButton.styleFrom(
        foregroundColor: onPressed != null
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      style: IconButton.styleFrom(
        foregroundColor: onPressed != null
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
