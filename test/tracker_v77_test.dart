// v77 回归测试：状态栏模板兜底清洗——
//  - tracker.template 混入 PHI 指令文本（"标记；数值用 {{getvar}} 引用，
//    不得编造）：" 前缀 + <!--panel--> 块）时，渲染只取面板本体，
//    指令文本不再显示在状态栏里
//  - 无 ::key 的裸 {{getvar}}/{{gettitle}} 引用被剥离（渲染残留）
//  - 干净模板不受影响
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/services/tracker_runtime.dart';

Map<String, dynamic> _cardWithTemplate(String template) {
  return {
    'data': {
      'extensions': {
        'tracker': {
          'stateSchema': {
            'like': {
              'type': 'number',
              'label': '好感',
              'min': 0,
              'max': 100,
              'presentation': {
                'ranges': [
                  {'gte': 0, 'lt': 50, 'title': '冷淡', 'text': '冷淡期'},
                  {'gte': 50, 'title': '亲密', 'text': '亲密期'},
                ],
              },
            },
          },
          'initialState': {'like': 30},
          'template': template,
        },
      },
    },
  };
}

void main() {
  group('v77 脏模板清洗', () {
    test('template 含 PHI 指令前缀 + panel 块时只渲染块内面板', () {
      final card = _cardWithTemplate(
        '标记；数值用 {{getvar}} 引用真实变量，不得编造）：\n'
        '<!--panel-->\n'
        '<details><summary>测试面板</summary>'
        '<span>好感：【{{getvar::like}}】</span></details>\n'
        '<!--/panel-->',
      );
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'like': '35'},
      );
      expect(html, isNotNull);
      expect(html, isNot(contains('不得编造')),
          reason: 'PHI 指令文本不得进入渲染结果');
      expect(html, isNot(contains('标记；')),
          reason: '面板标记说明不得进入渲染结果');
      expect(html, contains('35'), reason: '面板本体正常渲染数值');
      expect(html, contains('测试面板'));
      expect(html, isNot(contains('<!--panel-->')),
          reason: 'panel 标记本身不显示');
    });

    test('裸 {{getvar}}（无 ::key）被剥离', () {
      final card = _cardWithTemplate(
        '<details><summary>面板</summary>'
        '裸引用：{{getvar}} 残留：{{gettitle}}\n'
        '<span>好感：【{{getvar::like}}】</span></details>',
      );
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'like': '40'},
      );
      expect(html, isNotNull);
      expect(html, isNot(contains('{{getvar}}')),
          reason: '裸引用被剥离');
      expect(html, isNot(contains('{{gettitle}}')));
      expect(html, contains('40'));
    });

    test('干净 template 不受影响', () {
      final card = _cardWithTemplate(
        '<details><summary>干净面板</summary>'
        '<span>好感：【{{getvar::like}}】</span></details>',
      );
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'like': '50'},
      );
      expect(html, contains('干净面板'));
      expect(html, contains('50'));
    });

    test('说明句内嵌假 <!--panel--> 标记不被误当面板起点', () {
      final card = _cardWithTemplate(
        '请保留 <!--panel--> 标记；数值用 {{getvar}} 引用（这不是面板起点）\n'
        '<details><summary>真面板</summary>'
        '<span>好感：【{{getvar::like}}】</span></details>',
      );
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'like': '60'},
      );
      expect(html, isNotNull);
      expect(html, contains('真面板'));
      expect(html, isNot(contains('不是面板起点')),
          reason: '假标记行不是独占整行的 panel 块，不被提取为模板');
    });
  });
}
