// v65 回归测试：narrative 动态解读完整链路——
// 审查 v65 指出的"值变了、点号还在、解释却空了"问题：
//  1. patch 使用 key，narrative 使用中文 label → 映射到同一 key
//  2. 一轮修改三个字段、裁判只解释一个 → 最终 v4 快照三个字段都不能缺少说明
//  3. 字符串变成 presentation.states 中不存在的新值 → gettitle/getnarrative 不得留下空白
//  4. 未变化字段没有新 narrative → 继承上一条消息的解读
//  5. 已变化字段没有新 narrative → 不得继承旧解读，使用新阶段描述或确定性兜底
//  6. allowCustomValues=false 拒绝未声明 string 值
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
            'presentation': {
              'ranges': [
                {
                  'gte': 0,
                  'lt': 20,
                  'title': '初始',
                  'color': '#78909C',
                  'text': '尚未开始堕落。',
                },
                {
                  'gte': 20,
                  'lt': 40,
                  'title': '松动',
                  'color': '#66BB6A',
                  'text': '开始产生动摇。',
                },
              ],
            },
          },
          'current_status': {
            'type': 'string',
            'label': '当前状态',
            'aliases': ['状态', '处境'],
            'allowCustomValues': false,
            'presentation': {
              'states': {
                '警戒': {
                  'title': '警戒',
                  'color': '#78909C',
                  'text': '她保持距离，随时准备反击。',
                },
                '拦截对峙': {
                  'title': '拦截对峙',
                  'color': '#66BB6A',
                  'text': '她正在细数你的行为。',
                },
                '压制中': {
                  'title': '压制中',
                  'color': '#FFA726',
                  'text': '她的反抗正在被压制。',
                },
              },
            },
          },
          'clothing_status': {
            'type': 'string',
            'label': '服装状态',
            // 自由组合字段：允许自定义值
            'presentation': {
              'states': {
                '整齐完整': {
                  'title': '整齐完整',
                  'color': '#78909C',
                  'text': '衣物完好。',
                },
              },
            },
          },
        },
        'initialState': {
          'fall_progress': 0,
          'current_status': '警戒',
          'clothing_status': '整齐完整',
        },
        'template':
            '<span>堕落进度</span>：<b>{{getvar::fall_progress}}</b> · {{gettitle::fall_progress}}<br>'
            '<span>{{getnarrative::fall_progress}}</span><br>'
            '<span>当前状态</span>：<b>{{getvar::current_status}}</b> · {{gettitle::current_status}}<br>'
            '<span>{{getnarrative::current_status}}</span><br>'
            '<span>服装状态</span>：<b>{{getvar::clothing_status}}</b> · {{gettitle::clothing_status}}<br>'
            '<span>{{getnarrative::clothing_status}}</span>',
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_cardJson);

