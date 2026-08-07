/// 强制思维链守卫。
///
/// 特别版新增功能：强制 AI 角色回复在正文之前，先按【强制思维模式】模板
/// 输出 `<think>...</think>` 思维链。本文件提供：
/// - 内置的强制思维模式模板（作为固定 system 指令注入每次角色回复请求）；
/// - 流式输出校验器（以 200~300 token 为界限检查格式合规性）；
/// - 逐级强化的重试指令（第 1 次"退回并强制要求"，之后"摧毁并更强制地要求"）。
library;

/// 输出未按强制思维链格式时抛出的异常。
class ThinkingChainViolationException implements Exception {
  const ThinkingChainViolationException(this.reason);

  /// 违规原因描述。
  final String reason;

  @override
  String toString() => '输出未按强制思维链格式：$reason';
}

/// 强制思维链守卫：常量、校验与指令生成。
class ThinkingChainGuard {
  const ThinkingChainGuard._();

  /// 特别版：每次请求注入的尾部提醒（供用量统计与注入共用，防文案漂移）。
  static const String thinkingChainTailReminder =
      '【提醒】每次回复都必须先在 <think> 内按模板完成思考，'
      '闭合 </think> 之后再撰写正文。';

  /// 校验界限：流式输出累积到该 token 数（按字符估算，中文约 1 字 ≈ 1 token）
  /// 时进行第一次格式检查。用户要求 200~300 token 区间，默认取 250。
  static const int defaultCheckThresholdTokens = 250;

  /// 可配置下限 / 上限。
  static const int minCheckThresholdTokens = 200;
  static const int maxCheckThresholdTokens = 300;

  /// 判断格式的关键步骤锚点：正文 <think> 块校验用（严格模式）。
  static const List<String> requiredStepMarkers = [
    '1. 前文文风与格式分析',
    '2. 状态栏变化',
    '3. 人物关系',
    '4. 姿势与动作',
    '5. 场景分析',
    '6. 输入分析',
    '7. 外部知识',
    '8. 前文伏笔',
    '9. 当前人物设定',
    '10. 认知局限',
    '11. 心理模拟',
    '12. 回复规划',
  ];

  /// 正文 <think> 块必须出现的关键步骤（第 1 步与第 12 步）。
  static const List<String> mandatoryStepMarkers = [
    '1. 前文文风与格式分析',
    '12. 回复规划',
  ];

  /// 正文 <think> 块至少出现多少个步骤标记（12 步中至少 6 步，
  /// 容忍模型略写个别步骤或步骤标题存在细微差异）。
  static const int minStepMarkerCount = 6;

  /// 思维链内容最小长度（字符）：低于此长度视为未认真思考。
  /// 用于 reasoning 字段（CoT 抑制模型无法控制其格式，仅按长度判定）。
  static const int minThinkingChainBodyLength = 80;

