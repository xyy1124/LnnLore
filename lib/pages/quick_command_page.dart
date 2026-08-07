import 'package:flutter/material.dart';

import '../../models/quick_command.dart';
import '../../services/quick_command_service.dart';
import '../../widgets/keyboard_safe_edit_sheet.dart';

/// 快捷指令管理页（特别版）。
///
/// 管理聊天时输入框上方的快捷指令：每个指令包含名称与提示词。
/// 点击快捷指令发送时，聊天界面只显示名称，实际发送给模型的是提示词。
class QuickCommandPage extends StatefulWidget {
  const QuickCommandPage({super.key});

  @override
  State<QuickCommandPage> createState() => _QuickCommandPageState();
}

class _QuickCommandPageState extends State<QuickCommandPage> {
  List<QuickCommand> _commands = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final commands = await QuickCommandService.instance.loadAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _commands = commands;
      _loading = false;
    });
  }

  Future<void> _onAdd() async {
    final result = await _openEditSheet(
      title: '添加快捷指令',
      initialName: '',
      initialPrompt: '',
    );
    if (result == null || !mounted) {
      return;
    }

    final service = QuickCommandService.instance;
    await service.add(
      QuickCommand(
        id: service.generateId(),
        name: result.name,
        prompt: result.prompt,
        order: _commands.length,
        type: result.type,
      ),
    );
    await _refresh();
  }

  Future<void> _onEdit(QuickCommand command) async {
    final result = await _openEditSheet(
      title: '编辑快捷指令',
      initialName: command.name,
      initialPrompt: command.prompt,
      initialType: command.type,
    );
    if (result == null || !mounted) {
      return;
    }

    await QuickCommandService.instance.update(
      command.copyWith(
        name: result.name,
        prompt: result.prompt,
        type: result.type,
      ),
    );
    await _refresh();
  }

  /// 打开键盘安全的快捷指令编辑面板（输入法弹出时按钮不跳动）。
  Future<QuickCommandEditResult?> _openEditSheet({
    required String title,
    required String initialName,
    required String initialPrompt,
    QuickCommandType initialType = QuickCommandType.direct,
  }) {
    final nameController = TextEditingController(text: initialName);
    final promptController = TextEditingController(text: initialPrompt);
    var selectedType = initialType;

    return showKeyboardSafeEditSheet<QuickCommandEditResult>(
      context: context,
      title: title,
      saveLabel: '保存',
      validateError: () {
        if (nameController.text.trim().isEmpty) {
          return '名称不能为空';
        }
        if (promptController.text.trim().isEmpty) {
          return '提示词不能为空';
        }
        return null;
      },
      fields: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: promptController,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            labelText: '提示词（实际发送给模型的内容，不会显示在聊天中）',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        // 特别版：类型选择器（自带状态——修复选择后不高亮 bug；
        // 新增第三种类型：插入输入框）
        _QuickCommandTypeSelector(
          initialType: selectedType,
          onChanged: (type) {
            selectedType = type;
          },
        ),
        const SizedBox(height: 8),
        Text(
          '${QuickCommandType.direct.label}：${QuickCommandType.direct.description}；'
          '${QuickCommandType.prompt.label}：${QuickCommandType.prompt.description}；'
          '${QuickCommandType.insert.label}：${QuickCommandType.insert.description}。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      buildResult: () {
        final name = nameController.text.trim();
        final prompt = promptController.text.trim();
        return QuickCommandEditResult(
          name: name,
          prompt: prompt,
          type: selectedType,
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      promptController.dispose();
    });
  }

  Future<void> _onDelete(QuickCommand command) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除快捷指令'),
          content: Text('确定删除快捷指令「${command.name}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await QuickCommandService.instance.delete(command.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('快捷指令')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _commands.isEmpty
          ? const Center(child: Text('还没有快捷指令，点击右下角添加'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _commands.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final command = _commands[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.bolt_outlined),
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            command.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (command.type != QuickCommandType.direct) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              command.type == QuickCommandType.prompt
                                  ? '询问'
                                  : '插入',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      command.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: '编辑',
                          onPressed: () => _onEdit(command),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                          onPressed: () => _onDelete(command),
                        ),
                      ],
                    ),
                    onTap: () => _onEdit(command),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onAdd,
        tooltip: '添加快捷指令',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 编辑面板的返回结果。
class QuickCommandEditResult {
  const QuickCommandEditResult({
    required this.name,
    required this.prompt,
    this.type = QuickCommandType.direct,
  });

  final String name;
  final String prompt;
  final QuickCommandType type;
}

/// 特别版：快捷指令类型选择器（SegmentedButton 自带状态）。
///
/// 修复：父级编辑面板的 fields 只构建一次，普通 SegmentedButton 的
/// selected 由局部变量驱动且无 setState，导致选中后不高亮（保存却正确）。
/// 本组件内部持有状态并 setState，选中即时高亮。
class _QuickCommandTypeSelector extends StatefulWidget {
  const _QuickCommandTypeSelector({
    required this.initialType,
    required this.onChanged,
  });

  final QuickCommandType initialType;
  final ValueChanged<QuickCommandType> onChanged;

  @override
  State<_QuickCommandTypeSelector> createState() =>
      _QuickCommandTypeSelectorState();
}

class _QuickCommandTypeSelectorState extends State<_QuickCommandTypeSelector> {
  late QuickCommandType _selected = widget.initialType;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<QuickCommandType>(
      segments: const [
        ButtonSegment(
          value: QuickCommandType.direct,
          label: Text('直接'),
          icon: Icon(Icons.send_outlined, size: 16),
        ),
        ButtonSegment(
          value: QuickCommandType.prompt,
          label: Text('询问后'),
          icon: Icon(Icons.edit_note_outlined, size: 16),
        ),
        ButtonSegment(
          value: QuickCommandType.insert,
          label: Text('插入'),
          icon: Icon(Icons.vertical_align_top_outlined, size: 16),
        ),
      ],
      selected: {_selected},
      onSelectionChanged: (selection) {
        setState(() {
          _selected = selection.first;
        });
        widget.onChanged(_selected);
      },
    );
  }
}
