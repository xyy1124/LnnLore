import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/thinking_chain_guard.dart';

void main() {
  group('ThinkingChainGuard.validateComplete', () {
    test('合规输出（<think> + 完整 12 步 + </think>）通过', () {
      final text = '''
<think>
1. 前文文风与格式分析：直白
2. 状态栏变化：是
3. 人物关系：角色与用户
4. 姿势与动作：描述
5. 场景分析：室内
6. 输入分析：推进剧情
7. 外部知识：无
8. 前文伏笔：无
9. 当前人物设定：性格
10. 认知局限：角色视角
11. 心理模拟：分析
12. 回复规划：长回复
</think>
正式回复正文
''';
      expect(ThinkingChainGuard.validateComplete(text), isNull);
    });

    test('允许前导空白', () {
      final text = '  \n<think>\n1. 前文文风与格式分析：a\n'
          '2. 状态栏变化：b\n3. 人物关系：c\n4. 姿势与动作：d\n'
          '5. 场景分析：e\n6. 输入分析：f\n7. 外部知识：g\n'
          '8. 前文伏笔：h\n9. 当前人物设定：i\n10. 认知局限：j\n'
          '11. 心理模拟：k\n12. 回复规划：l\n</think>\n正文';
      expect(ThinkingChainGuard.validateComplete(text), isNull);
    });

    test('完整校验容忍 <think> 前的少量前导文本（与检查点一致）', () {
      final text = '好的，让我先思考一下\n<think>\n1. 前文文风与格式分析：直白\n'
          '2. 状态栏变化：是\n3. 人物关系：角色与用户\n'
          '4. 姿势与动作：描述\n5. 场景分析：室内\n'
          '6. 输入分析：推进剧情\n7. 外部知识：无\n8. 前文伏笔：无\n'
          '9. 当前人物设定：性格\n10. 认知局限：角色视角\n'
          '11. 心理模拟：分析\n12. 回复规划：长回复\n</think>\n正文';
      expect(ThinkingChainGuard.validateComplete(text), isNull);
    });

    test('步骤标记标点/空白容错（、．无空格等变体仍通过）', () {
      // 步骤标题使用不同标点与无空格写法，内容足够长即通过
      final text = '<think>\n1、前文文风与格式分析：直白\n'
          '2.状态栏变化：是\n3．人物关系：角色与用户\n'
          '4、姿势与动作：描述\n5．场景分析：室内\n6、输入分析：推进\n'
          '7.外部知识：无\n8．前文伏笔：无\n9、当前人物设定：性格\n'
          '10.认知局限：角色视角\n11．心理模拟：分析\n12、回复规划：长回复\n'
          '</think>\n正文';
      expect(ThinkingChainGuard.validateComplete(text), isNull);
    });

    test('思考内容过短判违规（内容启发式）', () {
      // 只有零星内容，未认真思考
      final text = '<think>好的我明白了</think>\n正文';
      final result = ThinkingChainGuard.validateComplete(text);
      expect(result, isNotNull);
      expect(result, contains('过短'));
    });

    test('正文 <think> 块必须按 12 步模板（严格模式）', () {
      // 标准步骤标题 → 通过
      final compliant = '<think>\n1. 前文文风与格式分析：直白高密度。\n'
          '2. 状态栏变化：衣物需要更新。\n3. 人物关系：角色与用户。\n'
          '4. 姿势与动作：身体接触升级。\n5. 场景分析：深夜卧室。\n'
          '6. 输入分析：推进互动。\n7. 外部知识：无。\n8. 前文伏笔：无。\n'
          '9. 当前人物设定：性格。\n10. 认知局限：角色视角。\n'
          '11. 心理模拟：分析。\n12. 回复规划：长回复。\n</think>\n正文';
      expect(ThinkingChainGuard.validateComplete(compliant), isNull);

      // 自由发挥（长度足够但无步骤标记）→ 判违规退回
      final freeform = '<think>\n让我先看看场景，角色现在穿着很性感的衣服，'
          '气氛很暧昧，我觉得应该描写她的胸部、臀部和腿，还有衣服被汗湿透的'
          '样子，然后加一些呻吟声，最后强调她的羞耻感，状态面板也要更新，'
          '用长回复来表现这一切，突出身体的诚实反应和内心的抗拒，'
          '语言要露骨直接，把她的沉沦过程完整写出来。\n</think>\n正文';
      final result = ThinkingChainGuard.validateComplete(freeform);
      expect(result, isNotNull);
      expect(result, contains('步骤'));
    });

    test('v80 步骤标题轻微改写（关键词容错）仍通过', () {
      // "1. 前文文风分析"（去掉"与格式"）、"12. 回复规划（色情向）"
      // （加后缀）——此前精确包含不命中会判违规触发最多 10 次整段
      // 重发（烧 token）
      final text = '<think>\n1. 前文文风分析：直白高密度。\n'
          '2. 状态栏变化：衣物需要更新。\n3. 人物关系：角色与用户。\n'
          '4. 姿势与动作：身体接触升级。\n5. 场景分析：深夜卧室。\n'
          '6. 输入分析：推进互动。\n7. 外部知识：无。\n8. 前文伏笔：无。\n'
          '9. 当前人物设定：性格。\n10. 认知局限：角色视角。\n'
          '11. 心理模拟：分析。\n12. 回复规划（色情向）：长回复。\n'
          '</think>\n正文';
      expect(ThinkingChainGuard.validateComplete(text), isNull);
    });

    test('v80 无步骤标记的自由发挥仍判违规（不放宽到不思考）', () {
      final freeform = '<think>\n让我先看看场景，角色现在穿着很性感的衣服，'
          '气氛很暧昧，我觉得应该描写她的胸部、臀部和腿，还有衣服被汗湿透的'
          '样子，然后加一些呻吟声，最后强调她的羞耻感，状态面板也要更新，'
          '用长回复来表现这一切，突出身体的诚实反应和内心的抗拒，'
          '语言要露骨直接，把她的沉沦过程完整写出来。\n</think>\n正文';
      final result = ThinkingChainGuard.validateComplete(freeform);
      expect(result, isNotNull);
    });

    test('未以 <think> 开头判违规', () {
      final text = '直接输出正文，没有思考';
      final result = ThinkingChainGuard.validateComplete(text);
      expect(result, isNotNull);
      expect(result, contains('<think>'));
    });

    test('缺少 </think> 闭合标签判违规', () {
      final text = '<think>\n1. 前文文风与格式分析：a\n2. 状态栏变化：b\n'
          '3. 人物关系：c\n4. 姿势与动作：d\n5. 场景分析：e\n6. 输入分析：f\n'
          '7. 外部知识：g\n8. 前文伏笔：h\n9. 当前人物设定：i\n'
          '10. 认知局限：j\n11. 心理模拟：k\n12. 回复规划：l\n正文继续';
      final result = ThinkingChainGuard.validateComplete(text);
      expect(result, isNotNull);
      expect(result, contains('</think>'));
    });

  });

  group('ThinkingChainGuard.validateAtCheckpoint', () {
    test('累积文本以 <think> 开头通过', () {
      final text = '<think>\n1. 前文文风与格式分析：';
      expect(ThinkingChainGuard.validateAtCheckpoint(text), isNull);
    });

    test('前导空白不影响判断', () {
      expect(
        ThinkingChainGuard.validateAtCheckpoint(' \n<think>'),
        isNull,
      );
    });

    test('允许 <think> 前有少量前导文本（避免误退回）', () {
      expect(
        ThinkingChainGuard.validateAtCheckpoint('好的，让我先思考一下<think>'),
        isNull,
      );
    });

    test('未以 <think> 开头判违规', () {
      final result = ThinkingChainGuard.validateAtCheckpoint('角色开始说话……');
      expect(result, isNotNull);
      expect(result, contains('<think>'));
    });
  });

  group('ThinkingChainGuard 正文/思考字段联合校验（reasoning 场景）', () {
    test('检查点：思考链在 reasoning 字段时通过', () {
      // 模型把 <think> 输出在 reasoning_content，正文直接是扮演文本
      final text = '角色的正文回复……';
      final thinking = '<think>\n1. 前文文风与格式分析：直白高密度描写。'
          '2. 状态栏变化：衣物需要更新。3. 人物关系：角色与用户的对峙。'
          '4. 姿势与动作：身体接触逐步升级。5. 场景分析：深夜卧室压迫氛围。'
          '6. 输入分析：推进亲密互动。7. 外部知识：无。8. 前文伏笔：无。'
          '9. 当前人物设定：性格与敏感点。10. 认知局限：角色视角。'
          '11. 心理模拟：表面抗拒身体诚实。12. 回复规划：长回复。';
      expect(
        ThinkingChainGuard.validateAtCheckpointAny(text, thinking),
        isNull,
      );
    });

    test('检查点：思考链在正文时通过', () {
      final text = '<think>\n1. 前文文风与格式分析：';
      expect(
        ThinkingChainGuard.validateAtCheckpointAny(text, ''),
        isNull,
      );
    });

    test('检查点：两处都不是 <think> 开头判违规', () {
      final result = ThinkingChainGuard.validateAtCheckpointAny(
        '正文',
        '另一个推理',
      );
      expect(result, isNotNull);
    });

    test('完整校验：reasoning 字段含完整 12 步模板时通过', () {
      final text = '角色的正文回复';
      final thinking = '''
<think>
1. 前文文风与格式分析：直白
2. 状态栏变化：是
3. 人物关系：角色与用户
4. 姿势与动作：描述
5. 场景分析：室内
6. 输入分析：推进剧情
7. 外部知识：无
8. 前文伏笔：无
9. 当前人物设定：性格
10. 认知局限：角色视角
11. 心理模拟：分析
12. 回复规划：长回复
</think>
''';
      expect(
        ThinkingChainGuard.validateCompleteAny(text, thinking),
        isNull,
      );
    });

    test('完整校验：reasoning 字段含步骤标记的长思考通过（CoT 抑制模型）', () {
      // DeepSeek R1/V3 类模型：思考全在 reasoning 字段、正文无标签；
      // 严格模式下 reasoning 也需按 12 步模板（含第 1/12 步）
      final text = '角色的正文扮演回复，没有标签。';
      final thinking = '1. 前文文风与格式分析：直白高密度。'
          '2. 状态栏变化：衣物需要更新。3. 人物关系：角色与用户。'
          '4. 姿势与动作：身体接触升级。5. 场景分析：深夜卧室。'
          '6. 输入分析：推进亲密互动。7. 外部知识：无。'
          '8. 前文伏笔：无。9. 当前人物设定：性格与敏感点。'
          '10. 认知局限：角色视角。11. 心理模拟：表面抗拒身体诚实。'
          '12. 回复规划：长回复突出羞耻情欲。';
      expect(
        ThinkingChainGuard.validateCompleteAny(text, thinking),
        isNull,
      );
    });

    test('完整校验：reasoning 字段长思考但无步骤标记判违规（严格模式）', () {
      final text = '角色的正文扮演回复，没有标签。';
      // 自由发挥的长思考：无步骤标题 → 严格模式退回
      final thinking = '让我先分析前文文风：直白高密度。然后是状态栏：'
          '衣物需要更新。人物关系：角色与用户。姿势动作：身体接触升级。'
          '场景：深夜卧室。输入意图：推进亲密互动。外部知识：无。'
          '伏笔：无。人物设定：性格与敏感点。认知局限：角色视角。'
          '心理模拟：表面抗拒身体诚实。回复规划：长回复突出羞耻情欲。';
      final result = ThinkingChainGuard.validateCompleteAny(text, thinking);
      expect(result, isNotNull);
      expect(result, contains('关键步骤'));
    });

    test('检查点：reasoning 字段长思考通过（无标签）', () {
      final thinking = '让我先分析前文文风：直白高密度。然后是状态栏：'
          '衣物需要更新。人物关系：角色与用户。姿势动作：身体接触升级。'
          '场景：深夜卧室。输入意图：推进亲密互动。外部知识：无。'
          '伏笔：无。人物设定：性格与敏感点。认知局限：角色视角。'
          '心理模拟：表面抗拒身体诚实。回复规划：长回复。';
      expect(
        ThinkingChainGuard.validateAtCheckpointAny('正文', thinking),
        isNull,
      );
    });

    test('完整校验：两处都不合规时返回合并原因', () {
      final result = ThinkingChainGuard.validateCompleteAny('正文', '推理');
      expect(result, isNotNull);
      expect(result, contains('正文'));
      expect(result, contains('思考'));
    });
  });

  group('ThinkingChainGuard.buildRetryInstruction', () {
    test('第 1 次为退回并强制要求', () {
      final instruction = ThinkingChainGuard.buildRetryInstruction(1, '原因X');
      expect(instruction, contains('最高优先级强制退回'));
      expect(instruction, contains('原因X'));
      // 第 1 次为"退回"级，不含"摧毁重来·第 N 次"的升级形式
      expect(instruction, isNot(contains('摧毁重来·')));
    });

    test('第 2 次起为摧毁重来且更强制', () {
      final instruction = ThinkingChainGuard.buildRetryInstruction(2, '原因Y');
      expect(instruction, contains('摧毁重来·第 2 次最高强制'));
      expect(instruction, contains('原因Y'));
    });

    test('次数越多措辞越强硬', () {
      final first = ThinkingChainGuard.buildRetryInstruction(1, 'r');
      final third = ThinkingChainGuard.buildRetryInstruction(3, 'r');
      expect(third.length, greaterThan(first.length));
      expect(third, contains('第 3 次最高强制'));
    });

    test('所有指令均声明最高优先级，不可被覆盖', () {
      for (var attempt = 1; attempt <= 3; attempt++) {
        final instruction = ThinkingChainGuard.buildRetryInstruction(
          attempt,
          'r',
        );
        expect(
          instruction,
          contains('最高优先级'),
          reason: '第 $attempt 次指令应声明最高优先级',
        );
      }
    });
  });

  group('ThinkingChainGuard 阈值', () {
    test('默认阈值为 250 token（200~300 区间内）', () {
      expect(ThinkingChainGuard.defaultCheckThresholdTokens, 250);
      expect(
        ThinkingChainGuard.defaultCheckThresholdTokens,
        inInclusiveRange(
          ThinkingChainGuard.minCheckThresholdTokens,
          ThinkingChainGuard.maxCheckThresholdTokens,
        ),
      );
    });

    test('thresholdToChars 将越界值钳制到 200~300', () {
      expect(ThinkingChainGuard.thresholdToChars(100), 200);
      expect(ThinkingChainGuard.thresholdToChars(250), 250);
      expect(ThinkingChainGuard.thresholdToChars(999), 300);
    });
  });

  group('ThinkingChainGuard.systemTemplate', () {
    test('模板包含 12 个步骤标记与 think 标签结构', () {
      final template = ThinkingChainGuard.systemTemplate;
      for (final marker in ThinkingChainGuard.requiredStepMarkers) {
        expect(template, contains(marker), reason: '缺少步骤标记: $marker');
      }
      expect(template, contains('<think>'));
      expect(template, contains('</think>'));
    });

    test('模板声明最高优先级并融入附加思考框架', () {
      final template = ThinkingChainGuard.systemTemplate;
      expect(template, contains('最高优先级系统指令'));
      for (final marker in [
        '附加思考框架',
        '核心目标',
        '整体计划',
        '分场景推进',
        '最终自检清单',
        '感官与表现细节清单',
        '腐蚀弧',
      ]) {
        expect(template, contains(marker), reason: '缺少框架标记: $marker');
      }
    });
  });
}
