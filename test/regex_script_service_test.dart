import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/regex_script.dart';
import 'package:pocket_inn/services/regex_script_service.dart';

void main() {
  group('RegexScript.fromJson ST 字段映射', () {
    test('完整字段映射', () {
      final script = RegexScript.fromJson({
        'scriptName': '状态栏兜底',
        'findRegex': r'pattern',
        'replaceString': r'repl',
        'trimStrings': true,
        'placement': 'ai_output',
        'markdownOnly': false,
        'promptOnly': false,
        'runOnEdit': false,
        'disabled': true,
      });
      expect(script.name, '状态栏兜底');
      expect(script.findRegex, 'pattern');
      expect(script.replaceString, 'repl');
      expect(script.trimStrings, isTrue);
      expect(script.disabled, isTrue);
      expect(script.appliesToOutput, isFalse);
    });

    test('缺字段回退默认值', () {
      final script = RegexScript.fromJson({'findRegex': r'x'});
      expect(script.name, 'x');
      expect(script.placement, 'ai_output');
      expect(script.appliesToOutput, isTrue);
    });

    test('ST 数组字段（trimStrings 为数组）不崩溃', () {
      final script = RegexScript.fromJson({
        'scriptName': 'weird',
        'findRegex': r'y',
        'trimStrings': ['before', 'after'], // ST 旧格式数组
        'placement': ['ai_output'], // 数组 placement
      });
      expect(script.trimStrings, isFalse);
      expect(script.placement, 'ai_output');
      expect(script.appliesToOutput, isTrue);
    });
  });

  group('scriptsFromCharacterCard', () {
    test('读取 data.extensions.regex_scripts', () {
      final scripts = RegexScriptService.scriptsFromCharacterCard({
        'data': {
          'extensions': {
            'regex_scripts': [
              {'scriptName': 'A', 'findRegex': r'a'},
              {'scriptName': 'B', 'findRegex': r'b'},
            ],
          },
        },
      });
      expect(scripts.length, 2);
      expect(scripts.map((s) => s.name), ['A', 'B']);
    });

    test('无 regex_scripts 返回空', () {
      expect(
        RegexScriptService.scriptsFromCharacterCard({'data': {'extensions': {}}}),
        isEmpty,
      );
      expect(RegexScriptService.scriptsFromCharacterCard(null), isEmpty);
    });
  });

  group('applyToOutput', () {
    test('捕获组替换 ${1}', () {
      final out = RegexScriptService.applyToOutput(
        '📊 状态栏未更新：{{getvar::hp}}',
        const [
          RegexScript(
            name: 'fallback',
            findRegex: r'📊 状态栏未更新：\{\{getvar::([^}]+)\}\}',
            replaceString: r'HP:${1}',
          ),
        ],
      );
      expect(out, 'HP:hp');
    });

    test('replaceString 含 {{ 宏模板的 ST 兜底脚本跳过（不吞正文）', () {
      // StatusFallback 类：lookahead 不含面板关键词时整块替换为模板
      const statusFallback = RegexScript(
        name: 'StatusFallback',
        findRegex:
            r'^(?![\s\S]*(?:<!--panel-->|```|状态栏|状态面板))[\s\S]*$',
        replaceString:
            '{{match}}\\n<!--panel-->\\n📊 状态栏未更新\\n<!--/panel-->',
      );
      const text = '*她抬眸*「你终于来了。」';
      final out = RegexScriptService.applyToOutput(text, const [
        statusFallback,
      ]);
      // 正文必须原样保留（不被替换成宏模板）
      expect(out, text);
    });

    test('HideThink（空替换）/CleanPunct（纯文本替换）照常执行', () {
      const scripts = [
        RegexScript(name: 'HideThink', findRegex: r'<think>[\s\S]*?</think>', replaceString: ''),
        RegexScript(name: 'CleanPunct', findRegex: r'…{2,}', replaceString: '…'),
      ];
      final out = RegexScriptService.applyToOutput(
        '<think>思考</think>正文……',
        scripts,
      );
      expect(out, '正文…');
    });

    test('空替换 = 删除匹配', () {
      final out = RegexScriptService.applyToOutput(
        '【隐藏内容】正文',
        const [
          RegexScript(name: 'hide', findRegex: r'【隐藏内容】', replaceString: ''),
        ],
      );
      expect(out, '正文');
    });

    test('disabled / promptOnly 脚本跳过', () {
      const scripts = [
        RegexScript(
          name: 'off',
          findRegex: r'a',
          replaceString: 'b',
          disabled: true,
        ),
        RegexScript(
          name: 'prompt',
          findRegex: r'c',
          replaceString: 'd',
          promptOnly: true,
        ),
      ];
      expect(RegexScriptService.applyToOutput('ac', scripts), 'ac');
    });

    test('非法正则静默跳过不崩溃', () {
      final out = RegexScriptService.applyToOutput(
        '正文',
        const [RegexScript(name: 'bad', findRegex: r'(', replaceString: 'x')],
      );
      expect(out, '正文');
    });

    test('危险嵌套量词正则 + 长文本跳过（ReDoS 防护）', () {
      // (a+)+$ 在 6000 个 a 后接非匹配字符会灾难性回溯，防护应直接跳过
      final longText = '${'a' * 6000}b';
      final out = RegexScriptService.applyToOutput(
        longText,
        const [
          RegexScript(
            name: 'redos',
            findRegex: r'^(a+)+$',
            replaceString: 'x',
          ),
        ],
      );
      expect(out, longText); // 原样返回，不执行危险正则
    });

    test('markdownOnly 仅 Markdown 阶段执行', () {
      const script = [
        RegexScript(
          name: 'md',
          findRegex: r'a',
          replaceString: 'b',
          markdownOnly: true,
        ),
      ];
      expect(RegexScriptService.applyToOutput('a', script), 'a');
      expect(
        RegexScriptService.applyToOutput('a', script, forMarkdown: true),
        'b',
      );
    });

    test('按列表顺序逐条应用', () {
      final out = RegexScriptService.applyToOutput(
        'abc',
        const [
          RegexScript(name: '1', findRegex: r'a', replaceString: 'x'),
          RegexScript(name: '2', findRegex: r'x', replaceString: 'z'),
        ],
      );
      expect(out, 'zbc');
    });

    test('trimStrings 先修剪', () {
      final out = RegexScriptService.applyToOutput(
        '  正文  ',
        const [
          RegexScript(
            name: 'trim',
            findRegex: r'正',
            replaceString: 'X',
            trimStrings: true,
          ),
        ],
      );
      expect(out, 'X文');
    });

    test(r'第 10 组以上捕获组不被 $1 截胡（倒序替换）', () {
      final out = RegexScriptService.applyToOutput(
        'a b c d e f g h i j',
        const [
          RegexScript(
            name: 'groups10',
            findRegex: r'(\w) (\w) (\w) (\w) (\w) (\w) (\w) (\w) (\w) (\w)',
            replaceString: r'$10',
          ),
        ],
      );
      expect(out, 'j');
    });
  });
}
