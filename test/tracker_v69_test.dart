// v69 回归测试：三模式不对称与状态栏混入正文修复——
//  - stripTrailingPlainTrackerPanel：纯文本状态栏尾部识别（≥2 label 行）
//  - stripPanelTemplates：剥离面板外"输出状态栏"指令句
//  - kTrackerProtocolSuffix：明确禁止 HTML/纯文本状态栏
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

const Map<String, dynamic> _cardJson = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': '1.0',
        'stateSchema': {
          'fall_progress': {
            'type': 'number',
            'label': '堕落进度',
            'min': 0,
            'max': 100,
          },
          'current_status': {
            'type': 'string',
            'label': '当前状态',
            'presentation': {
              'states': {
                '警戒': {'title': '警戒', 'color': '#78909C', 'text': '她保持距离。'},
                '压制中': {
                  'title': '压制中',
                  'color': '#FFA726',
                  'text': '她的反抗正在被压制。',
                },
              },
            },
          },
        },
        'initialState': {'fall_progress': 0, 'current_status': '警戒'},
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_cardJson);

void main() {
  group('v69 纯文本状态栏剥离', () {
    test('末尾"状态栏：label：值 x2"被剥离并回传值', () {
      final config = _config();
      const text = '她看着你，眼神有些复杂。\n'
          '状态栏：\n'
          '堕落进度：27/100\n'
          '当前状态：压制中';
      final values = <String, String>{};
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
        plainPanelValues: values,
      );
      expect(stripped, '她看着你，眼神有些复杂。');
      expect(values['堕落进度'], '27/100');
      expect(values['当前状态'], '压制中');
    });

    test('少于 2 个 label 行不剥离（防误删剧情）', () {
      final config = _config();
      const text = '剧情里提到：堕落进度：27/100 只有一行状态。';
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
      );
      expect(stripped, contains('堕落进度'));
    });

    test('末尾非状态行时不剥离（防误删正文）', () {
      final config = _config();
      const text = '她转过身，轻声说：堕落进度：27/100 不是状态栏。\n'
          '说完便离开了。';
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
      );
      expect(stripped, contains('她转过身'));
    });

    test('英文冒号 label: 值 也识别', () {
      final config = _config();
      const text = '正文内容。\n'
          '状态面板:\n'
          '堕落进度: 30\n'
          '当前状态: 警戒';
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
      );
      expect(stripped, '正文内容。');
    });
  });

  group('v69 输出状态栏指令句剥离', () {
    test('stripPanelTemplates 剥离"每次回复末尾输出状态栏"句', () {
      final stripped = TrackerRuntime.stripPanelTemplates(
        '【强制输出规则】\n'
        '每次回复末尾必须输出状态栏，不得省略。\n'
        '面板数值与剧情一致。\n'
        '<!--panel-->\n<details><summary>面板</summary></details>\n<!--/panel-->',
      );
      expect(stripped.contains('每次回复末尾必须输出状态栏'), isFalse);
      expect(stripped.contains('面板数值与剧情一致'), isTrue);
      expect(stripped.contains('<details>'), isFalse, reason: '面板块应被剥离');
    });

    test('剥离"请在正文末尾附带状态面板"句', () {
      final stripped = TrackerRuntime.stripPanelTemplates(
        '规则：请在正文末尾附带状态面板。\n其他规则。',
      );
      expect(stripped.contains('请在正文末尾附带状态面板'), isFalse);
      expect(stripped.contains('其他规则'), isTrue);
    });
  });

  group('v69 协议禁止状态栏', () {
    test('kTrackerProtocolSuffix 明确禁止 HTML/纯文本状态栏', () {
      final suffix = TrackerRuntime.kTrackerProtocolSuffix;
      expect(suffix, contains('禁止在 reply 中输出任何状态栏'));
      expect(suffix, contains('禁止输出 <details>'));
      expect(suffix, contains('禁止输出"当前状态："'));
      expect(suffix, contains('状态栏由 App 根据最终状态自动渲染'));
      expect(suffix, contains('patch、narrative、consequence 必须放在同一个 JSON'));
    });

    test('协议 JSON 示例仍可解析', () {
      final suffix = TrackerRuntime.kTrackerProtocolSuffix;
      final match = RegExp(r'```json\n([\s\S]*?)\n```').firstMatch(suffix);
      expect(match, isNotNull);
      final decoded = _jsonDecode(match!.group(1)!);
      expect(decoded['reply'], '剧情正文');
      expect(decoded['patch'], isA<Map<String, dynamic>>());
    });

    test('协议不再有接近 JSON 的中文占位', () {
      final suffix = TrackerRuntime.kTrackerProtocolSuffix;
      final jsonBlock = RegExp(r'```json\n([\s\S]*?)\n```')
          .firstMatch(suffix)!
          .group(1)!;
      expect(jsonBlock.contains('字段key'), isFalse);
      expect(jsonBlock.contains('数值变化'), isFalse);
    });
  });
}

Map<String, dynamic> _jsonDecode(String text) {
  return (jsonDecode(text) as Map).map(
    (k, v) => MapEntry(k.toString(), v),
  );
}
