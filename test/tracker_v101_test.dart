// v101 回归：实体卡数值栏不更新 + 正文末尾状态提示剥不掉
//  - 裁判 field 用中文 label/旧键/阶段名时，收成 instance key
//  - number 只接受能抽出的数字（15、+15、15/100），拒绝「无痕」
//  - initState 补 entity.<id>.<field> 初值，add 才能叠到面板正在读的键
//  - 双模板都注入裁判/主模型摘要
//  - stripTrailingPlainTrackerPanel 用模板 label（根 schema 为空也能剥）
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

const Map<String, dynamic> _ywyCard = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': 2,
        'entityTemplates': {
          'demon_lord': {
            'label': '魔尊状态',
            'defaultState': {'brand': 0, 'cloth': '完好', 'stage': '本尊'},
            'stateSchema': {
              'brand': {
                'type': 'number',
                'label': '烙印值',
                'min': 0,
                'max': 100,
                'aliases': ['烙印值'],
                'updatePolicy': {
                  'mode': 'conservative',
                  'qualitativeDeltas': {'一点': 1, '明显': 5},
                  'semanticHints': {
                    'meaning': '臣服与依赖程度',
                    'positiveSignals': ['灵力注入'],
                    'negativeSignals': ['驱散净化'],
                    'neutralSignals': ['普通交谈'],
                  },
                },
                'presentation': {
                  'ranges': [
                    {
                      'gte': 0,
                      'lt': 20,
                      'title': '无痕',
                      'color': '#8e8e93',
                      'text': '烙印尚未显现',
                    },
                  ],
                },
              },
              'cloth': {
                'type': 'string',
                'label': '黑丝状态',
                'aliases': ['黑丝状态'],
                'allowCustomValues': true,
                'updatePolicy': {
                  'semanticHints': {
                    'meaning': '当前黑丝状态',
                    'positiveSignals': ['撕破'],
                    'negativeSignals': ['仅提及'],
                    'neutralSignals': ['无信息'],
                  },
                },
              },
              'stage': {
                'type': 'string',
                'label': '称呼阶段',
                'aliases': ['称呼阶段'],
                'allowCustomValues': true,
                'updatePolicy': {
                  'semanticHints': {
                    'meaning': '当前称呼阶段',
                    'positiveSignals': ['新称呼'],
                    'negativeSignals': ['延续'],
                    'neutralSignals': ['无信息'],
                  },
                },
              },
            },
          },
          'righteous_cultivator': {
            'label': '正道女修状态',
            'defaultState': {
              'relationship': '素不相识',
              'corruption': 0,
              'clothing': '仙袍整齐',
            },
            'stateSchema': {
              'relationship': {
                'type': 'string',
                'label': '关系阶段',
                'allowCustomValues': true,
                'updatePolicy': {
                  'semanticHints': {
                    'meaning': '与魔尊的关系',
                    'positiveSignals': ['初遇'],
                    'negativeSignals': ['挣脱'],
                    'neutralSignals': ['普通交谈'],
                  },
                },
              },
              'corruption': {
                'type': 'number',
                'label': '堕落阶段',
                'min': 0,
                'max': 100,
                'aliases': ['堕落阶段', '堕落', '堕落度'],
              },
              'clothing': {
                'type': 'string',
                'label': '衣着',
                'allowCustomValues': true,
                'updatePolicy': {
                  'semanticHints': {
                    'meaning': '当前衣着',
                    'positiveSignals': ['褪去'],
                    'negativeSignals': ['穿回'],
                    'neutralSignals': ['未提及'],
                  },
                },
              },
            },
          },
        },
        'initialEntities': [
          {
            'id': 'ywy',
            'displayName': '夜无央',
            'templateId': 'demon_lord',
            'initiallyAppeared': true,
            'initialState': {'brand': 0, 'cloth': '完好', 'stage': '本尊'},
          },
        ],
        'entityDiscovery': {
          'enabled': true,
          'defaultTemplateId': 'righteous_cultivator',
          'maxAutoEntities': 24,
        },
        'migrations': [
          {
            'id': 'legacy-ywy-v1',
            'targetEntityId': 'ywy',
            'fieldMap': {
              'yw_brand': 'brand',
              'yw_cloth': 'cloth',
              'yw_stage': 'stage',
            },
          },
        ],
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_ywyCard);

