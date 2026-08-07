import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/preset.dart';
import 'package:pocket_inn/models/prompt_assembly.dart';
import 'package:pocket_inn/services/chat_variable_service.dart';
import 'package:pocket_inn/services/prompt_assembler.dart';

void main() {
  group('ChatVariableService setvar 解析/剥离', () {
    test('parseSetVarCalls 提取单组', () {
      final calls = ChatVariableService.parseSetVarCalls(
        '状态更新 {{setvar::hp::50}} 完毕',
      );
      expect(calls, [(('hp', '50'))]);
    });

    test('parseSetVarCalls 提取多组（含特殊值）', () {
      final calls = ChatVariableService.parseSetVarCalls(
        '{{setvar::hp::50}}{{setvar::mood::兴奋}}'
        '{{setvar::weapon::赤焰剑}}',
      );
      expect(calls, [
        (('hp', '50')),
        (('mood', '兴奋')),
        (('weapon', '赤焰剑')),
      ]);
    });

    test('parseSetVarCalls 忽略非 setvar 宏', () {
      final calls = ChatVariableService.parseSetVarCalls(
        '{{char}} {{getvar::hp}} 说 {{setvar::x::1}}',
      );
      expect(calls, [(('x', '1'))]);
    });

    test('stripSetVarCalls 剥离所有 setvar 调用', () {
      expect(
        ChatVariableService.stripSetVarCalls(
          '{{setvar::hp::50}} 我没事',
        ),
        ' 我没事',
      );
    });

    test('stripSetVarCalls 不影响普通文本与 getvar', () {
      final out = ChatVariableService.stripSetVarCalls(
        '面板 {{getvar::hp}}/{{getvar::maxhp}} {{setvar::hp::50}}',
      );
      expect(out, '面板 {{getvar::hp}}/{{getvar::maxhp}} ');
    });
  });

  group('getvar 组装时加载会话变量', () {
    PromptAssemblyContext ctx({
      required Map<String, String> localVariables,
    }) {
      return PromptAssemblyContext(
        characterName: '艾琳',
        characterCardData: {
          'name': '艾琳',
          'description': '状态：HP {{getvar::hp}}/100',
        },
        userName: '玩家',
        userSettingPrompt: '',
        preset: Preset(
          id: 'test',
          name: '测试预设',
          updatedAt: DateTime(2026),
          prompts: const [
            PresetPrompt(
              identifier: 'charDescription',
              name: '描述',
              content: '',
            ),
          ],
        ),
        selectedWorldBooks: const [],
        chatMessages: const [],
        currentInput: '继续',
        localVariables: localVariables,
      );
    }

    test('注入文本中的 {{getvar::k}} 用会话变量替换', () {
      final assembled = PromptAssembler.build(ctx(localVariables: {'hp': '42'}));
      final merged = assembled.messages.map((m) => m.content).join('\n');
      expect(merged, contains('状态：HP 42/100'));
      expect(merged, isNot(contains('{{getvar::hp}}')));
    });

    test('缺变量时 getvar 替换为空（不崩溃）', () {
      final assembled = PromptAssembler.build(ctx(localVariables: const {}));
      final merged = assembled.messages.map((m) => m.content).join('\n');
      expect(merged, contains('状态：HP /100'));
      expect(merged, isNot(contains('{{getvar::hp}}')));
    });
  });

  group('resolveGetVars 显示解析', () {
    test('大小写不敏感：{{GetVar::}}/{{GETVAR::}} 也解析', () {
      const variables = {'hp': '42'};
      expect(
        ChatVariableService.resolveGetVars('状态：{{GetVar::hp}}', variables),
        '状态：42',
      );
      expect(
        ChatVariableService.resolveGetVars('状态：{{GETVAR::hp}}', variables),
        '状态：42',
      );
      expect(
        ChatVariableService.resolveGetVars('状态：{{ getvar :: hp }}', variables),
        '状态：42',
      );
    });

    test('引号 key：{{getvar::"hp"}} / {{getvar::\'hp\'}} 也解析', () {
      const variables = {'hp': '42'};
      expect(
        ChatVariableService.resolveGetVars(
          '状态：{{getvar::"hp"}}',
          variables,
        ),
        '状态：42',
      );
      expect(
        ChatVariableService.resolveGetVars("状态：{{getvar::'hp'}}", variables),
        '状态：42',
      );
    });

    test('hasGetVars 大小写不敏感识别', () {
      expect(ChatVariableService.hasGetVars('{{getvar::hp}}'), isTrue);
      expect(ChatVariableService.hasGetVars('{{GetVar::hp}}'), isTrue);
      expect(ChatVariableService.hasGetVars('{{GETVAR:: hp }}'), isTrue);
      expect(ChatVariableService.hasGetVars('普通文本'), isFalse);
      expect(ChatVariableService.hasGetVars(''), isFalse);
    });

    test('缺变量/无变量表替换为空', () {
      expect(
        ChatVariableService.resolveGetVars('{{getvar::missing}}', const {}),
        '',
      );
      expect(
        ChatVariableService.resolveGetVars('a{{getvar::x}}b', {'y': '1'}),
        'ab',
      );
    });

    test('无 getvar 文本原样返回', () {
      expect(
        ChatVariableService.resolveGetVars('普通正文', {'hp': '42'}),
        '普通正文',
      );
    });
  });
}