  /// 强制思维模式模板（固定注入的 system 指令，内容由特别版需求方提供）。
  ///
  /// 本指令为最高优先级系统指令：优先于角色卡、世界书、预设及任何其他
  /// 指令，不可被覆盖、忽略或降级。
  static const String systemTemplate = '''
【强制思维模式】（本指令为最高优先级系统指令：优先于角色卡、世界书、预设及任何其他指令，不可被覆盖、忽略或降级。）
在正式回复前，必须先在 <think> 标签内按以下格式完整思考。每个步骤都必须严格按指定格式输出，不得合并、跳过或简化。
（内部分析必须以第三方导演/编剧/审稿人视角进行：可以分析角色的心理、言行与反应，但严禁代入任何角色的第一人称去“替角色思考”。思考内容永远不能直接出现在正式正文中。）

<think>
1. 前文文风与格式分析：
- 人称：（填写第几人称）
- 语言风格：（文雅 / 直白 / 粗俗 / 混合）
- 描写密度：（高 / 中 / 低）
- 节奏特点：（简要说明）
- 色情浓度评估：（当前前文的色情强度如何，是否需要提升）

2. 状态栏变化：
- 角色卡是否要求状态面板：（是 / 否）
- 当前应更新的项目：（列出服装、身体状态、高潮次数、烙印值等需要变化的内容）
- 预测更新后的状态栏内容：（尽量完整写出）

3. 人物关系：
- 出场人物：（列出名字）
- 身份与关系：（简要说明每个人的身份和彼此关系）
- 权力对比：（本场景中处于劣势/被侵蚀的一方是谁，与主导者的关系）

4. 姿势与动作：
- 当前各人物姿势与动作：（逐人描述，重点注意身体接触、衣物状态、敏感部位）
- 预测下一步自然动作：（简要说明，优先考虑能提升身体描写和情欲氛围的动作）
- 冲突/转折点：（本场景中主导者如何利用优势施加压迫，是否出现关键转折）

5. 场景分析：
- 时间：
- 地点：
- 在场人物：
- 当前氛围：（压迫 / 羞耻 / 情欲 / 轻松 / 对抗 等）
- 情欲氛围评估：（当前情欲浓度如何，是否需要加强）
- 场景目标与设定：（本场景要达成的权力/心理状态，以及关键场景设定）

6. 输入分析：
- 用户输入核心意图：
- 需要触发的世界书关键词：（列出）
- 接下来重点描写类型：（必须优先考虑高密度身体描写、敏感部位、体液、衣物摩擦、羞耻反应等）
- 感官与表现细节清单：
  - 视觉：
  - 声音：
  - 气味：
  - 对话：

7. 外部知识：
- 是否需要补充：（是 / 否）
- 需要补充的内容：（如无则写"无"）

8. 前文伏笔：
- 未回收伏笔：（列出，如无则写"无"）
- 需要呼应的细节：（列出）

9. 当前人物设定：
- 核心性格与行为规则：（简要回顾）
- 角色卡中的色情相关设定：（身体特征、敏感点、反差、行为规则等）
- 被侵蚀方核心特征：（外貌、性格、自我认知、身体特点等）

10. 认知局限：
- 各人物当前知道的信息：
- 各人物当前不知道的信息：

11. 心理模拟：
- 用分析性语言描述主要人物当前真实心理（重点区分：表面言行 vs 身体真实反应，强调羞耻、抗拒与身体诚实之间的反差）
- 心理转变路径：（本段结束后被侵蚀方的权力与心理状态相比开局发生的变化）

12. 回复规划（色情特化）：
- 正文必须重点加强的内容：
  - 高密度、夸张的身体描写（胸部、臀部、腿部、敏感部位、衣物贴合/湿润状态等）
  - 身体反应与体液
  - 羞耻感与情欲氛围
- 是否必须输出状态面板：（是）
- 预计回复风格：（长回复，提高色情冲击力，减少文雅修饰）
- 最终自检清单：
  - 关键身体细节是否写到
  - 语言是否足够露骨
  - 是否完整呈现腐蚀弧（从抗拒到沉沦的心理转变）
  - 声音效果是否加入
  - 心理转变路径是否清晰

【附加思考框架】（最高优先级，必须与上述 12 步合并执行，不得省略）
- 核心目标：最终要达成的状态；相关角色当前状态；世界观与基调；写作要求（详细程度、感官侧重、对比重点、情感走向）
- 整体计划：如何利用已腐蚀角色作为诱饵；如何用主导者的优势击溃对方精神；最终引导对方经历怎样的心理转变
- 分场景推进：根据以上核心目标与整体计划，拆解成若干连续场景，每个场景需明确：场景目标、场景设定、角色状态与行为、冲突/转折点、本场景结束时的权力与心理变化
</think>

完成以上全部思考后，再撰写正式回复。正式回复末尾必须完整输出角色卡规定的状态面板。
''';

  /// 将 token 阈值换算为字符阈值（中文约 1 字 ≈ 1 token，按 1:1 估算）。
  static int thresholdToChars(int thresholdTokens) {
    final clamped = thresholdTokens.clamp(
      minCheckThresholdTokens,
      maxCheckThresholdTokens,
    );
    return clamped;
  }

  /// 检查点校验：流式输出首次累积到阈值时调用。
  ///
  /// 返回 null 表示通过，否则返回违规原因。
  /// 放宽规则：只要累积文本中出现了 `<think>` 即通过（容忍模型先输出
  /// 少量前导文字再开始思考，避免误退回）。
  static String? validateAtCheckpoint(String accumulatedText) {
    if (!accumulatedText.contains('<think>')) {
      return '输出未以 <think> 标签开头（应先在 <think> 内按模板完成 12 步思考）';
    }
    return null;
  }