Map<String, dynamic> _registry({
  String templateId = 'demon_lord',
  bool appeared = true,
}) =>
    {
      'version': 1,
      'nextDynamicOrdinal': 1,
      'appliedMigrations': <String>[],
      'entities': [
        {
          'id': 'ywy',
          'templateId': templateId,
          'displayName': '夜无央',
          'aliases': <String>[],
          'order': 0,
          'source': 'preset',
          'appeared': appeared,
        },
      ],
    };

void main() {
  group('v101 数值抽取', () {
    test('15 / +15 / 15/100 抽出数字，阶段名拒绝', () {
      expect(TrackerRuntime.coerceNumericValue(15), 15);
      expect(TrackerRuntime.coerceNumericValue('+15'), 15);
      expect(TrackerRuntime.coerceNumericValue('15/100'), 15);
      expect(TrackerRuntime.coerceNumericValue('无痕'), isNull);
      expect(TrackerRuntime.coerceNumericValue('刻印显现'), isNull);
    });
  });

  group('v101 实体 update 收成 instance key', () {
    test('中文 label 烙印值 + 数字 15 → entity.ywy.brand', () {
      final compiled = TrackerRuntime.compileEntityUpdate(
        item: {
          'entityRef': 'ywy',
          'field': '烙印值',
          'op': 'set',
          'value': 15,
        },
        idMap: const {},
        registry: _registry(),
        config: _config(),
      );
      expect(compiled, isNotNull);
      expect(compiled!.instanceKey, 'entity.ywy.brand');
      expect(compiled.isDelta, isFalse);
      expect(compiled.value, 15);
    });

    test('显示名夜无央 + op=delta → 叠到 ywy.brand', () {
      final compiled = TrackerRuntime.compileEntityUpdate(
        item: {
          'entityRef': '夜无央',
          'field': 'brand',
          'op': 'delta',
          'value': 10,
        },
        idMap: const {},
        registry: _registry(),
        config: _config(),
      );
      expect(compiled, isNotNull);
      expect(compiled!.instanceKey, 'entity.ywy.brand');
      expect(compiled.isDelta, isTrue);
      expect(compiled.value, 10);
    });

    test('旧键 yw_brand 经 migration 收到 brand', () {
      final compiled = TrackerRuntime.compileEntityUpdate(
        item: {
          'entityRef': 'ywy',
          'field': 'yw_brand',
          'op': 'delta',
          'value': '5',
        },
        idMap: const {},
        registry: _registry(),
        config: _config(),
      );
      expect(compiled, isNotNull);
      expect(compiled!.instanceKey, 'entity.ywy.brand');
      expect(compiled.isDelta, isTrue);
      expect(compiled.value, 5);
    });

    test('number 写成阶段名无痕 → 丢弃，不落脏键', () {
      expect(
        TrackerRuntime.compileEntityUpdate(
          item: {
            'entityRef': 'ywy',
            'field': 'brand',
            'op': 'set',
            'value': '无痕',
          },
          idMap: const {},
          registry: _registry(),
          config: _config(),
        ),
        isNull,
      );
    });
  });

  group('v101 initState / add 叠到面板键', () {
    test('空变量表补 entity.ywy.brand=0，add 15 后面板键变成 15', () {
      final config = _config();
      final seeded = TrackerRuntime.initState(config: config);
      expect(seeded['entity.ywy.brand'], 0);
      expect(seeded['entity.ywy.cloth'], '完好');

      final next = TrackerRuntime.applyPatchToVariables(
        variables: const {},
        patch: StatePatch(
          addValues: {'entity.ywy.brand': 15},
          protocolDetected: true,
        ),
        config: config,
      );
      expect(next['entity.ywy.brand'], '15');
    });

    test('已有 0 再 delta 10 → 10（不是停在 0）', () {
      final next = TrackerRuntime.applyPatchToVariables(
        variables: {'entity.ywy.brand': '0'},
        patch: StatePatch(
          addValues: {'entity.ywy.brand': 10},
          protocolDetected: true,
        ),
        config: _config(),
      );
      expect(next['entity.ywy.brand'], '10');
    });
  });

  group('v101 双模板注入', () {
    test('裁判指令同时含 demon_lord 与 righteous_cultivator', () {
      final text = TrackerRuntime.formatEntityTrackerInstruction(
        variables: {
          TrackerRuntime.kEntityRegistryKey:
              TrackerRuntime.encodeEntityRegistry(_registry()),
          'entity.ywy.brand': '0',
        },
        config: _config(),
      );
      expect(text, contains('demon_lord'));
      expect(text, contains('righteous_cultivator'));
      expect(text, contains('field=brand'));
      expect(text, contains('field=corruption'));
      expect(text, contains('禁止中文 label'));
      expect(text, contains('value 必须是数字增量'));
    });

    test('主模型摘要也列出两套模板', () {
      final text = TrackerRuntime.formatEntityStateSummary(
        variables: {
          TrackerRuntime.kEntityRegistryKey:
              TrackerRuntime.encodeEntityRegistry(_registry()),
          'entity.ywy.brand': '0',
        },
        config: _config(),
      );
      expect(text, contains('demon_lord'));
      expect(text, contains('righteous_cultivator'));
      expect(text, isNot(contains('entities')));
    });
  });

  group('v101 正文末尾状态提示', () {
    test('实体卡根 schema 为空时仍剥离 烙印值/黑丝状态', () {
      final config = _config();
      expect(config.stateSchema, isEmpty);
      expect(config.allFieldLabels.contains('烙印值'), isTrue);

      const text = '她咬紧银牙，黑丝下渗出黏腻。\n'
          '烙印值：15/100\n'
          '黑丝状态：微破';
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
      );
      expect(stripped, '她咬紧银牙，黑丝下渗出黏腻。');
      expect(stripped.contains('烙印值'), isFalse);
    });

    test('kStoryOnlySuffix 禁止正文末尾状态提示', () {
      final suffix = TrackerRuntime.kStoryOnlySuffix;
      expect(suffix, contains('只输出剧情正文'));
      expect(suffix, contains('正文末尾'));
      expect(suffix, contains('状态判断由独立裁判完成'));
    });

    test('v102 Gemini 风格【状态更新】+ 列表 + 字段+N 也能剥', () {
      final config = _config();
      const text = '她咬紧银牙，黑丝下渗出黏腻。\n'
          '【状态更新】\n'
          '- 烙印值 +15\n'
          '- 黑丝状态：微破';
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
      );
      expect(stripped, '她咬紧银牙，黑丝下渗出黏腻。');
      expect(stripped.contains('烙印值'), isFalse);
      expect(stripped.contains('状态更新'), isFalse);
    });

    test('v102 只有标题+一栏也剥（Gemini 常只复述一栏）', () {
      final config = _config();
      const text = '她把脸埋进臂弯。\n'
          '本轮状态变化\n'
          '烙印值：15/100';
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
      );
      expect(stripped, '她把脸埋进臂弯。');
    });

    test('v102 单行剧情提到字段仍不剥', () {
      final config = _config();
      const text = '剧情里她低声嘀咕烙印值：15/100 不是状态栏。';
      final stripped = TrackerRuntime.stripTrailingPlainTrackerPanel(
        text,
        config,
      );
      expect(stripped, contains('烙印值'));
    });
  });

  _sylDiscoveryTests();
}

