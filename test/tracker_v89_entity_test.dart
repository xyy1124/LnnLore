// v89 回归测试：动态实体（群像卡）——
//  - instance key codec（entity.<id>.<field>）
//  - 实体模板/预设解析（schemaVersion 2）
//  - envelope 规范化（new:N → dyn_ ID）
//  - 分区渲染（entitysections 插槽）
//  - narrative 元语言过滤
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

const Map<String, dynamic> _entityCard = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': 2,
        'entityTemplates': {
          'brainwashed_female': {
            'label': '角色洗脑状态',
            'defaultState': {'xno_depth': 0, 'xno_layer': 0},
            'stateSchema': {
              'xno_depth': {
                'type': 'number',
                'label': '洗脑深度',
                'min': 0,
                'max': 100,
                'updatePolicy': {
                  'mode': 'conservative',
                  'qualitativeDeltas': {'一点': 1, '大幅': 10},
                  'semanticHints': {
                    'meaning': '该角色被洗脑的深度。剧情中任何使她的意识受控程度发生实质变化的事件都应更新。',
                    'positiveSignals': ['洗脑', '灌输'],
                    'negativeSignals': ['清醒'],
                    'neutralSignals': ['普通对话'],
                  },
                },
              },
              'xno_layer': {
                'type': 'number',
                'label': '常识改写',
                'min': 0,
                'max': 5,
              },
            },
            'sectionTemplate': '<section><h4>{{entityname}}</h4>'
                '<div>{{getvar::xno_depth}} {{getnarrative::xno_depth}}</div></section>',
          },
        },
        'initialEntities': [
          {
            'id': 'szh',
            'displayName': '沈昭华',
            'aliases': ['昭华仙子'],
            'templateId': 'brainwashed_female',
            'initialState': {'xno_depth': 90, 'xno_layer': 2},
          },
          {
            'id': 'lql',
            'displayName': '洛青鸾',
            'aliases': ['青鸾'],
            'templateId': 'brainwashed_female',
          },
        ],
        'entityDiscovery': {'enabled': true, 'defaultTemplateId': 'brainwashed_female', 'maxAutoEntities': 24},
        'migrations': [
          {
            'id': 'legacy-xno-to-szh-v1',
            'targetEntityId': 'szh',
            'fieldMap': {'xno_depth': 'xno_depth', 'xno_layer': 'xno_layer'},
          },
        ],
        'template': '<details><summary>状态</summary>{{entitysections::brainwashed_female}}</details>',
      },
    },
  },
};

