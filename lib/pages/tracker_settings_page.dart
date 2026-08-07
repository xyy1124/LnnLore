import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/storage_service.dart';

/// v60：状态更新设置——剧情自主状态判断（状态裁判）开关与三档模式。
///
/// - 状态裁判：剧情生成后独立调用一次状态判断请求（只输出 JSON
///   patch）——剧情模型专心写剧情，状态由裁判按规则确定性判断。
/// - 模式：仅明确指令 / 保守剧情判断（默认）/ 积极剧情判断。
class TrackerSettingsPage extends StatefulWidget {
  const TrackerSettingsPage({super.key});

  @override
  State<TrackerSettingsPage> createState() => _TrackerSettingsPageState();
}

class _TrackerSettingsPageState extends State<TrackerSettingsPage> {
  bool _judgeEnabled = true;
  String _mode = 'conservative';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await ChatService.isTrackerJudgeEnabled();
    final mode = await ChatService.getTrackerJudgeMode();
    if (!mounted) {
      return;
    }
    setState(() {
      _judgeEnabled = enabled;
      _mode = mode;
      _loaded = true;
    });
  }

  Future<void> _setJudgeEnabled(bool value) async {
    setState(() => _judgeEnabled = value);
    await StorageService.instance.setBool(ChatService.kJudgeEnabledKey, value);
  }

  Future<void> _setMode(String value) async {
    setState(() => _mode = value);
    await StorageService.instance.setString(ChatService.kJudgeModeKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('状态更新')),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: const Text('状态裁判（双阶段判断）'),
                  subtitle: const Text(
                    '剧情生成后独立调用一次状态判断请求，只输出 JSON patch——'
                    '剧情明确表示状态变化时（即使没有具体数字）也会按规则更新，'
                    '不再依赖剧情模型在长篇回复末尾顺便输出协议',
                  ),
                  value: _judgeEnabled,
                  onChanged: _setJudgeEnabled,
                ),
                const SizedBox(height: 8),
                Text(
                  '剧情自主更新模式',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                RadioListTile<String>(
                  title: const Text('仅明确指令'),
                  subtitle: const Text('只处理明确状态描述（（好感度+2）/好感提升一点），不因剧情自行推断'),
                  value: 'explicit',
                  groupValue: _mode,
                  onChanged: _judgeEnabled
                      ? (v) => _setMode(v!)
                      : null,
                ),
                RadioListTile<String>(
                  title: const Text('保守剧情判断（推荐）'),
                  subtitle: const Text('除明确指令外，允许从非常明确的剧情结果推断小幅变化（她接受道歉、戒备明显放松 → +1）；普通对话/心理描写/重复描述不更新'),
                  value: 'conservative',
                  groupValue: _mode,
                  onChanged: _judgeEnabled
                      ? (v) => _setMode(v!)
                      : null,
                ),
                RadioListTile<String>(
                  title: const Text('积极剧情判断'),
                  subtitle: const Text('允许根据整体剧情主动调整（共同战斗/赠送礼物/发生冲突等都可能触发变化）'),
                  value: 'active',
                  groupValue: _mode,
                  onChanged: _judgeEnabled
                      ? (v) => _setMode(v!)
                      : null,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '说明：具体"程度词 → 数值"的量化规则由角色卡的 '
                    'updatePolicy.qualitativeDeltas 声明（如 一点=1、明显=5、'
                    '大幅=10）；未声明的卡按保守模式由模型/裁判参照常规幅度判断。'
                    '每轮每字段最多更新一次，增量受 maxAutoDeltaPerTurn 限制，'
                    '防止状态膨胀。',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
