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
  static _MessageBubbleState? _currentPopupOwner;
  final OverlayPortalController _overlayPortalController =
      OverlayPortalController();

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

  @override
  void dispose() {
    _hideActionPopup();
    if (_currentPopupOwner == this) {
      _currentPopupOwner = null;
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hideActionPopup();
    });
  }

  void _showActionPopup() {
    if (_currentPopupOwner != null && !_currentPopupOwner!.mounted) {
      _currentPopupOwner = null;
    }
    _currentPopupOwner?._hideActionPopup();
    _hideActionPopup();
    if (!mounted) return;
    _overlayPortalController.show();
    _currentPopupOwner = this;
  }

  void _hideActionPopup() {
    if (_overlayPortalController.isShowing) {
      _overlayPortalController.hide();
    }
    if (_currentPopupOwner == this) {
      _currentPopupOwner = null;
    }
  }

  Widget _buildPopupOverlay(BuildContext context, OverlayChildLayoutInfo info) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMe = widget.message.isMe;
    final Offset targetPos = Offset(
      info.childPaintTransform.getTranslation().x,
      info.childPaintTransform.getTranslation().y,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: -targetPos.dx,
          top: -targetPos.dy,
          width: info.overlaySize.width,
          height: info.overlaySize.height,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _hideActionPopup(),
          ),
        ),
        Positioned(
          left: isMe ? null : targetPos.dx,
          right: isMe
              ? info.overlaySize.width - targetPos.dx - info.childSize.width
              : null,
          top: targetPos.dy + info.childSize.height + 4,
          child: TextFieldTapRegion(
            groupId: widget.inputTapRegionGroupId,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.surfaceContainerHigh,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildPopupActions(colorScheme),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPopupActions(ColorScheme colorScheme) {
    return <Widget>[
      _buildPopupActionButton(
        icon: Icons.copy_outlined,
        tooltip: '复制',
        onPressed: () {
          widget.onCopy();
          _hideActionPopup();
        },
        color: colorScheme.onSurface,
      ),
      if (widget.canEdit)
        _buildPopupActionButton(
          icon: Icons.edit_outlined,
          tooltip: '编辑',
          onPressed: () {
            widget.onEdit();
            _hideActionPopup();
          },
          color: colorScheme.onSurface,
        ),
      if (widget.canDelete)
        _buildPopupActionButton(
          icon: Icons.delete_outline,
          tooltip: '删除',
          onPressed: () {
            widget.onDelete();
            _hideActionPopup();
          },
          color: colorScheme.error,
        ),
    ];
  }

  Widget _buildPopupActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ExcludeFocus(
      child: IconButton(
        icon: Icon(icon, size: 18, color: color),
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        style: IconButton.styleFrom(
          foregroundColor: color,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
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
              OverlayPortal.overlayChildLayoutBuilder(
                controller: _overlayPortalController,
                overlayChildBuilder: _buildPopupOverlay,
                child: GestureDetector(
                  onTapDown: widget.showActions
                      ? (_) => _showActionPopup()
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
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.showActions) _buildActionButtons(context, colorScheme),
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

  /// 特别版：对 AI 输出应用角色卡自带正则脚本（显示阶段）。
  /// 仅角色消息生效；总开关关闭或卡无脚本时原样返回。
  /// 两次串联：先应用普通脚本，再应用 markdownOnly 脚本
  /// （markdownOnly 语义=仅 Markdown 渲染通道执行）。
  String _applyRegexScripts(String text) {
    if (!appSettingsNotifier.value.regexScriptsEnabled) {
      return text;
    }
    final scripts = RegexScriptService.scriptsFromCharacterCard(
      widget.character?.cardJson,
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
              child: OverlayPortal.overlayChildLayoutBuilder(
                controller: _overlayPortalController,
                overlayChildBuilder: _buildPopupOverlay,
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
                    GestureDetector(
                      onTapDown: widget.showActions
                          ? (_) => _showActionPopup()
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
                          );
                        }),
                      ),
                    ),
                    _buildActionButtons(context, colorScheme),
                    // 特别版：消息动作按钮（模型 choices）
                    _buildChoicesRow(context, colorScheme),
                    // 特别版：本条消息的状态面板（跟随消息渲染，
                    // 从会话变量表按消息 id 关联）
                    ?_buildMessageStatusPanel(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 本条消息的状态面板：三路兜底——
  /// ①消息级 HTML 面板（`__msg_status_html__:<id>`，该消息时的快照）
  /// ②全局最新 HTML 面板（`__special_status_html__`）
  /// ③运行时生成面板（卡的 tracker 声明 + 变量表 + **initialState 兜底**，
  /// 新会话/开场/变量表为空也能显示）
  Widget? _buildMessageStatusPanel(BuildContext context) {
    if (widget.message.isMe) {
      return null;
    }
    // 注意：draft/未落库消息 id 可能为 null——不能因此拦截（否则
    // 新会话开场消息下无状态栏），id 缺失时跳过消息级快照即可。
    String? rawHtml;
    if (widget.message.id != null) {
      rawHtml =
          widget.sessionVariables[ChatService.messageStatusHtmlKey(
            widget.message.id!,
          )];
    }
    rawHtml ??= widget.sessionVariables[kSpecialStatusHtmlKey];
    var html = rawHtml == null
        ? null
        : ChatVariableService.resolveGetVars(
            rawHtml,
            widget.sessionVariables,
          );
    if (html == null || html.trim().isEmpty) {
      html = _generateStatusPanelHtml();
    }
    if (html == null || html.trim().isEmpty) {
      return null;
    }
    // 统一清洗：模型可能按卡模板"原样输出"（输出指令要求），把
    // {{match}} 与"状态栏未更新"前缀也带进面板——显示层必须剥掉，
    // 否则所有卡都顶着"状态栏未更新"+{{match}} 原文，渲染很奇怪。
    // 同时剥掉 details/summary 折叠标签（HtmlWidget 对 details 折叠
    // 渲染不可靠），面板内容直接展开显示。
    html = html
        .replaceAll('{{match}}', '')
        .replaceAll('状态栏未更新，当前：', '')
        .replaceAll('状态栏未更新，当前:', '')
        .replaceAll('状态栏未更新', '')
        .replaceAll(RegExp(r'<details[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</details>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<summary[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</summary>', caseSensitive: false), '')
        .trim();
    if (html.isEmpty) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SpecialStatusPanel(html: html),
    );
  }

  /// 从卡 `data.extensions.regex_scripts` 取 StatusFallback 的 replaceString
  /// 作为"卡里设置的状态栏样子"（含 `{{getvar::key}}` 占位）。
  /// ⚠️ 卡 JSON 的 extensions 在 `data.extensions` 下（顶层没有）——
  ///    必须走深层路径，否则所有卡都读不到模板、统一回退内置样式。
  String? _statusFallbackTemplate() =>
      TrackerRuntime.statusFallbackTemplate(widget.character?.cardJson);

  /// 运行时生成状态面板：无模型输出面板时，优先按**卡内 StatusFallback
  /// 模板**渲染（`{{getvar::key}}` 用变量表值/initialState 填充）——
  /// 样子与角色卡预期一致；卡无模板时回退内置深色卡片。
  String? _generateStatusPanelHtml() {
    final config = TrackerConfig.fromCardJson(widget.character?.cardJson);
    if (!config.isEnabled) {
      return null;
    }
    // 值来源：会话变量优先，缺失回退卡 initialState
    String? valueOf(String key) {
      final v = widget.sessionVariables[key];
      if (v != null && v.isNotEmpty) {
        return v;
      }
      final init = config.initialState[key];
      return init == null ? null : '$init';
    }

    // ① 卡 StatusFallback 模板（卡内定义的状态栏样子）。
    // 去掉"状态栏未更新，当前："前缀——那是 ST 正则兜底的文案，
    // 在 PocketInn 里模板用作默认面板，顶着"未更新"三个字很怪；
    // 去掉后直接显示状态（各卡字段不同），与模型输出面板观感一致。
    final template = _statusFallbackTemplate();
    if (template != null && template.contains('getvar')) {
      var rendered = template
          .replaceAll('{{match}}', '')
          .replaceAll(r'\n', '\n');
      rendered = rendered.replaceAllMapped(
        RegExp(r'\{\{\s*getvar::([^}]+)\}\}', caseSensitive: false),
        (m) => valueOf(m.group(1)!.trim()) ?? '',
      );
      rendered = rendered
          .replaceAll('状态栏未更新，当前：', '')
          .replaceAll('状态栏未更新，当前:', '')
          .replaceAll('状态栏未更新', '');
      if (rendered.trim().isNotEmpty) {
        return '<div class="status-panel" style="display:flex;'
            'flex-wrap:wrap;gap:6px 8px;align-items:center;padding:8px 10px;'
            'border-radius:10px;background:rgba(120,80,220,0.08);'
            'border:1px solid rgba(120,80,220,0.25);'
            'font-size:12px;">$rendered</div>';
      }
    }

    // ② 内置深色卡片（卡无模板/无 getvar 时兜底）
    final chips = <String>[];
    for (final key in config.displayOrder) {
      final schema = config.stateSchema[key];
      if (schema == null || schema.hidden) {
        continue;
      }
      final value = valueOf(key);
      if (value == null) {
        continue;
      }
      final label = schema.label.isNotEmpty ? schema.label : key;
      // number 字段带 max → 显示 值/max（进度感）
      final display = (schema.type == 'number' && schema.max != null)
          ? '$value/${schema.max}'
          : value;
      chips.add(
        '<span style="background:rgba(255,255,255,0.07);'
        'border:1px solid rgba(255,255,255,0.10);'
        'border-radius:999px;padding:2px 10px;font-size:12px;'
        'white-space:nowrap;">$label：$display</span>',
      );
    }
    if (chips.isEmpty) {
      return null;
    }

    // 深色主题卡片 + 字段 chips（外观接近模型输出的 HTML 面板）
    return '<div class="status-panel" style="display:flex;flex-wrap:wrap;'
        'gap:6px 8px;align-items:center;padding:8px 10px;'
        'border-radius:10px;'
        'background:rgba(120,80,220,0.08);'
        'border:1px solid rgba(120,80,220,0.25);">'
        '<span style="font-size:12px;font-weight:600;color:#b388ff;">'
        '📊 状态</span>${chips.join('')}</div>';
  }

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