void main() {
  group('v89 instance key codec', () {
    test('entityFieldKey 生成 entity.<id>.<field>', () {
      expect(
        TrackerRuntime.entityFieldKey('szh', 'xno_layer'),
        'entity.szh.xno_layer',
      );
      expect(
        TrackerRuntime.entityFieldKey('dyn_0001', 'xno_cloth'),
        'entity.dyn_0001.xno_cloth',
      );
    });

    test('parseEntityFieldKey 正确解析（含下划线的 id/field）', () {
      final parsed = TrackerRuntime.parseEntityFieldKey('entity.szh.xno_layer');
      expect(parsed, isNotNull);
      expect(parsed!.$1, 'szh');
      expect(parsed.$2, 'xno_layer');
      final parsed2 = TrackerRuntime.parseEntityFieldKey(
        'entity.dyn_0001.xno_cloth',
      );
      expect(parsed2!.$1, 'dyn_0001');
      expect(parsed2.$2, 'xno_cloth');
    });

    test('非实体 key 返回 null', () {
      expect(TrackerRuntime.parseEntityFieldKey('xno_layer'), isNull);
      expect(TrackerRuntime.parseEntityFieldKey('entity.'), isNull);
      expect(TrackerRuntime.parseEntityFieldKey('entity.abc'), isNull);
    });
  });

  group('v89 实体卡配置解析', () {
    test('schemaVersion 2 实体卡解析成功', () {
      final config = TrackerConfig.fromCardJson(_entityCard);
      expect(config.isEntityCard, isTrue);
      expect(config.entityTemplates.length, 1);
      expect(config.entityTemplates['brainwashed_female']!.stateSchema.length, 2);
      expect(config.initialEntities.length, 2);
      expect(config.initialEntities[0].id, 'szh');
      expect(config.initialEntities[0].initialState['xno_depth'], 90);
      expect(config.initialEntities[1].id, 'lql');
      expect(config.entityDiscovery.enabled, isTrue);
      expect(config.entityMigrations.length, 1);
    });

    test('字符串 schemaVersion "1.0" 兼容（旧卡不崩）', () {
      final legacy = {
        'data': {
          'extensions': {
            'tracker': {
              'schemaVersion': '1.0',
              'stateSchema': {'energy': {'type': 'number', 'label': '体力'}},
              'initialState': {'energy': 80},
            },
          },
        },
      };
      final config = TrackerConfig.fromCardJson(legacy);
      expect(config.isEntityCard, isFalse);
      expect(config.isEnabled, isTrue);
    });
  });

  group('v89 实体卡状态指令（formatEntityTrackerInstruction）', () {
    test('包含模板字段定义与活跃实体列表', () {
      final config = TrackerConfig.fromCardJson(_entityCard);
      final registry = TrackerRuntime.decodeEntityRegistry(null);
      final registryJson = TrackerRuntime.encodeEntityRegistry({
        ...registry,
        'entities': [
          {'id': 'szh', 'templateId': 'brainwashed_female', 'displayName': '沈昭华', 'aliases': ['昭华仙子'], 'order': 0, 'source': 'preset'},
          {'id': 'lql', 'templateId': 'brainwashed_female', 'displayName': '洛青鸾', 'aliases': ['青鸾'], 'order': 1, 'source': 'preset'},
        ],
      });
      final text = TrackerRuntime.formatEntityTrackerInstruction(
        variables: {
          TrackerRuntime.kEntityRegistryKey: registryJson,
          'entity.szh.xno_depth': '90',
          'entity.szh.xno_layer': '2',
          'entity.lql.xno_depth': '0',
        },
        config: config,
      );
      expect(text, contains('field=xno_depth'));
      expect(text, contains('entityId=szh | name=沈昭华'));
      expect(text, contains('entityId=lql | name=洛青鸾'));
      expect(text, contains('xno_depth=90'));
      expect(text, contains('角色归属规则'));
      expect(text, contains('entities'));
      expect(text, contains('updates'));
    });
  });

  group('v89 envelope 元语言过滤', () {
    test('命中直接拒绝词 → 判定为元语言', () {
      expect(TrackerRuntime.isMetaLanguageNarrative('本字段表示洗脑深度'), isTrue);
      expect(TrackerRuntime.isMetaLanguageNarrative('该字段更新为90'), isTrue);
      expect(TrackerRuntime.isMetaLanguageNarrative('状态值从2升至3'), isTrue);
      expect(TrackerRuntime.isMetaLanguageNarrative('tracker 输出 patch'), isTrue);
    });

    test('命中组合拒绝词 → 判定为元语言', () {
      expect(TrackerRuntime.isMetaLanguageNarrative('本轮认知增加一层'), isTrue);
      expect(TrackerRuntime.isMetaLanguageNarrative('数值变为90'), isTrue);
      expect(TrackerRuntime.isMetaLanguageNarrative('档位升至3'), isTrue);
    });

    test('正常剧情句不误杀', () {
      expect(TrackerRuntime.isMetaLanguageNarrative('她顺从地复述着刚被植入的新常识，眼神温顺'), isFalse);
      expect(TrackerRuntime.isMetaLanguageNarrative('衣带微松，领口半敞，她坦然迎上主人的目光'), isFalse);
      expect(TrackerRuntime.isMetaLanguageNarrative('她主动膝行贴近，薄纱下乳尖微微凸起'), isFalse);
    });
  });

  group('v89 实体分区渲染', () {
    test('renderEntitySections 按实体渲染分区并回退静态文案', () {
      final config = TrackerConfig.fromCardJson(_entityCard);
      final registryJson = TrackerRuntime.encodeEntityRegistry({
        'version': 1,
        'nextDynamicOrdinal': 1,
        'appliedMigrations': <String>[],
        'entities': [
          {'id': 'szh', 'templateId': 'brainwashed_female', 'displayName': '沈昭华', 'aliases': [], 'order': 0, 'source': 'preset'},
          {'id': 'dyn_0001', 'templateId': 'brainwashed_female', 'displayName': '顾清寒', 'aliases': [], 'order': 1, 'source': 'discovered'},
        ],
      });
      final sections = TrackerRuntime.renderEntitySections(
        cardJson: _entityCard,
        variables: {
          TrackerRuntime.kEntityRegistryKey: registryJson,
          'entity.szh.xno_depth': '90',
          'entity.szh.xno_layer': '2',
          'entity.dyn_0001.xno_depth': '5',
        },
        narrative: {
          'entity.szh.xno_depth': '她眼神温顺地跪伏在主人脚边。',
          'entity.dyn_0001.xno_depth': '本字段表示洗脑深度', // 元语言 → 回退
        },
        config: config,
        registry: TrackerRuntime.decodeEntityRegistry(registryJson),
      );
      expect(sections, isNotNull);
      expect(sections, contains('沈昭华'));
      expect(sections, contains('顾清寒'));
      expect(sections, contains('她眼神温顺地跪伏在主人脚边'));
      // 元语言 narrative 被过滤（不出现）
      expect(sections, isNot(contains('本字段表示洗脑深度')));
      // 回退静态文案（无 presentation 时为空/原值）
      expect(sections, contains('90'));
      expect(sections, contains('5'));
    });

    test('实体卡面板含 entitysections 插槽时整体渲染', () {
      final config = TrackerConfig.fromCardJson(_entityCard);
      final registryJson = TrackerRuntime.encodeEntityRegistry({
        'version': 1,
        'nextDynamicOrdinal': 1,
        'appliedMigrations': <String>[],
        'entities': [
          {'id': 'szh', 'templateId': 'brainwashed_female', 'displayName': '沈昭华', 'aliases': [], 'order': 0, 'source': 'preset'},
        ],
      });
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: _entityCard,
        variables: {
          TrackerRuntime.kEntityRegistryKey: registryJson,
          'entity.szh.xno_depth': '90',
          'entity.szh.xno_layer': '2',
        },
      );
      expect(html, isNotNull);
      expect(html, contains('沈昭华'));
      expect(html, contains('90'));
      expect(html, isNot(contains('{{entitysections')));
    });
  });
}
