import 'package:get_it/get_it.dart';

import '../data/api_configs.dart';
import '../models/api_config.dart';
import '../models/character_card.dart';
import '../models/world_book.dart';
import 'i_openai_api_service.dart';
import 'storage_service.dart';

/// 角色 AI 通读介绍服务（特别版）。
///
/// 通读角色卡及其配套世界书，用配置的 AI 模型生成角色简介与玩法说明。
class CharacterIntroService {
  CharacterIntroService._();

  static final CharacterIntroService instance = CharacterIntroService._();

  /// SharedPreferences 键名：介绍生成使用的模型 id（ApiModel.id）。
  /// 未设置时跟随当前选中的聊天模型。
  static const String _keyIntroApiModelId = 'character_intro_api_model_id';

  /// 获取介绍专用的模型 id（可能为 null，表示跟随当前选中模型）。
  Future<String?> getIntroApiModelId() async {
    final saved = StorageService.instance.getString(_keyIntroApiModelId);
    if (saved == null || saved.isEmpty) {
      return null;
    }
    return saved;
  }

  /// 设置介绍专用模型 id（null 表示跟随当前选中模型）。
  Future<void> setIntroApiModelId(String? id) async {
    if (id == null || id.isEmpty) {
      await StorageService.instance.remove(_keyIntroApiModelId);
    } else {
      await StorageService.instance.setString(_keyIntroApiModelId, id);
    }
  }

  /// 解析介绍生成使用的配置：优先专用设置，回退当前选中模型。
  ResolvedApiConfig? resolveIntroConfig() {
    final introId = getIntroApiModelIdSync();
    if (introId != null && introId.isNotEmpty) {
      for (final config in apiConfigsNotifier.value) {
        for (final model in config.models) {
          if (model.id == introId) {
            return config.resolve(model);
          }
        }
      }
    }
    return resolvedSelectedApi;
  }

  String? getIntroApiModelIdSync() {
    final saved = StorageService.instance.getString(_keyIntroApiModelId);
    if (saved == null || saved.isEmpty) {
      return null;
    }
    return saved;
  }

  /// 生成角色介绍与玩法说明。
  ///
  /// [character] 角色卡完整记录；[worldBook] 可选的世界书。
  Future<String> generateIntroduction({
    required CharacterCardRecord character,
    WorldBook? worldBook,
  }) async {
    final config = resolveIntroConfig();
    if (config == null) {
      throw StateError('未配置可用的 AI 模型，请先在 API 配置中设置');
    }

    final prompt = _buildPrompt(character, worldBook);
    final api = GetIt.instance<IOpenAiApiService>();
    final result = await api.createChatCompletion(
      config,
      messages: [
        {
          'role': 'system',
          'content': '你是一位资深的 AI 角色扮演游戏设计师与角色卡解读专家。'
              '用户会提供一份角色卡（含人物设定）以及可选的世界书（世界观/规则/事件资料）。'
              '请通读全部内容后进行【深度解读】，输出一份完整、详细、可直接上手游玩的角色介绍。'
              '要求：\n'
              '- 不要照抄或复述角色卡原文，要提炼、概括并补充你的专业解读；\n'
              '- 挖掘角色设定背后的动机、冲突点、成长空间与扮演价值；\n'
              '- 指出角色卡中容易忽略但值得玩出的细节；\n'
              '- 玩法建议要具体、可操作（给出开场示例、可选的互动方向、如何制造冲突与张力）。\n'
              '必须包含以下小节（使用 Markdown 标题与列表）：\n'
              '# 角色简介\n（身份、外貌、性格概述，一两句话抓住精髓）\n'
              '# 核心设定与世界观\n（关键背景、势力/环境要点）\n'
              '# 性格与行为模式\n（说话风格、癖好、雷区、互动倾向）\n'
              '# 世界书要点\n（重要的规则、关键词、事件、设定，逐条列出并解释用途）\n'
              '# 玩法与互动建议\n（推荐的切入方式、可玩方向、注意事项，尽量详细具体）\n'
              '# 亮点与隐藏细节\n（值得玩出的伏笔、反差、扮演张力）\n'
              '请用简体中文输出。',
        },
        {'role': 'user', 'content': prompt},
      ],
    );
    final text = result.text.trim();
    if (text.isEmpty) {
      throw StateError('AI 未返回介绍内容，请重试');
    }
    return text;
  }

  String _buildPrompt(CharacterCardRecord character, WorldBook? worldBook) {
    final buffer = StringBuffer();

    buffer.writeln('【角色卡】');
    buffer.writeln('名称：${character.name}');
    final data = character.cardData;
    final description = data['description'] as String? ?? '';
    final personality = data['personality'] as String? ?? '';
    final scenario = data['scenario'] as String? ?? '';
    final firstMes = data['first_mes'] as String? ?? '';
    final mesExample = data['mes_example'] as String? ?? '';
    if (description.trim().isNotEmpty) {
      buffer.writeln('描述：\n${truncateText(description)}');
    }
    if (personality.trim().isNotEmpty) {
      buffer.writeln('性格：\n${truncateText(personality)}');
    }
    if (scenario.trim().isNotEmpty) {
      buffer.writeln('场景：\n${truncateText(scenario)}');
    }
    if (firstMes.trim().isNotEmpty) {
      buffer.writeln('开场白：\n${truncateText(firstMes)}');
    }
    if (mesExample.trim().isNotEmpty) {
      buffer.writeln('对话示例：\n${truncateText(mesExample)}');
    }

    if (worldBook != null) {
      buffer.writeln('\n【世界书：${worldBook.name}】');
      final entries = worldBook.entries;
      if (entries.isEmpty) {
        buffer.writeln('（无条目）');
      } else {
        var omitted = 0;
        for (final entry in entries) {
          if (!entry.isEnabled) {
            continue;
          }
          if (buffer.length >= maxPromptBudget) {
            omitted++;
            continue;
          }
          final title = entry.title;
          final keywords = entry.key.take(6).join('、');
          buffer.writeln(
            '- 条目「${title.isEmpty ? entry.id : title}」'
            '${keywords.isEmpty ? '' : '（关键词：$keywords）'}：\n'
            '  ${truncateText(entry.content)}',
          );
        }
        if (omitted > 0) {
          buffer.writeln('（其余 $omitted 个条目因内容过多已省略）');
        }
      }
    }

    buffer.writeln(
      '\n请基于以上材料输出角色介绍与玩法说明（严格按 system 要求的六个小节）。',
    );
    return buffer.toString();
  }

  /// 提示词总预算（字符）：超出后跳过剩余世界书条目，防止上下文溢出。
  static const int maxPromptBudget = 60000;

  /// 截断过长的文本，避免超出模型上下文。
  static String truncateText(String text, {int limit = 4000}) {
    if (text.length <= limit) {
      return text;
    }
    return '${text.substring(0, limit)}\n…（内容过长已截断）';
  }
}
