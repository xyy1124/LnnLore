import 'package:flutter/material.dart';

import '../../../models/quick_command.dart';
import '../../../widgets/expanded_text_editor_field.dart';
import 'quick_command_marks.dart';
import 'quick_command_text_editing_controller.dart';

enum MessageEditAction { save, saveAndSend }

class MessageEditDialogResult {
  const MessageEditDialogResult({required this.action, required this.text});

  final MessageEditAction action;
  final String text;
}

class MessageEditDialog extends StatefulWidget {
  const MessageEditDialog({
    super.key,
    required this.initialText,
    required this.title,
    required this.canSaveAndSend,
    /// 特别版：编辑时可选用的快捷指令（插入占位标记，发送时展开）。
    this.quickCommands = const [],
  });

  final String initialText;
  final String title;
  final bool canSaveAndSend;
  final List<QuickCommand> quickCommands;

  @override
  State<MessageEditDialog> createState() => _MessageEditDialogState();
}

class _MessageEditDialogState extends State<MessageEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuickCommandTextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 特别版：编辑时选择并插入快捷指令（弹出菜单，选插入型指令）。
  void _openQuickCommandMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final insertCommands = widget.quickCommands
            .where((c) => c.type == QuickCommandType.insert)
            .toList();
        if (insertCommands.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('没有可插入的快捷指令（请先创建"插入输入框"类型）'),
            ),
          );
        }
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final command in insertCommands)
                ListTile(
                  leading: const Icon(Icons.vertical_align_top_outlined),
                  title: Text(command.name),
                  subtitle: Text(
                    command.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _insertQuickCommand(command);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// 特别版：在光标处插入快捷指令占位标记（斜体彩色显示，发送时展开）。
  /// 与输入框插入行为一致：与相邻文本之间自动补空格避免粘连。
  void _insertQuickCommand(QuickCommand command) {
    final name = command.name.trim();
    if (name.isEmpty) {
      return;
    }
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : start;
    final mark = wrapQuickCommandMark(name);
    final current = _controller.text;
    final leadingSpace =
        start > 0 && !RegExp(r'\s').hasMatch(current[start - 1]);
    final trailingSpace =
        end < current.length && !RegExp(r'\s').hasMatch(current[end]);
    final insertText =
        '${leadingSpace ? ' ' : ''}$mark${trailingSpace ? ' ' : ''}';
    final newText = current.substring(0, start) +
        insertText +
        current.substring(end);
    final cursor = start + insertText.length;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  void _closeWith(MessageEditAction action) {
    Navigator.of(
      context,
    ).pop(MessageEditDialogResult(action: action, text: _controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final availableHeight = mediaQuery.size.height - keyboardInset - 48;
    final dialogMaxHeight = availableHeight
        .clamp(240.0, mediaQuery.size.height)
        .toDouble();
    final keyboardVisible = keyboardInset > 0;
    final actionButtons = <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => _closeWith(MessageEditAction.save),
        child: const Text('保存'),
      ),
      if (widget.canSaveAndSend)
        FilledButton(
          onPressed: () => _closeWith(MessageEditAction.saveAndSend),
          child: const Text('保存并发送'),
        ),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: dialogMaxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                ExpandedTextEditorField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: keyboardVisible ? 5 : 10,
                  minLines: keyboardVisible ? 3 : 5,
                  dialogTitle: widget.title,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '输入消息内容',
                  ),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 特别版：编辑时插入快捷指令（占位标记，斜体彩色显示）
                      if (widget.quickCommands.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openQuickCommandMenu(context),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('插入快捷指令'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      for (var i = 0; i < actionButtons.length; i++) ...[
                        if (i > 0 || widget.quickCommands.isNotEmpty)
                          const SizedBox(width: 8),
                        actionButtons[i],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