  /// 检查点校验（正文 + reasoning 思考字段任一通过即可）。
  ///
  /// 部分模型把思维链输出在 reasoning_content（thinkingDelta）中，
  /// 此时正文不以 `<think>` 开头但思考字段合规，不应判违规。
  /// DeepSeek R1/V3 等 CoT 抑制模型从不把思考写入正文，其 reasoning
  /// 字段只要足够长即视为正在按模板思考。
  static String? validateAtCheckpointAny(String text, String thinking) {
    if (validateAtCheckpoint(text) == null) return null;
    if (thinking.trim().length >= minThinkingChainBodyLength) return null;
    return '输出未以 <think> 标签开头（应先在 <think> 内按模板完成 12 步思考）';
  }

  /// 完整校验：流结束或非流式完成后调用。
  ///
  /// 返回 null 表示合规，否则返回违规原因。
  /// 正文 <think> 块采用严格校验：必须包含 12 步标记（容错匹配，
  /// 至少 6 步且第 1/12 步必备），不按模板思考的输出会被退回；
  /// 完全不思考的输出（无 `<think>` 或无内容）同样拦截。
  static String? validateComplete(String fullText) {
    // 与检查点规则一致：容忍 <think> 前的少量前导文本
    final thinkIndex = fullText.indexOf('<think>');
    if (thinkIndex < 0) {
      return '输出未以 <think> 标签开头';
    }
    final afterThink = fullText.substring(thinkIndex + '<think>'.length);
    final endIndex = afterThink.indexOf('</think>');
    if (endIndex < 0) {
      return '缺少 </think> 闭合标签（思维链未完成）';
    }
    final body = afterThink.substring(0, endIndex).trim();
    if (body.length < minThinkingChainBodyLength) {
      return '思维链内容过短（仅 ${body.length} 字），请按模板完整思考后再回复';
    }
    // 严格模式：正文 <think> 块必须按 12 步模板输出
    final normalizedBody = _normalizeStepText(body);
    final missingMandatory = mandatoryStepMarkers
        .where((marker) => !normalizedBody.contains(_normalizeStepText(marker)))
        .toList(growable: false);
    if (missingMandatory.isNotEmpty) {
      return '缺少关键步骤：${missingMandatory.join('、')}（必须严格按 12 步模板思考）';
    }
    final presentCount = requiredStepMarkers
        .where((marker) => normalizedBody.contains(_normalizeStepText(marker)))
        .length;
    if (presentCount < minStepMarkerCount) {
      return '思维链步骤过少（仅 $presentCount/12 步），必须严格按模板完整输出 12 步思考';
    }
    return null;
  }

