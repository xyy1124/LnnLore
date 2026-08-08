// v76 回归测试：卡级协议兼容修复——
//  - semanticHints 放字段顶层（updatePolicy 外面）不再静默失效
//    （部分卡把 meaning/positiveSignals 写错层级，App 之前全忽略）
//  - 信号列表支持字符串写法（"双修/做爱/内射" 斜杠分隔），
//    之前只接受 JSON 数组、字符串被整组忽略
//  - updatePolicy 内已声明 semanticHints 时以内部为准（不覆盖）
//  - 只有顶层 semanticHints、无 updatePolicy 的字段也能生成策略
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

TrackerConfig _config(Map<String, dynamic> schema) {
  return TrackerConfig.fromCardJson({
    'data': {
      'extensions': {
        'tracker': {
          'stateSchema': schema,
          'initialState': {
            for (final e in schema.entries)
              e.key: e.value['type'] == 'number' ? 0 : '',
          },
        },
      },
    },
  });
}

void main() {
  group('v76 字段顶层 semanticHints 兼容', () {
    test('semanticHints 放字段顶层也能解析（meaning + 信号）', () {
      final config = _config({
        'sp_lv': {
          'type': 'number',
          'label': '魂力等级',
          'updatePolicy': {
            'mode': 'conservative',
            'qualitativeDeltas': {'一点': 1, '双修一次': 2},
            'maxAutoDeltaPerTurn': 2,
          },
          // 旧卡写法：semanticHints 与 updatePolicy 平级
          'semanticHints': {
            'meaning': '做爱即修炼，每次+2',
            'positiveSignals': '双修/做爱/内射',
            'negativeSignals': ['禁欲', '魂力受损'],
            'neutralSignals': '普通对话,日常训练',
          },
        },
      });
      final hints = config.stateSchema['sp_lv']?.updatePolicy?.semanticHints;
      expect(hints, isNotNull, reason: '字段顶层 semanticHints 必须被合并');
      expect(hints!.meaning, '做爱即修炼，每次+2');
      expect(hints.positiveSignals, ['双修', '做爱', '内射'],
          reason: '斜杠分隔字符串拆成数组');
      expect(hints.negativeSignals, ['禁欲', '魂力受损'],
          reason: 'JSON 数组照常解析');
      expect(hints.neutralSignals, ['普通对话', '日常训练'],
          reason: '逗号分隔字符串拆成数组');
      // updatePolicy 本身内容不被破坏
      final policy = config.stateSchema['sp_lv']?.updatePolicy;
      expect(policy!.qualitativeDeltas['双修一次'], 2);
      expect(policy.maxAutoDeltaPerTurn, 2);
    });

    test('updatePolicy 内已有 semanticHints 时以内部为准（不覆盖）', () {
      final config = _config({
        'f': {
          'type': 'string',
          'label': '好感',
          'updatePolicy': {
            'semanticHints': {
              'meaning': '内部 meaning',
              'positiveSignals': ['内部信号'],
            },
          },
          'semanticHints': {
            'meaning': '顶层 meaning（应被忽略）',
            'positiveSignals': '顶层信号',
          },
        },
      });
      final hints = config.stateSchema['f']?.updatePolicy?.semanticHints;
      expect(hints!.meaning, '内部 meaning');
      expect(hints.positiveSignals, ['内部信号']);
    });

    test('只有顶层 semanticHints、无 updatePolicy 也能生成策略', () {
      final config = _config({
        'g': {
          'type': 'string',
          'label': '阶段',
          'semanticHints': {'meaning': '仅顶层提示', 'positiveSignals': '推进'},
        },
      });
      final policy = config.stateSchema['g']?.updatePolicy;
      expect(policy, isNotNull, reason: '无 updatePolicy 也应生成默认策略');
      expect(policy!.mode, 'conservative');
      expect(policy.semanticHints!.meaning, '仅顶层提示');
      expect(policy.semanticHints!.positiveSignals, ['推进']);
    });
  });

  group('v76 兼容后注入验证', () {
    test('formatTrackerInstruction 注入 meaning/positive（语义不再丢失）', () {
      final config = _config({
        'sp_lv': {
          'type': 'number',
          'label': '魂力等级',
          'min': 0,
          'max': 100,
          'updatePolicy': {
            'mode': 'conservative',
            'qualitativeDeltas': {'双修一次': 2},
          },
          'semanticHints': {
            'meaning': '做爱即修炼，每次+2',
            'positiveSignals': '双修/做爱/魂力提升',
            'negativeSignals': ['禁欲'],
            'neutralSignals': '普通对话',
          },
        },
      });
      final text = TrackerRuntime.formatTrackerInstruction(
        state: {'sp_lv': 20},
        config: config,
      );
      expect(text, contains('meaning=做爱即修炼，每次+2'));
      expect(text, contains('positive=双修，做爱，魂力提升'));
      expect(text, contains('negative=禁欲'));
      expect(text, contains('neutral=普通对话'));
    });
  });
}
