// v71.2 回归测试：开场消息（first_mes）纯文本状态栏剥离——
// 辉夜大小姐卡 first_mes 末尾自带"当前场景：…\n好感：30/100"纯文本
// 状态栏，extractOpeningMessages 之前只剥 HTML 面板/协议块，纯文本
// label:值 行残留进正文。修复：传 cardJson 时对每条消息做
// stripTrailingPlainTrackerPanel。
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/services/chat_display_sanitizer.dart';

const Map<String, dynamic> _cardJson = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': '1.0',
        'stateSchema': {
          'kihao': {
            'type': 'number',
            'label': '辉夜好感',
            'min': 0,
            'max': 100,
          },
          'fcd': {
            'type': 'number',
            'label': '辉夜服从度',
            'min': 0,
            'max': 100,
          },
          'dld': {
            'type': 'number',
            'label': '辉夜堕落度',
            'min': 0,
            'max': 100,
          },
          'zsy': {
            'type': 'number',
            'label': '早坂爱献身意愿',
            'min': 0,
            'max': 100,
          },
          'scene': {
            'type': 'string',
            'label': '当前场景',
          },
        },
        'initialState': {
          'kihao': 30,
          'fcd': 20,
          'dld': 0,
          'zsy': 30,
          'scene': '四宫宅邸会客厅',
        },
      },
    },
  },
};

void main() {
  group('v71.2 开场消息纯文本状态栏剥离', () {
    test('first_mes 末尾纯文本状态栏被剥离（传 cardJson）', () {
      const firstMes = '（四宫宅邸会客厅，夕阳西下。辉夜站在那里……）\n'
          '辉夜双手轻轻握在身前：「……您就是那位军火商吧。」\n'
          '\n'
          '当前场景：四宫宅邸会客厅\n'
          '辉夜好感：30/100\n'
          '辉夜服从度：20/100\n'
          '辉夜堕落度：0/100\n'
          '早坂爱献身意愿：30/100';
      final result = ChatDisplaySanitizer.extractOpeningMessages(
        [firstMes],
        cardJson: _cardJson,
      );
      expect(result.messages.length, 1);
      final msg = result.messages.first;
      // 正文保留
      expect(msg, contains('辉夜站在那里'));
      expect(msg, contains('军火商'));
      // 纯文本状态栏被剥离
      expect(msg.contains('当前场景：四宫宅邸会客厅'), isFalse);
      expect(msg.contains('辉夜好感：30/100'), isFalse);
      expect(msg.contains('辉夜服从度'), isFalse);
      expect(msg.contains('早坂爱献身意愿'), isFalse);
    });

    test('不传 cardJson 时保持原行为（不清洗纯文本）', () {
      const firstMes = '开场正文。\n当前场景：四宫宅邸会客厅\n辉夜好感：30/100';
      final result = ChatDisplaySanitizer.extractOpeningMessages([firstMes]);
      expect(result.messages.first, contains('当前场景：四宫宅邸会客厅'));
    });

    test('正文中的"场景"叙事不被误删（只有 label 行才剥）', () {
      const firstMes = '夕阳下的会客厅，她站在窗边。\n'
          '「这是我们的初次见面。」\n'
          '当前场景：四宫宅邸会客厅\n'
          '辉夜好感：30/100';
      final result = ChatDisplaySanitizer.extractOpeningMessages(
        [firstMes],
        cardJson: _cardJson,
      );
      final msg = result.messages.first;
      // 叙事保留
      expect(msg, contains('夕阳下的会客厅'));
      expect(msg, contains('初次见面'));
      // 状态行剥离
      expect(msg.contains('当前场景：四宫宅邸会客厅'), isFalse);
      expect(msg.contains('辉夜好感：30/100'), isFalse);
    });

    test('少于 2 个 label 行不剥离（防误删）', () {
      const firstMes = '她提到：当前场景：四宫宅邸会客厅 只有一行状态。\n'
          '然后转身离开。';
      final result = ChatDisplaySanitizer.extractOpeningMessages(
        [firstMes],
        cardJson: _cardJson,
      );
      expect(result.messages.first, contains('只有一行状态'));
    });
  });
}
