import 'dart:math';

import '../models/quick_command.dart';
import 'storage_service.dart';

/// 快捷指令服务（特别版功能）。
///
/// 负责快捷指令的持久化储存和管理。数据存储为单文件
/// `quick_commands.json`（结构 `{version, commands[]}`），
/// 模式与 UserSettingsService 一致。
class QuickCommandService {
  QuickCommandService._();

  static final QuickCommandService instance = QuickCommandService._();

  // JSON 文件名
  static const String _filename = 'quick_commands.json';

  // 数据版本（用于未来数据迁移）
  static const int _dataVersion = 1;

  /// 内置的默认快捷指令（首次使用时的示例，可删除/编辑）。
  static List<QuickCommand> get defaultQuickCommands => [
    QuickCommand(
      id: 'quick-continue',
      name: '继续',
      prompt: '请自然地继续推进当前场景，保持原有风格、语气与节奏，'
          '延续上一条回复的走向，不要重复已写过的内容。',
      order: 0,
      type: QuickCommandType.direct,
    ),
    QuickCommand(
      id: 'quick-time-skip',
      name: '时间流逝',
      prompt: '请让场景中的时间自然流逝，交代流逝期间发生的事情与角色状态变化，'
          '然后从新的时间点继续描写。',
      order: 1,
      type: QuickCommandType.prompt,
    ),
    QuickCommand(
      id: 'quick-next-scene',
      name: '下一场景',
      prompt: '请结束当前场景，切换到下一个自然衔接的新场景（可更换地点、时间），'
          '交代场景过渡，并保持世界观与人物设定的一致性。',
      order: 2,
      type: QuickCommandType.direct,
    ),
    QuickCommand(
      id: 'quick-narration',
      name: '旁白',
      prompt: '请以旁白视角进行叙述，交代当前画面、环境与角色状态，'
          '补充场景中没有明说的氛围与细节。',
      order: 3,
      type: QuickCommandType.prompt,
    ),
    QuickCommand(
      id: 'quick-detailed',
      name: '详细描写',
      prompt: '请对指定内容进行高密度、详细的描写，'
          '包括视觉、声音、气味、触感与情绪变化，放慢节奏逐层展开。',
      order: 4,
      type: QuickCommandType.prompt,
    ),
    QuickCommand(
      id: 'quick-camera',
      name: '摄像机视角',
      prompt: '请切换为电影镜头式的叙事视角，描写当前画面（景别、构图、光线、'
          '镜头运动），并给出画面中的重点细节。',
      order: 5,
      type: QuickCommandType.prompt,
    ),
  ];

  /// 加载所有快捷指令（首次使用返回内置默认指令）。
  Future<List<QuickCommand>> loadAll() async {
    final storage = StorageService.instance;

    final data = await storage.readJsonMap(_filename);
    if (data == null) {
      // 文件不存在：首次使用，返回内置默认指令
      return defaultQuickCommands;
    }

    try {
      final version = data['version'] as int? ?? 1;
      if (version != _dataVersion) {
        return defaultQuickCommands;
      }

      final commandsList = data['commands'] as List<dynamic>?;
      if (commandsList == null) {
        return defaultQuickCommands;
      }
      if (commandsList.isEmpty) {
        // 文件存在但用户已删光全部指令：尊重用户选择，不重新播种
        return [];
      }

      final commands = commandsList
          .map((json) => QuickCommand.fromJson(json as Map<String, dynamic>))
          .toList();
      commands.sort((a, b) => a.order.compareTo(b.order));
      return commands;
    } on Object {
      // 文件损坏（如写入中断或类型异常）：回退默认，避免崩溃
      return defaultQuickCommands;
    }
  }

  /// 保存所有快捷指令。
  Future<void> saveAll(List<QuickCommand> commands) async {
    final storage = StorageService.instance;

    final sorted = [...commands]..sort((a, b) => a.order.compareTo(b.order));
    final data = {
      'version': _dataVersion,
      'commands': sorted.map((c) => c.toJson()).toList(),
    };

    await storage.writeJsonMap(_filename, data);
  }

  /// 添加快捷指令。
  Future<void> add(QuickCommand command) async {
    final commands = await loadAll();
    commands.add(command);
    await saveAll(commands);
  }

  /// 更新快捷指令。
  Future<void> update(QuickCommand command) async {
    final commands = await loadAll();
    final index = commands.indexWhere((c) => c.id == command.id);
    if (index != -1) {
      commands[index] = command;
      await saveAll(commands);
    }
  }

  /// 删除快捷指令。
  Future<List<QuickCommand>> delete(String id) async {
    final commands = await loadAll();
    commands.removeWhere((c) => c.id == id);
    await saveAll(commands);
    return commands;
  }

  /// 生成唯一ID。
  String generateId() {
    final random = Random().nextInt(0xFFFFFF).toRadixString(16);
    return 'quick-command-${DateTime.now().millisecondsSinceEpoch}-$random';
  }
}