const Map<String, dynamic> _sylCard = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': 2,
        'entityTemplates': {
          'sect_master': {
            'label': '掌门',
            'defaultState': {'chi': 1, 'seal': '无'},
            'stateSchema': {
              'chi': {'type': 'number', 'label': '痴缠业', 'min': 0, 'max': 5},
              'seal': {
                'type': 'string',
                'label': '玉塞',
                'allowCustomValues': true,
                'updatePolicy': {
                  'semanticHints': {
                    'meaning': '玉塞状态',
                    'positiveSignals': ['放入'],
                    'negativeSignals': ['取出'],
                    'neutralSignals': ['未提及'],
                  },
                },
              },
            },
          },
          'disciple': {
            'label': '弟子',
            'defaultState': {'initiation': '新入门', 'reform': 0, 'bond': 20},
            'stateSchema': {
              'initiation': {
                'type': 'string',
                'label': '入门',
                'allowCustomValues': true,
                'updatePolicy': {
                  'semanticHints': {
                    'meaning': '入门阶段',
                    'positiveSignals': ['入门'],
                    'negativeSignals': ['未入门'],
                    'neutralSignals': ['未提及'],
                  },
                },
              },
              'reform': {'type': 'number', 'label': '改造', 'min': 0, 'max': 100},
              'bond': {'type': 'number', 'label': '羁绊', 'min': 0, 'max': 100},
            },
          },
        },
        'initialEntities': [
          {
            'id': 'syl',
            'displayName': '苏蕴泠',
            'templateId': 'sect_master',
            'initiallyAppeared': true,
            'initialState': {'chi': 1, 'seal': '无'},
          },
          {
            'id': 'zle',
            'displayName': '赵灵儿',
            'templateId': 'disciple',
            'initiallyAppeared': false,
            'initialState': {'initiation': '新入门', 'reform': 0, 'bond': 20},
          },
        ],
        'entityDiscovery': {
          'enabled': true,
          'defaultTemplateId': 'disciple',
          'maxAutoEntities': 24,
        },
      },
    },
  },
};

