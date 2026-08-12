import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/data/app_settings.dart';
import 'package:pocket_inn/models/preset.dart';
import 'package:pocket_inn/services/chat_service.dart';
import 'package:pocket_inn/services/thinking_chain_guard.dart';

void main() {
  final preset = Preset(
    id: 'test',
    name: '测试预设',
    updatedAt: DateTime.now(),
    extra: {'enable_reasoning': true, 'reasoning_effort': 'medium'},
  );

  group('DeepSeekThinkingMode', () {
    test('默认档位为 max（用户最常用）', () {
      expect(
        const AppSettings().deepSeekThinkingMode,
        DeepSeekThinkingMode.max,
      );
      expect(const AppSettings().deepSeekThinkingMode.reasoningEffort, 'max');
    });

    test('reasoningEffort 取值符合 DeepSeek 官方枚举', () {
      expect(DeepSeekThinkingMode.disabled.reasoningEffort, isNull);
      expect(DeepSeekThinkingMode.high.reasoningEffort, 'high');
      expect(DeepSeekThinkingMode.max.reasoningEffort, 'max');
    });
  });

  group('思维链模板第三方视角约束', () {
    test('systemTemplate 明确禁止角色第一人称内部分析', () {
      final template = ThinkingChainGuard.systemTemplate;
      expect(template, contains('第三方导演/编剧/审稿人视角'));
      expect(template, contains('严禁代入任何角色的第一人称'));
    });
  });

  group('validateCompleteLenient（原生 thinking 宽松校验）', () {
    String validText() {
      final steps = ThinkingChainGuard.requiredStepMarkers
          .map((marker) => '$marker：内容足够长，满足步骤要求。')
          .join('\n');
      return '<think>\n$steps\n</think>\n正式正文内容。';
    }

    test('思考非空且够长 + 正文合规即通过（无需 12 步标题）', () {
      final thinking = '这段思考足够长但完全不走 12 步格式。' * 10;
      expect(
        ThinkingChainGuard.validateCompleteLenient(validText(), thinking),
        isNull,
      );
    });

    test('思考为空且正文不合规 → 失败', () {
      expect(
        ThinkingChainGuard.validateCompleteLenient(
          '没有标签的正文内容',
          '',
        ),
        isNotNull,
      );
    });

    test('原生模式正文无 <think> 是常态：正文不合规但思考够长 → 放行', () {
      final thinking = '思考内容足够长但不走 12 步格式。' * 10;
      expect(
        ThinkingChainGuard.validateCompleteLenient('没有标签的正文内容', thinking),
        isNull,
      );
    });

    test('正文为空仍失败（不放过空白回复）', () {
      final thinking = '思考内容足够长但不走 12 步格式。' * 10;
      expect(
        ThinkingChainGuard.validateCompleteLenient('', thinking),
        isNotNull,
      );
    });

    test('validateAtCheckpointLenient：思考已开始即通过', () {
      expect(ThinkingChainGuard.validateAtCheckpointLenient('正在思考中'), isNull);
      expect(ThinkingChainGuard.validateAtCheckpointLenient(''), isNotNull);
    });
  });

  group('buildCompletionDefaults 分流', () {
    test('DeepSeek 端点 + max：thinking enabled + reasoning_effort max，不传 temperature', () {
      final defaults = ChatService.instance.buildCompletionDefaults(
        preset,
        useStreaming: true,
        isDeepSeek: true,
        deepSeekThinkingMode: DeepSeekThinkingMode.max,
      );
      expect(defaults['stream'], isTrue);
      expect((defaults['thinking'] as Map)['type'], 'enabled');
      expect(defaults['reasoning_effort'], 'max');
      expect(defaults.containsKey('temperature'), isFalse);
    });

    test('DeepSeek 端点 + high：reasoning_effort high', () {
      final defaults = ChatService.instance.buildCompletionDefaults(
        preset,
        useStreaming: false,
        isDeepSeek: true,
        deepSeekThinkingMode: DeepSeekThinkingMode.high,
      );
      expect(defaults['reasoning_effort'], 'high');
      expect((defaults['thinking'] as Map)['type'], 'enabled');
    });

    test('DeepSeek 端点 + disabled：thinking disabled，无 reasoning_effort', () {
      final defaults = ChatService.instance.buildCompletionDefaults(
        preset,
        useStreaming: true,
        isDeepSeek: true,
        deepSeekThinkingMode: DeepSeekThinkingMode.disabled,
      );
      expect((defaults['thinking'] as Map)['type'], 'disabled');
      expect(defaults.containsKey('reasoning_effort'), isFalse);
    });

    test('非 DeepSeek 端点：enable_reasoning 兼容路径（extra 未指定时默认 high，不再 medium）', () {
      final defaults = ChatService.instance.buildCompletionDefaults(
        preset.copyWith(extra: {'enable_reasoning': true}),
        useStreaming: true,
        isDeepSeek: false,
      );
      expect(defaults.containsKey('thinking'), isFalse);
      expect(defaults['reasoning_effort'], 'high');
    });

    // v87 根因回归：裁判请求（小 max_tokens）必须禁用原生 thinking，
    // 否则 max 级思考吃光 512-1024 token 预算 → 空回复 → 状态不更新
    test('裁判场景（forceDeepSeekThinkingMode=disabled）强制 thinking disabled', () {
      final defaults = ChatService.instance.buildCompletionDefaults(
        preset,
        useStreaming: false,
        isDeepSeek: true,
        deepSeekThinkingMode: DeepSeekThinkingMode.max,
      );
      // 模拟裁判调用：即使全局设置是 max，裁判也用 disabled 覆盖
      final judgeDefaults = ChatService.instance.buildCompletionDefaults(
        preset,
        useStreaming: false,
        isDeepSeek: true,
        deepSeekThinkingMode: DeepSeekThinkingMode.disabled,
      );
      expect((defaults['thinking'] as Map)['type'], 'enabled');
      expect((judgeDefaults['thinking'] as Map)['type'], 'disabled');
      expect(judgeDefaults.containsKey('reasoning_effort'), isFalse);
    });
  });
}
