import 'package:flutter/material.dart';

import '../data/api_configs.dart';
import '../services/character_intro_service.dart';

/// 角色 AI 介绍设置页（特别版）。
///
/// 选择"角色通读介绍"使用的 AI 模型；不设置时跟随当前选中的聊天模型。
class CharacterIntroSettingsPage extends StatefulWidget {
  const CharacterIntroSettingsPage({super.key});

  @override
  State<CharacterIntroSettingsPage> createState() =>
      _CharacterIntroSettingsPageState();
}

class _CharacterIntroSettingsPageState
    extends State<CharacterIntroSettingsPage> {
  String? _selectedModelId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await CharacterIntroService.instance.getIntroApiModelId();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedModelId = saved;
      _loading = false;
    });
  }

  Future<void> _onChanged(String? modelId) async {
    await CharacterIntroService.instance.setIntroApiModelId(modelId);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedModelId = modelId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final configs = apiConfigsNotifier.value;

    return Scaffold(
      appBar: AppBar(title: const Text('角色介绍 AI')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '「角色列表」右下角箭头会通读角色卡与配套世界书，'
                      '用这里的模型生成角色简介与玩法说明。\n'
                      '不选择时自动跟随当前聊天使用的模型。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: RadioGroup<String?>(
                    groupValue: _selectedModelId,
                    onChanged: _onChanged,
                    child: Column(
                      children: [
                        RadioListTile<String?>(
                          title: const Text('跟随当前聊天模型'),
                          subtitle: const Text('默认选项，与聊天使用同一模型'),
                          value: null,
                        ),
                        for (final config in configs)
                          for (final model in config.models)
                            RadioListTile<String?>(
                              title: Text(model.id),
                              subtitle: Text(config.name),
                              value: model.id,
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