void _sylDiscoveryTests() {
  group('v102 苏蕴泠式新角色发现', () {
    final config = TrackerConfig.fromCardJson(_sylCard);
    final registry = {
      'version': 1,
      'nextDynamicOrdinal': 1,
      'appliedMigrations': <String>[],
      'entities': [
        {
          'id': 'syl',
          'templateId': 'sect_master',
          'displayName': '苏蕴泠',
          'appeared': true,
          'order': 0,
          'source': 'preset',
        },
        {
          'id': 'zle',
          'templateId': 'disciple',
          'displayName': '赵灵儿',
          'appeared': false,
          'order': 1,
          'source': 'preset',
        },
      ],
    };

    test('updates 里只有中文名林清雪 → 推断发现，不重复苏蕴泠', () {
      final inferred = TrackerRuntime.inferDiscoveredEntities(
        envelope: {
          'entities': <dynamic>[],
          'appearedEntityRefs': <dynamic>[],
          'updates': [
            {
              'entityRef': '林清雪',
              'field': 'initiation',
              'op': 'set',
              'value': '新入门',
            },
          ],
        },
        registry: registry,
        config: config,
      );
      expect(inferred.length, 1);
      expect(inferred.first['displayName'], '林清雪');
      expect(inferred.any((e) => e['displayName'] == '苏蕴泠'), isFalse);
    });

    test('已有 entities 数组时不重复推断同名', () {
      final inferred = TrackerRuntime.inferDiscoveredEntities(
        envelope: {
          'entities': [
            {'ref': 'new:1', 'displayName': '林清雪', 'templateId': 'disciple'},
          ],
          'updates': [
            {'entityRef': '林清雪', 'field': 'bond', 'op': 'delta', 'value': 5},
          ],
        },
        registry: registry,
        config: config,
      );
      expect(inferred.where((e) => e['displayName'] == '林清雪').length, 1);
    });

    test('赵灵儿已在预设里 → 不新建 dyn', () {
      final inferred = TrackerRuntime.inferDiscoveredEntities(
        envelope: {
          'updates': [
            {'entityRef': '赵灵儿', 'field': 'bond', 'op': 'delta', 'value': 3},
          ],
        },
        registry: registry,
        config: config,
      );
      expect(inferred, isEmpty);
    });
  });
}
