import 'package:flutter/material.dart';

import '../models/thinking_chain_preset.dart';
import '../services/thinking_chain_guard.dart';
import '../services/thinking_chain_preset_service.dart';
import '../widgets/keyboard_safe_edit_sheet.dart';

/// 思维链约束方案管理页（特别版）。
///
/// 可创建多套【强制思维模式】模板方案，选择一套作为当前生效。
/// 模板必须保留 12 步步骤标题（校验锚点：第 1 步与第 12 步必备，
/// 且至少保留 6 个步骤标记，否则模型输出将无法通过校验）。
class ThinkingChainPresetPage extends StatefulWidget {
  const ThinkingChainPresetPage({super.key});

  @override
  State<ThinkingChainPresetPage> createState() =>
      _ThinkingChainPresetPageState();
}

class _ThinkingChainPresetPageState extends State<ThinkingChainPresetPage> {
  List<ThinkingChainPreset> _presets = [];
  String? _activeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = ThinkingChainPresetService.instance;
    final presets = await service.loadAll();
    final activeId = await service.getActiveId();
    if (!mounted) {
      return;
    }
    setState(() {
      _presets = presets;
      _activeId = activeId;
      _loading = false;
    });
  }

  Future<void> _onActivate(ThinkingChainPreset preset) async {
    await ThinkingChainPresetService.instance.setActiveId(preset.id);
    await _refresh();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已启用方案：${preset.name}')));
  }

  Future<void> _onEdit(ThinkingChainPreset preset) async {
    final result = await _openEditSheet(
      title: '编辑思维链方案',
      initialName: preset.name,
      initialTemplate: preset.template,
    );
    if (result == null || !mounted) {
      return;
    }
    await ThinkingChainPresetService.instance.update(
      preset.copyWith(
        name: result.name,
        template: result.template,
        updatedAt: DateTime.now(),
      ),
    );
    await _refresh();
  }

  Future<void> _onAdd() async {
    final result = await _openEditSheet(
      title: '新建思维链方案',
      initialName: '',
      initialTemplate: ThinkingChainGuard.systemTemplate,
    );
    if (result == null || !mounted) {
      return;
    }
    final service = ThinkingChainPresetService.instance;
    await service.add(
      ThinkingChainPreset(
        id: service.generateId(),
        name: result.name,
        template: result.template,
        updatedAt: DateTime.now(),
      ),
      activate: true,
    );
    await _refresh();
  }

  /// 打开键盘安全的方案编辑面板（输入法弹出时按钮不跳动）。
  Future<ThinkingChainTemplateEditResult?> _openEditSheet({
    required String title,
    required String initialName,
    required String initialTemplate,
  }) {
    final nameController = TextEditingController(text: initialName);
    final templateController = TextEditingController(text: initialTemplate);

    return showKeyboardSafeEditSheet<ThinkingChainTemplateEditResult>(
      context: context,
      title: title,
      saveLabel: '保存',
      validateError: () {
        if (nameController.text.trim().isEmpty) {
          return '方案名称不能为空';
        }
        if (templateController.text.trim().isEmpty) {
          return '模板不能为空';
        }
        return null;
      },
      fields: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '方案名称',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: templateController,
          maxLines: 16,
          minLines: 8,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            labelText: '模板（建议保留 12 步结构）',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '提示：校验采用内容启发式——输出需包含闭合的 <think> 思考块'
          '且内容 ≥80 字；建议模板保留 12 步结构。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      buildResult: () {
        final name = nameController.text.trim();
        final template = templateController.text.trim();
        return ThinkingChainTemplateEditResult(
          name: name,
          template: template,
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      templateController.dispose();
    });
  }

  Future<void> _onDelete(ThinkingChainPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除方案'),
          content: Text('确定删除思维链约束方案「${preset.name}」吗？'),
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
    await ThinkingChainPresetService.instance.delete(preset.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('思维链约束')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '选择一套方案作为当前生效的思维链约束。'
                      '校验采用内容启发式：只要输出包含 <think> 闭合的思考块'
                      '且思考内容达到足够长度（≥80 字）即通过；'
                      '完全不思考的输出才会被退回重试。'
                      '建议模板保留 12 步结构以获得最佳思考质量。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final preset in _presets) ...[
                  Card(
                    child: ListTile(
                      leading: Icon(
                        preset.id == _activeId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: preset.id == _activeId
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        preset.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        preset.template,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: '编辑模板',
                            onPressed: () => _onEdit(preset),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除',
                            onPressed: () => _onDelete(preset),
                          ),
                        ],
                      ),
                      onTap: () => _onActivate(preset),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onAdd,
        icon: const Icon(Icons.add),
        label: const Text('新建方案'),
      ),
    );
  }
}

/// 编辑对话框返回结果。
class ThinkingChainTemplateEditResult {
  const ThinkingChainTemplateEditResult({
    required this.name,
    required this.template,
  });

  final String name;
  final String template;
}

