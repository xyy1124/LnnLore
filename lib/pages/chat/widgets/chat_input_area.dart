import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../data/app_settings.dart';
import '../../../data/mock_user_settings.dart';
import '../../../models/quick_command.dart';
import '../../../models/world_book.dart';
import '../../../theme/chat_reading_theme.dart';
import '../../../widgets/keyboard_safe_edit_sheet.dart';
import 'quick_command_marks.dart';

class ChatInputArea extends StatelessWidget {
  const ChatInputArea({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.inputTapRegionGroupId,
    required this.sessionKey,
    required this.isSendEnabled,
    required this.isSending,
    required this.hasBackground,
    required this.settings,
    required this.worldBooks,
    required this.selectedWorldBookIds,
    required this.currentUserSetting,
    required this.onUserSettingsPressed,
    required this.onWorldBookPressed,
    required this.onPresetPressed,
    required this.onSendPressed,
    required this.onStopGeneratingPressed,
    this.quickCommands = const [],
    this.onQuickCommand,
    this.onQuickCommandWithExtra,
    this.contextUsedTokens = 0,
    this.contextMaxTokens = 0,
    this.onOpenContextUsage,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final Object inputTapRegionGroupId;
  final Key? sessionKey;
  final bool isSendEnabled;
  final bool isSending;
  final bool hasBackground;
  final AppSettings settings;
  final List<WorldBook> worldBooks;
  final Set<String> selectedWorldBookIds;
  final UserSetting? currentUserSetting;
  final ValueChanged<BuildContext> onUserSettingsPressed;
  final ValueChanged<BuildContext> onWorldBookPressed;
  final ValueChanged<BuildContext> onPresetPressed;
  final VoidCallback onSendPressed;
  final VoidCallback onStopGeneratingPressed;

  /// 特别版：快捷指令列表（供 + 菜单使用）。
  final List<QuickCommand> quickCommands;
  final ValueChanged<QuickCommand>? onQuickCommand;

  /// 特别版：询问型快捷指令（补充内容后发送）。
  final void Function(QuickCommand command, String extra)? onQuickCommandWithExtra;

  /// 特别版：上下文用量（估算 token；>0 时显示入口条）。
  final int contextUsedTokens;
  final int contextMaxTokens;
  final VoidCallback? onOpenContextUsage;

  /// 特别版（E 方案）：打开快捷指令面板（分类页签 + 大卡片 + 提示词预览）。
  void _openQuickCommandMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _QuickCommandMenuSheet(
        commands: quickCommands,
        onPick: (command) {
          Navigator.pop(sheetContext);
          _handleQuickCommand(context, command);
        },
      ),
    );
  }

  /// 特别版：按类型分发——直接发送 / 询问后发送 / 插入输入框。
  void _handleQuickCommand(BuildContext context, QuickCommand command) {
    switch (command.type) {
      case QuickCommandType.direct:
        onQuickCommand?.call(command);
      case QuickCommandType.prompt:
        _promptForExtra(context, command);
      case QuickCommandType.insert:
        _insertQuickCommand(context, command);
    }
  }

  /// 特别版：插入型——把快捷指令「占位标记」插入输入框当前光标位置，
  /// 不发送；可连续点击多个累计插入；标记在输入框内以斜体彩色显示，
  /// 发送时才展开为提示词（占位标记本身是普通文本，可随内容一起发送）。
  void _insertQuickCommand(BuildContext context, QuickCommand command) {
    final name = command.name.trim();
    if (name.isEmpty) {
      return;
    }
    final selection = textController.selection;
    final start = selection.isValid ? selection.start : textController.text.length;
    final end = selection.isValid ? selection.end : start;
    final mark = wrapQuickCommandMark(name);
    final (newText, cursorOffset) = insertTextAtCursor(
      textController.text,
      mark,
      start,
      end,
    );
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
    FocusScope.of(context).requestFocus(focusNode);
  }