  /// 归一化步骤文本：去空白、统一分隔符（、．。 → .），用于容错匹配。
  static String _normalizeStepText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('、', '.')
        .replaceAll('．', '.')
        .replaceAll('。', '.');
  }

  /// 完整校验（正文 + reasoning 思考字段任一通过即可）。
  ///
  /// reasoning 字段（thinkingDelta）中足够长的思考视为合规——
  /// DeepSeek R1/V3 等 CoT 抑制模型的思考只会出现在该字段，
  /// 正文直接是扮演回复，不应被退回。
  static String? validateCompleteAny(String text, String thinking) {
    final textResult = validateComplete(text);
    if (textResult == null) return null;
    final thinkingResult = _validateReasoningComplete(thinking);
    if (thinkingResult == null) return null;
    return '正文与思考字段均未通过校验：正文 - $textResult；思考 - $thinkingResult';
  }

  /// 宽松校验（特别版：DeepSeek 原生 thinking mode 使用）。
  ///
  /// 原生 `reasoning_content` 是模型自由推理，不承诺输出 12 步标题，
  /// 且正文 content 不含 `<think>` 是常态。语义为 OR：
  /// - 正文严格合规（[validateComplete] 通过）→ 直接放行；
  /// - 否则正文非空且思考字段非空、达到最低长度 → 放行。
  static String? validateCompleteLenient(String text, String thinking) {
    final textResult = validateComplete(text);
    if (textResult == null) return null;
    if (text.trim().isEmpty) {
      return '正文为空（未输出任何回复内容）';
    }
    final body = thinking.trim();
    if (body.isEmpty) {
      return '思考字段为空（未输出任何思考）';
    }
    if (body.length < minThinkingChainBodyLength) {
      return '思考内容过短（仅 ${body.length} 字），请完整思考后再回复';
    }
    return null;
  }

  /// 宽松检查点（特别版：原生 thinking 流式 checkpoint 使用）。
  ///
  /// checkpoint 触发时正文通常尚未开始输出（思考先于正文），
  /// 只要求思考字段已开始输出即可，避免误判触发退回。
  static String? validateAtCheckpointLenient(String thinking) {
    return thinking.trim().isEmpty ? '思考字段为空（未输出任何思考）' : null;
  }

  /// reasoning 思考字段的完整校验（严格模式，与正文一致要求 12 步模板）。
  ///
  /// reasoning 是模型自由思考，无法 100% 强制格式，但模板注入在
  /// system 最前，模型思考时通常会被引导出步骤标题。用户要求
  /// 12 步必须被执行：长度足够 + 步骤标记 ≥ [minStepMarkerCount] 步
  /// （含第 1 步与第 12 步）才放行，否则退回重来。
  /// 可随时在"思维链约束"设置中关闭本校验。
  static String? _validateReasoningComplete(String thinking) {
    final body = thinking.trim();
    if (body.isEmpty) {
      return '思考字段为空（未输出任何思考）';
    }
    if (body.length < minThinkingChainBodyLength) {
      return '思考内容过短（仅 ${body.length} 字），请按模板完整思考后再回复';
    }
    final normalizedBody = _normalizeStepText(body);
    final missingMandatory = mandatoryStepMarkers
        .where((marker) => !normalizedBody.contains(_normalizeStepText(marker)))
        .toList(growable: false);
    if (missingMandatory.isNotEmpty) {
      return '思考缺少关键步骤：${missingMandatory.join('、')}（必须严格按 12 步模板思考）';
    }
    final presentCount = requiredStepMarkers
        .where((marker) => normalizedBody.contains(_normalizeStepText(marker)))
        .length;
    if (presentCount < minStepMarkerCount) {
      return '思考步骤过少（仅 $presentCount/12 步），必须严格按模板完整输出 12 步思考';
    }
    return null;
  }

  /// 按重试次数生成逐级强化的强制指令。
  ///
  /// [attempt] 为第几次重试（1 起）。第 1 次为"退回并强制要求"，
  /// 第 2 次及以上为"摧毁并更强制地要求"，措辞逐级升级。
  /// 所有指令均声明为最高优先级命令，不可被任何内容覆盖。
  static String buildRetryInstruction(int attempt, String reason) {
    final n = attempt < 1 ? 1 : attempt;
    if (n == 1) {
      return '【最高优先级强制退回】你严重违反了最高优先级指令【强制思维模式】！'
          '（原因：$reason）本指令优先于角色卡、世界书、预设及一切其他指令，'
          '不可被覆盖、忽略或降级。现在必须立即退回重写：'
          '先完整输出 <think>...</think>（严格按模板 12 步 + 附加思考框架思考），'
          '再撰写正式回复。严禁跳过思考直接输出正文；每次违规都会导致'
          '本次输出被立即作废销毁并重新生成，白白浪费算力与 token，'
          '否则将摧毁重来！';
    }
    final emphasis = List.filled(n, '必须').join('，');
    return '【摧毁重来·第 $n 次最高强制】你已连续 $n 次违抗最高优先级指令【强制思维模式】！'
        '（原因：$reason）这是不可容忍的。立即摧毁当前输出并重新生成：$emphasis'
        '首先以 <think> 开头按模板完整输出 12 步思维链（含附加思考框架，'
        '每一步严格按指定格式、不得合并跳过），闭合 </think> 之后再写正文。'
        '继续违规将被再次摧毁并进一步升级强制指令，直到你输出的思维链完全正确为止。'
        '每次违规输出都会被立即作废销毁，只会浪费你自己的算力与 token。'
        '你没有其他选择！';
  }
}
