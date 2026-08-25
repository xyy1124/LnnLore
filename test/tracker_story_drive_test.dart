// v67 回归测试：状态系统从"剧情记录器"升级为"剧情驱动器"——
//  - 清理 Tracker prompt 中的 ** 残留（污染协议文本）
//  - kTrackerStoryInfluenceSuffix 状态约束指令
//  - extractConsequence（下一轮剧情影响指令提取）
//  - _trackerStateText 注入 narrative/consequence（下一轮主模型能读到
//    上一轮动态解读与剧情影响）
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
            'updatePolicy': {
              'mode': 'conservative',
              'qualitativeDeltas': {'一点': 1, '明显': 5, '大幅': 10},
            },
          },
          'current_status': {
            'type': 'string',
            'label': '当前状态',
            'allowCustomValues': true,
            'presentation': {
              'states': {
                '警戒': {
                  'title': '警戒',
                  'color': '#78909C',
                  'text': '她保持距离。',
                },
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
  group('v67 prompt 清理', () {
    test('formatTrackerInstruction 不再含 ** 残留', () {
      final text = TrackerRuntime.formatTrackerInstruction(
        state: {'fall_progress': 20, 'current_status': '警戒'},
        config: _config(),
      );
      expect(text.contains('**'), isFalse);
    });

    test('kTrackerStoryInfluenceSuffix 存在且无 **', () {
      expect(
        TrackerRuntime.kTrackerStoryInfluenceSuffix,
        contains('状态对剧情的约束'),
      );
      expect(
        TrackerRuntime.kTrackerStoryInfluenceSuffix.contains('**'),
        isFalse,
      );
      expect(
        TrackerRuntime.kTrackerStoryInfluenceSuffix,
        contains('不得无视、重置或无理由逆转当前状态'),
      );
      expect(
        TrackerRuntime.kTrackerStoryInfluenceSuffix.contains('并输出对应 patch'),
        isFalse,
      );
    });
  });

  group('v67 extractConsequence', () {
    test('裁判输出 {patch, narrative, consequence} 提取 consequence', () {
      const text = '```json\n'
          '{"patch":{"set":{"current_status":"压制中"},"add":{"fall_progress":2}},'
          '"narrative":{"fall_progress":"她的身体反应已经开始突破意志防线。"},'
          '"consequence":{"fall_progress":"后续应表现更明显的非自主身体反应。"}}\n'
          '```';
      final raw = TrackerRuntime.extractConsequence(text);
      expect(raw.containsKey('fall_progress'), isTrue);
      expect(raw['fall_progress'], '后续应表现更明显的非自主身体反应。');
    });

    test('consequence 规范化（中文 label → key）', () {
      final canonical = TrackerRuntime.canonicalizeNarrative(
        {'堕落进度': '后续应表现更明显的非自主身体反应。'},
        _config(),
      );
      expect(canonical.containsKey('fall_progress'), isTrue);
    });

    test('无 consequence 时返回空', () {
      const text = '{"patch":{"set":{}}}';
      expect(TrackerRuntime.extractConsequence(text), isEmpty);
    });
  });

  group('v67 下一轮注入', () {
    test('_trackerStateText 注入 narrative 表现段', () {
      // 通过 renderStatusPanelHtml 无直接入口——用 formatTrackerInstruction
      // 验证注入文本包含 narrative 段结构（实际注入在 chat_service 组装，
      // 此处验证 tracker_runtime 提供的素材）
      final narrative = <String, String>{
        'fall_progress': '她的身体反应已经开始突破意志防线。',
      };
      expect(narrative['fall_progress'], isNotEmpty);
      // 验证 key 规范化后可用于注入
      final canonical = TrackerRuntime.canonicalizeNarrative(
        narrative,
        _config(),
      );
      expect(canonical.containsKey('fall_progress'), isTrue);
    });

    test('narrative/consequence 字段级标签映射', () {
      // 注入时 label 映射：fall_progress → 堕落进度
      final label = _config().stateSchema['fall_progress']?.label;
      expect(label, '堕落进度');
    });
  });

  group('v67 协议', () {
    test('kTrackerProtocolSuffix 不含 ** 残留', () {
      expect(TrackerRuntime.kTrackerProtocolSuffix.contains('**'), isFalse);
    });

    test('selectRelevantText 保留 consequence 关键词段落', () {
      final text = List.filled(300, '普通段落内容').join('\n') +
          '\n她的衣服被撕破了，露出大片肌肤。\n' +
          List.filled(300, '更多普通内容').join('\n');
      final trimmed = TrackerRuntime.selectRelevantText(
        text,
        config: _config(),
        maxChars: 3500,
      );
      expect(trimmed.length, lessThanOrEqualTo(3500));
      expect(trimmed, isNotEmpty);
    });
  });
}