void main() {
  group('v65 narrative 规范化', () {
    test('1. patch 使用 key，narrative 使用中文 label → 映射到同一 key', () {
      final config = _config();
      final narrative = TrackerRuntime.canonicalizeNarrative(
        {
          '堕落进度': '她的内心防线开始出现裂缝。',
          '当前状态': '她正在细数你的行为，试图维持威严。',
        },
        config,
      );
      expect(narrative.containsKey('fall_progress'), isTrue);
      expect(narrative.containsKey('current_status'), isTrue);
      expect(narrative['fall_progress'], '她的内心防线开始出现裂缝。');
    });

    test('1b. narrative 使用别名也能映射到真实 key', () {
      final config = _config();
      final narrative = TrackerRuntime.canonicalizeNarrative(
        {'状态': '她正在细数你的行为。'},
        config,
      );
      expect(narrative.containsKey('current_status'), isTrue);
    });

    test('1c. 无法识别的 narrative key 被丢弃', () {
      final config = _config();
      final narrative = TrackerRuntime.canonicalizeNarrative(
        {'不存在的字段': '无意义解读'},
        config,
      );
      expect(narrative, isEmpty);
    });
  });

  group('v65 changedKeys', () {
    test('number 按数值比较（字符串数字视为相同）', () {
      final config = _config();
      final changed = TrackerRuntime.changedKeys(
        before: {'fall_progress': '20'},
        after: {'fall_progress': '20'},
        config: config,
      );
      expect(changed, isEmpty);
    });

    test('string 按文本比较', () {
      final config = _config();
      final changed = TrackerRuntime.changedKeys(
        before: {'current_status': '警戒'},
        after: {'current_status': '压制中'},
        config: config,
      );
      expect(changed, contains('current_status'));
    });
  });

  group('v65 narrative 合并', () {
    test('2. 一轮修改三个字段、裁判只解释一个 → 三个字段都有解读', () {
      final config = _config();
      final merged = TrackerRuntime.mergeNarrative(
        previousNarrative: const {},
        judgeNarrative: {
          'fall_progress': '她的内心防线开始出现裂缝。',
        },
        beforeVariables: {
          'fall_progress': '27',
          'current_status': '拦截对峙',
          'clothing_status': '整齐完整',
        },
        afterVariables: {
          'fall_progress': '29',
          'current_status': '压制中',
          'clothing_status': '乳贴脱落、衣物凌乱',
        },
        config: config,
      );
      expect(merged['fall_progress'], '她的内心防线开始出现裂缝。');
      // current_status 裁判漏写 → 回退新阶段静态描述
      expect(merged['current_status'], '她的反抗正在被压制。');
      // clothing_status 裁判漏写 + 无匹配 states → 确定性兜底
      expect(merged['clothing_status'], contains('已变为'));
      expect(merged['clothing_status'], contains('乳贴脱落、衣物凌乱'));
    });

    test('4. 未变化字段没有新 narrative → 继承上一轮解读', () {
      final config = _config();
      final merged = TrackerRuntime.mergeNarrative(
        previousNarrative: {
          'fall_progress': '上一轮解读：内心防线出现裂缝。',
          'current_status': '上一轮解读：她试图维持威严。',
          'clothing_status': '上一轮解读：衣物开始凌乱。',
        },
        judgeNarrative: {
          'fall_progress': '本轮新解读：裂缝加深。',
        },
        beforeVariables: {
          'fall_progress': '29',
          'current_status': '压制中',
          'clothing_status': '乳贴脱落、衣物凌乱',
        },
        afterVariables: {
          'fall_progress': '30',
          'current_status': '压制中',
          'clothing_status': '乳贴脱落、衣物凌乱',
        },
        config: config,
      );
      // 已变化字段用新解读
      expect(merged['fall_progress'], '本轮新解读：裂缝加深。');
      // 未变化字段继承上一轮
      expect(merged['current_status'], '上一轮解读：她试图维持威严。');
      expect(merged['clothing_status'], '上一轮解读：衣物开始凌乱。');
    });

    test('5. 已变化字段没有新 narrative → 不得继承旧解读，用新阶段描述', () {
      final config = _config();
      final merged = TrackerRuntime.mergeNarrative(
        previousNarrative: {
          'current_status': '旧解读：她正在细数你的行为。',
        },
        judgeNarrative: const {},
        beforeVariables: {'current_status': '拦截对峙'},
        afterVariables: {'current_status': '压制中'},
        config: config,
      );
      // 已变化但裁判没给 → 不能是旧解读
      expect(merged['current_status'], isNot('旧解读：她正在细数你的行为。'));
      // 回退新阶段静态描述
      expect(merged['current_status'], '她的反抗正在被压制。');
    });
  });

  group('v65 渲染兜底', () {
    test('3. string 变成 states 中不存在的新值 → gettitle/getnarrative 不留空白', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: _cardJson,
        variables: {
          'fall_progress': '29',
          'current_status': '压制中',
          'clothing_status': '乳贴脱落、衣物凌乱',
        },
        narrative: const {},
      );
      // gettitle 回退原始值——"压制中"在 states 里，用标题；服装是自由值回退原始值
      expect(html, contains('压制中'));
      expect(html, contains('乳贴脱落、衣物凌乱'));
      // 不得留下"· 空"（gettitle 空 + 分隔符）
      expect(html, isNot(contains('· </span>')));
      expect(html, isNot(contains('·<br>')));
    });

    test('3b. getnarrative 有解读时优先动态解读', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: _cardJson,
        variables: {'fall_progress': '29'},
        narrative: {
          'fall_progress': '本轮剧情中她的眼神开始躲闪。',
        },
      );
      expect(html, contains('本轮剧情中她的眼神开始躲闪。'));
    });
  });

  group('v65 allowCustomValues', () {
    test('6. allowCustomValues=false 拒绝未声明 string 值', () {
      final config = _config();
      final next = TrackerRuntime.reduce(
        current: {'current_status': '警戒'},
        patch: StatePatch(
          setValues: {'current_status': '完全屈服'},
        ),
        config: config,
      );
      // 未声明的值被拒绝，保持原值
      expect(next['current_status'], '警戒');
    });

    test('6b. allowCustomValues=false 允许已声明值', () {
      final config = _config();
      final next = TrackerRuntime.reduce(
        current: {'current_status': '警戒'},
        patch: StatePatch(
          setValues: {'current_status': '压制中'},
        ),
        config: config,
      );
      expect(next['current_status'], '压制中');
    });

    test('6c. 自由组合 string 字段（默认 allowCustomValues=true）接受自定义值', () {
      final config = _config();
      final next = TrackerRuntime.reduce(
        current: {'clothing_status': '整齐完整'},
        patch: StatePatch(
          setValues: {'clothing_status': '乳贴脱落、衣物凌乱'},
        ),
        config: config,
      );
      expect(next['clothing_status'], '乳贴脱落、衣物凌乱');
    });
  });
}