  /// 特别版（E 方案）：工具胶囊（统一高度/圆角，防误触且美观）。
  /// 所有胶囊内容自适应宽度（同预设大小），超长标签按字符截断省略。
  /// [maxLabelChars]：超过该字符数显示前 N 字 + …（用户设定/世界书用）。
  Widget _toolChip({
    required Widget icon,
    required String label,
    required VoidCallback? onTap,
    required ColorScheme colorScheme,
    required ChatReadingTheme readingTheme,
    int maxLabelChars = 20,
  }) {
    final displayLabel = label.runes.length > maxLabelChars
        ? '${String.fromCharCodes(label.runes.take(maxLabelChars))}…'
        : label;
    return Material(
      color: readingTheme.composerToolSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 6),
              Text(
                displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: readingTheme.composerText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 特别版：询问型指令的补充内容对话框。
  /// 使用键盘安全面板（按钮固定在底部不随键盘移动）；提示词超长时
  /// 输入区可滚动；对话框通过返回值传递补充文本；无论取消/遮罩/
  /// 发送，controller 都在对话框关闭后统一释放，避免 use-after-dispose。
  Future<void> _promptForExtra(
    BuildContext context,
    QuickCommand command,
  ) async {
    final controller = TextEditingController();
    final extra = await showKeyboardSafeEditSheet<String>(
      context: context,
      title: command.name,
      saveLabel: '发送',
      fields: [
        // 提示词说明（超长时随输入区滚动，不影响底部按钮）
        Text(
          command.prompt,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final canSend = value.text.trim().isNotEmpty;
            return TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '补充内容',
                hintText: '如：流逝一夜 / 描写她的表情 / 拉近镜头',
                border: OutlineInputBorder(),
              ),
              onSubmitted: canSend
                  ? (text) => Navigator.of(context).pop(text.trim())
                  : null,
            );
          },
        ),
      ],
      buildResult: () {
        final trimmed = controller.text.trim();
        return trimmed.isEmpty ? null : trimmed;
      },
    );
    // 面板已关闭：统一释放控制器
    controller.dispose();
    if (extra != null && extra.isNotEmpty) {
      onQuickCommandWithExtra?.call(command, extra);
    }
  }

  Widget _wrapTapRegion(Widget child) {
    return TextFieldTapRegion(groupId: inputTapRegionGroupId, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final readingTheme = context.chatReadingTheme;
    final hasWorldBooks = worldBooks.isNotEmpty;
    final selectedWorldBooks = worldBooks
        .where((item) => selectedWorldBookIds.contains(item.id))
        .toList();
    final worldBookDisplayText = selectedWorldBooks.isEmpty
        ? '世界书'
        : selectedWorldBooks.length == 1
        ? selectedWorldBooks.first.name
        : '${selectedWorldBooks.length} 本世界书';
    final worldBookColor = selectedWorldBooks.isNotEmpty
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final useGlassEffect = hasBackground && settings.inputGlassEffect;

    Widget inputContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 特别版（E 方案）：输入框上方一行 —— 左：快捷指令入口；右：上下文用量条
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              // 快捷指令入口（无指令时隐藏）
              if (quickCommands.isNotEmpty)
                InkWell(
                  onTap: isSending
                      ? null
                      : () {
                          // 先收键盘，避免面板被键盘顶出屏幕
                          FocusManager.instance.primaryFocus?.unfocus();
                          _openQuickCommandMenu(context);
                        },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: readingTheme.composerToolSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          size: 16,
                          color: isSending
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '快捷指令',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: readingTheme.composerText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              // 上下文用量入口（常驻显示；未发送过显示估算值）
              if (onOpenContextUsage != null)
                InkWell(
                  onTap: onOpenContextUsage,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: readingTheme.composerToolSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            value: (contextMaxTokens <= 0
                                    ? 0.0
                                    : (contextUsedTokens / contextMaxTokens))
                                .clamp(0.0, 1.0),
                            strokeWidth: 2.5,
                            backgroundColor: readingTheme.composerSurface,
                            color: contextMaxTokens > 0 &&
                                    contextUsedTokens / contextMaxTokens > 0.9
                                ? colorScheme.error
                                : colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          contextUsedTokens > 0
                              // v61：明确"预计/约"——估算值不冒充精确
                              // 已用；分母为安全输入上限（扣除输出预留）
                              ? '约 ${_formatTokens(contextUsedTokens)}/'
                                  '${_formatTokens(contextMaxTokens)}'
                                  '（预计 ${contextMaxTokens <= 0 ? 0 : (contextUsedTokens * 100 / contextMaxTokens).toStringAsFixed(0)}%）'
                              : '用量待发送后统计',
                          style: TextStyle(
                            fontSize: 11,
                            color: readingTheme.composerText,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: readingTheme.composerText,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 特别版（E 方案）：输入框与内嵌发送键（右下圆形）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Stack(
            children: [
              TextField(
                key: sessionKey,
                controller: textController,
                focusNode: focusNode,
                groupId: inputTapRegionGroupId,
                maxLines: 6,
                // 特别版：输入栏高度调高（默认两行）
                minLines: 2,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '输入消息',
                  hintStyle: TextStyle(color: readingTheme.composerHint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(
                    right: 44,
                    top: 8,
                    bottom: 8,
                  ),
                ),
                style: TextStyle(
                  fontSize: 16,
                  color: readingTheme.composerText,
                ),
              ),
              // 发送键：输入框右下角内嵌（圆形渐变，发送/停止切换；
              // 禁用态用 IgnorePointer 让点击穿透到输入框）
              Positioned(
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !isSending && !isSendEnabled,
                  child: InkWell(
                    onTap: isSending
                        ? onStopGeneratingPressed
                        : (isSendEnabled ? onSendPressed : null),
                    borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSending
                          ? readingTheme.composerStop
                          : isSendEnabled
                          ? readingTheme.composerSend
                          : readingTheme.composerToolSurface,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isSending
                          ? Icons.stop_rounded
                          : Icons.arrow_upward_rounded,
                      size: 20,
                      color: isSending
                          ? colorScheme.onError
                          : isSendEnabled
                          ? colorScheme.onPrimary
                          : readingTheme.composerHint,
                    ),
                  ),
                ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              // 用户设定：图标 + 最多 2 字 + 省略号，内容自适应靠左
              Builder(
                builder: (context) => ValueListenableBuilder<List<UserSetting>>(
                  valueListenable: userSettingsNotifier,
                  builder: (context, userSettings, _) {
                    if (userSettings.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final selectedSetting = currentUserSetting;
                    if (selectedSetting == null) {
                      return const SizedBox.shrink();
                    }

                    return _toolChip(
                      icon: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: selectedSetting.color,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          selectedSetting.avatarText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      label: selectedSetting.name,
                      maxLabelChars: 2,
                      onTap: () => onUserSettingsPressed(context),
                      colorScheme: colorScheme,
                      readingTheme: readingTheme,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 世界书：图标 + 最多 2 字 + 省略号，内容自适应靠左
              Builder(
                builder: (context) => _toolChip(
                  icon: Icon(
                    Icons.menu_book_rounded,
                    size: 16,
                    color: worldBookColor,
                  ),
                  label: worldBookDisplayText,
                  maxLabelChars: 2,
                  onTap: hasWorldBooks
                      ? () => onWorldBookPressed(context)
                      : null,
                  colorScheme: colorScheme,
                  readingTheme: readingTheme,
                ),
              ),
              const SizedBox(width: 8),
              // 预设：固定小胶囊
              Builder(
                builder: (context) => _toolChip(
                  icon: Icon(
                    Icons.tune,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  label: '预设',
                  onTap: () => onPresetPressed(context),
                  colorScheme: colorScheme,
                  readingTheme: readingTheme,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    inputContent = _wrapTapRegion(inputContent);

    if (useGlassEffect) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: readingTheme.composerGlassSurface,
                border: Border.all(
                  color: readingTheme.composerBorder,
                  width: 0.5,
                ),
              ),
              child: inputContent,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: readingTheme.composerSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: readingTheme.composerShadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: readingTheme.composerBorder, width: 0.5),
      ),
      child: inputContent,
    );
  }

  /// 格式化 token 数（>1000 显示为 K）。
  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    }
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return '$tokens';
  }
}

/// 特别版：插入型快捷指令的纯函数——把 [insertion] 插入 [current] 的
/// [start, end) 区间（覆盖选中文本），返回插入后的文本与光标偏移。
/// 供 [ChatInputArea] 的插入逻辑使用，便于单元测试。
(String text, int cursorOffset) insertTextAtCursor(
  String current,
  String insertion,
  int start,
  int end,
) {
  final safeStart = start.clamp(0, current.length);
  final safeEnd = end.clamp(safeStart, current.length);
  // 仅无选区（start==end）且插入位置在中间时才补空格，避免粘连；
  // 覆盖选区时不补（直接替换选中文本）
  final suffix = safeStart == safeEnd && safeEnd < current.length ? ' ' : '';
  final piece = '$insertion$suffix';
  final newText = current.replaceRange(safeStart, safeEnd, piece);
  return (newText, safeStart + piece.length);
}

/// 特别版（E 方案）：快捷指令面板——分类页签 + 大卡片 + 提示词预览。
class _QuickCommandMenuSheet extends StatefulWidget {
  const _QuickCommandMenuSheet({
    required this.commands,
    required this.onPick,
  });

  final List<QuickCommand> commands;
  final ValueChanged<QuickCommand> onPick;

  @override
  State<_QuickCommandMenuSheet> createState() => _QuickCommandMenuSheetState();
}

class _QuickCommandMenuSheetState extends State<_QuickCommandMenuSheet> {
  QuickCommandType _selectedType = QuickCommandType.direct;

  List<QuickCommand> get _filtered =>
      widget.commands.where((c) => c.type == _selectedType).toList();

  IconData _typeIcon(QuickCommandType type) => switch (type) {
    QuickCommandType.direct => Icons.send_outlined,
    QuickCommandType.prompt => Icons.edit_note_outlined,
    QuickCommandType.insert => Icons.vertical_align_top_outlined,
  };

  String _typeHint(QuickCommandType type) => switch (type) {
    QuickCommandType.direct => '点击立即发送',
    QuickCommandType.prompt => '点击后补充内容再发送',
    QuickCommandType.insert => '插入输入框（发送时展开）',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final readingTheme = context.chatReadingTheme;
    final filtered = _filtered;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 + 关闭
            Row(
              children: [
                Text(
                  '快捷指令',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 分类页签
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<QuickCommandType>(
                segments: [
                  for (final type in QuickCommandType.values)
                    ButtonSegment(
                      value: type,
                      icon: Icon(_typeIcon(type), size: 16),
                      label: Text(type.label),
                    ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (selection) {
                  setState(() => _selectedType = selection.first);
                },
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // 分类说明
            Text(
              _typeHint(_selectedType),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: readingTheme.thinkingLabel,
              ),
            ),
            const SizedBox(height: 8),
            // 当前分类指令
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 32,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '暂无指令',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final command = filtered[index];
                    return Material(
                      color: readingTheme.composerSurface,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => widget.onPick(command),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: readingTheme.composerToolSurface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  _typeIcon(command.type),
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      command.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      command.prompt.trim().isEmpty
                                          ? '（无提示词）'
                                          : command.prompt,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
