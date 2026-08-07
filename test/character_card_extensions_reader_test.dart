import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/character_card_extensions_reader.dart';
import 'package:pocket_inn/services/regex_script_service.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

/// v46 回归：真实手机导入链路下卡 JSON 的运行时类型可能与测试构造的
/// 标准 `Map<String, dynamic>` 不同（如 `Map<dynamic, dynamic>`、顶层
/// 已展开的 data 对象等）。统一读取器 + 放宽查找必须保证：
/// - TrackerConfig 仍能解析（旁白/状态栏不失效）
/// - StatusFallback 模板仍能读到（不静默降级统一内置面板）
/// - 模板渲染不依赖 tracker 是否解析成功
void main() {
  Map<String, dynamic> cardWithTracker() => {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': {
          'name': '测试角色',
          'extensions': {
            'regex_scripts': [
              {
                'scriptName': 'StatusFallback',
                'replaceString':
                    '<div>烙印值：{{getvar::yw_brand}}/100</div>',
              },
            ],
            'tracker': {
              'stateSchema': {
                'yw_brand': {
                  'type': 'number',
                  'label': '烙印值',
                  'min': 0,
                  'max': 100,
                },
              },
              'initialState': {'yw_brand': 20},
            },
          },
        },
      };

  group('CharacterCardExtensionsReader（统一读取器）', () {
    test('标准 Map<String, dynamic> 结构', () {
      final card = cardWithTracker();
      final tracker = CharacterCardExtensionsReader.tracker(card);
      expect(tracker, isNotNull);
      expect(tracker!['stateSchema'], isA<Map<String, dynamic>>());
    });

    test('运行时类型为 Map<dynamic, dynamic> 也能读取（真实导入链路变体）', () {
      // 模拟 jsonDecode 后经过 Map.from / 其他转换导致运行时类型
      // 不再是 Map<String, dynamic> 的情况——统一读取器必须兼容
      final card = <dynamic, dynamic>{
        'spec': 'chara_card_v2',
        'data': <dynamic, dynamic>{
          'name': '测试角色',
          'extensions': <dynamic, dynamic>{
            'regex_scripts': <dynamic>[
              <dynamic, dynamic>{
                'scriptName': 'StatusFallback',
                'replaceString': '<div>烙印值：{{getvar::yw_brand}}/100</div>',
              },
            ],
            'tracker': <dynamic, dynamic>{
              'stateSchema': <dynamic, dynamic>{
                'yw_brand': <dynamic, dynamic>{
                  'type': 'number',
                  'label': '烙印值',
                  'min': 0,
                  'max': 100,
                },
              },
              'initialState': <dynamic, dynamic>{'yw_brand': 20},
            },
          },
        },
      };
      final asStringMap = Map<String, dynamic>.from(card);
      final tracker = CharacterCardExtensionsReader.tracker(asStringMap);
      expect(tracker, isNotNull);
      expect(tracker!['stateSchema'], isNotNull);
    });

    test('调用方已传入展开后的 data 对象也能读取（顶层即 data 字段）', () {
      final expandedData = {
        'name': '测试角色',
        'extensions': {
          'regex_scripts': [
            {
              'scriptName': 'StatusFallback',
              'replaceString': '<div>烙印值：{{getvar::yw_brand}}/100</div>',
            },
          ],
          'tracker': {
            'stateSchema': {
              'yw_brand': {
                'type': 'number',
                'label': '烙印值',
                'min': 0,
                'max': 100,
              },
            },
            'initialState': {'yw_brand': 20},
          },
        },
      };
      final tracker = CharacterCardExtensionsReader.tracker(expandedData);
      expect(tracker, isNotNull);
    });

    test('无 extensions 返回 null 不崩溃', () {
      expect(CharacterCardExtensionsReader.tracker(null), isNull);
      expect(CharacterCardExtensionsReader.tracker({'data': {}}), isNull);
    });
  });

  group('TrackerConfig 兼容真实数据变体', () {
    test('Map<dynamic, dynamic> 变体仍能解析 tracker（旁白/状态栏不失效）', () {
      final card = <dynamic, dynamic>{
        'data': <dynamic, dynamic>{
          'extensions': <dynamic, dynamic>{
            'tracker': <dynamic, dynamic>{
              'stateSchema': <dynamic, dynamic>{
                'yw_brand': <dynamic, dynamic>{
                  'type': 'number',
                  'label': '烙印值',
                  'min': 0,
                  'max': 100,
                },
              },
              'initialState': <dynamic, dynamic>{'yw_brand': 20},
            },
          },
        },
      };
      final config = TrackerConfig.fromCardJson(
        Map<String, dynamic>.from(card),
      );
      expect(config.isEnabled, isTrue);
      expect(config.stateSchema['yw_brand']!.max, 100);
      expect(config.initialState['yw_brand'], 20);
    });

    test('展开后的 data 对象（顶层）也能解析 tracker', () {
      final config = TrackerConfig.fromCardJson({
        'name': '测试角色',
        'extensions': {
          'tracker': {
            'stateSchema': {
              'yw_brand': {
                'type': 'number',
                'label': '烙印值',
                'min': 0,
                'max': 100,
              },
            },
            'initialState': {'yw_brand': 20},
          },
        },
      });
      expect(config.isEnabled, isTrue);
      expect(config.stateSchema['yw_brand']!.max, 100);
    });

    test('schema 简写类型字符串仍兼容', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {'hp': 'number', 'name': 'string'},
            },
          },
        },
      });
      expect(config.stateSchema['hp']!.isNumber, isTrue);
    });
  });

  group('statusFallbackTemplate 放宽查找', () {
    test('脚本名大小写不敏感（statusfallback / StatusFallback）', () {
      final card = {
        'data': {
          'extensions': {
            'regex_scripts': [
              {'scriptName': 'statusfallback', 'replaceString': 'A'},
            ],
          },
        },
      };
      expect(TrackerRuntime.statusFallbackTemplate(card), 'A');
    });

    test('兼容 script_name / name 键名', () {
      final card = {
        'data': {
          'extensions': {
            'regex_scripts': [
              {'script_name': 'StatusFallback', 'replace_string': 'B'},
            ],
          },
        },
      };
      expect(TrackerRuntime.statusFallbackTemplate(card), 'B');
    });

    test('脚本名首尾空格容忍', () {
      final card = {
        'data': {
          'extensions': {
            'regex_scripts': [
              {'scriptName': ' StatusFallback ', 'replaceString': 'C'},
            ],
          },
        },
      };
      expect(TrackerRuntime.statusFallbackTemplate(card), 'C');
    });
  });

  group('renderStatusPanelHtml 模板优先于 tracker isEnabled', () {
    Map<String, dynamic> cardWithTemplateOnly(String template) => {
          'data': {
            'extensions': {
              'regex_scripts': [
                {'scriptName': 'StatusFallback', 'replaceString': template},
              ],
              // 无 tracker 声明：旧版卡/未升级卡的典型形态
            },
          },
        };

    test('无 tracker 声明但卡有 StatusFallback 模板 → 仍按模板渲染', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithTemplateOnly(
          '<div>烙印值：{{getvar::yw_brand}}/100</div>',
        ),
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('烙印值：30/100'));
    });

    test('无 tracker 声明且无模板 → null（不显示内置面板）', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: {
          'data': {'extensions': {'regex_scripts': []}},
        },
        variables: {},
      );
      expect(html, isNull);
    });

    test('有 tracker 声明但无模板 → 内置 chips 面板（原行为保留）', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: {
          'data': {
            'extensions': {
              'tracker': {
                'stateSchema': {
                  'yw_brand': {
                    'type': 'number',
                    'label': '烙印值',
                    'min': 0,
                    'max': 100,
                  },
                },
                'initialState': {'yw_brand': 20},
              },
            },
          },
        },
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('class="status-panel"'));
      expect(html, contains('烙印值：30/100'));
    });
  });

  group('RegexScriptService 统一读取器', () {
    test('Map<dynamic, dynamic> 变体仍能读取脚本', () {
      final card = <dynamic, dynamic>{
        'data': <dynamic, dynamic>{
          'extensions': <dynamic, dynamic>{
            'regex_scripts': <dynamic>[
              <dynamic, dynamic>{
                'scriptName': 'HideThink',
                'findRegex': 'test',
                'replaceString': '',
              },
            ],
          },
        },
      };
      final scripts = RegexScriptService.scriptsFromCharacterCard(
        Map<String, dynamic>.from(card),
      );
      expect(scripts, hasLength(1));
      expect(scripts.first.name, 'HideThink');
    });

    test('展开后的 data 对象（顶层）也能读取脚本', () {
      final scripts = RegexScriptService.scriptsFromCharacterCard({
        'extensions': {
          'regex_scripts': [
            {
              'scriptName': 'HideThink',
              'findRegex': 'test',
              'replaceString': '',
            },
          ],
        },
      });
      expect(scripts, hasLength(1));
    });

    test('空卡返回空列表', () {
      expect(RegexScriptService.scriptsFromCharacterCard(null), isEmpty);
      expect(
        RegexScriptService.scriptsFromCharacterCard({'data': {}}),
        isEmpty,
      );
    });
  });
}
