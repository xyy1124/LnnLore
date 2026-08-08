// v66 回归测试：状态更新三档模式——
//  - TrackerUpdateMode 枚举与 AppSettings 默认值（quick）
//  - 主模型 narrative 提取（_processAssistantOutput 链路：extractNarrative
//    + canonicalizeNarrative 规范化）
//  - selectRelevantText 正文裁剪（裁判输入压缩）
//  - 协议后缀含 narrative 要求
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/data/app_settings.dart';
import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

const Map<String, dynamic> _cardJson = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': '1.0',
        'stateSchema': {
          'ml_like': {
            'type': 'number',
            'label': '好感度',
            'min': 0,
            'max': 100,
            'aliases': ['好感', '亲密度'],
            'updatePolicy': {
              'mode': 'conservative',
              'qualitativeDeltas': {'一点': 1, '明显': 5, '大幅': 10},
              'maxAutoDeltaPerTurn': 10,
              'semanticHints': {
                'meaning': '角色对用户的亲近程度',
                'positiveSignals': ['帮助', '礼物', '守护'],
                'negativeSignals': ['欺骗', '背叛'],
                'neutralSignals': ['闲聊', '心理描写'],
              },
            },
          },
          'ml_seal': {
            'type': 'string',
            'label': '封印松动',
            'presentation': {
              'states': {
                '稳固': {
                  'title': '稳固',
                  'color': '#90A4AE',
                  'text': '封印完好。',
                },
                '松动': {
                  'title': '松动',
                  'color': '#FFA726',
                  'text': '封印开始松动。',
                },
              },
            },
          },
        },
        'initialState': {'ml_like': 20, 'ml_seal': '稳固'},
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_cardJson);

void main() {
  group('v66 TrackerUpdateMode 设置', () {
    test('默认值为 quick（快速单次 API）', () {
      expect(appSettingsNotifier.value.trackerUpdateMode,
          TrackerUpdateMode.quick);
    });

    test('枚举三个档位与标签', () {
      expect(TrackerUpdateMode.values.length, 3);
      expect(TrackerUpdateMode.quick.label, contains('快速'));
      expect(TrackerUpdateMode.background.label, contains('后台'));
      expect(TrackerUpdateMode.strict.label, contains('严格'));
    });

    test('updateAppSettings 可切换档位', () {
      // 测试环境 StorageService 未初始化——直接更新 notifier 验证 copyWith
      // 链路（持久化由 AppSettingsService 负责，非本测试范围）
      appSettingsNotifier.value = appSettingsNotifier.value.copyWith(
        trackerUpdateMode: TrackerUpdateMode.background,
      );
      expect(
        appSettingsNotifier.value.trackerUpdateMode,
        TrackerUpdateMode.background,
      );
      appSettingsNotifier.value = appSettingsNotifier.value.copyWith(
        trackerUpdateMode: TrackerUpdateMode.quick,
      );
      expect(appSettingsNotifier.value.trackerUpdateMode,
          TrackerUpdateMode.quick);
    });
  });

  group('v66 协议含 narrative', () {
    test('kTrackerProtocolSuffix 要求主模型输出 narrative', () {
      expect(TrackerRuntime.kTrackerProtocolSuffix, contains('narrative'));
      expect(TrackerRuntime.kTrackerProtocolSuffix, contains('"reply"'));
      expect(TrackerRuntime.kTrackerProtocolSuffix, contains('"patch"'));
      expect(TrackerRuntime.kTrackerProtocolSuffix, contains('字段key'));
    });
  });

  group('v66 extractNarrative 主模型链路', () {
    test('主模型输出 {reply, patch, narrative} 提取并规范化', () {
      const text = '```json\n'
          '{"reply":"剧情正文","patch":{"set":{},"add":{"好感度":2}},'
          '"narrative":{"好感度":"她虽然保持警惕，但开始接受你的帮助。"}}\n'
          '```';
      final raw = TrackerRuntime.extractNarrative(text);
      // 原始提取：key 是中文 label
      expect(raw.containsKey('好感度'), isTrue);
      // 规范化后映射回真实 key
      final canonical = TrackerRuntime.canonicalizeNarrative(raw, _config());
      expect(canonical.containsKey('ml_like'), isTrue);
      expect(canonical['ml_like'], '她虽然保持警惕，但开始接受你的帮助。');
    });

    test('narrative 用别名也能映射', () {
      final canonical = TrackerRuntime.canonicalizeNarrative(
        {'亲密度': '关系更近了一步。'},
        _config(),
      );
      expect(canonical.containsKey('ml_like'), isTrue);
    });

    test('空 narrative / 无法识别 key 被丢弃', () {
      final canonical = TrackerRuntime.canonicalizeNarrative(
        {'不存在字段': '无效'},
        _config(),
      );
      expect(canonical, isEmpty);
    });
  });

  group('v66 selectRelevantText 正文裁剪', () {
    test('短文本原样返回', () {
      final config = _config();
      final text = '她看着你，眼神有些复杂。';
      expect(
        TrackerRuntime.selectRelevantText(text, config: config),
        text,
      );
    });

    test('超长文本保留命中关键词段落与首尾', () {
      final config = _config();
      final buffer = StringBuffer();
      for (var i = 0; i < 200; i++) {
        buffer.write('第${i}段：她默默整理着房间里的书卷。\n');
      }
      // 中间插入命中 positiveSignals 的段落（"帮助"在 positiveSignals 中）
      buffer.write('你帮助她修好了漏水的屋顶，她愣了一下。\n');
      for (var i = 0; i < 200; i++) {
        buffer.write('第${i + 200}段：窗外的风轻轻吹过。\n');
      }
      final trimmed = TrackerRuntime.selectRelevantText(
        buffer.toString(),
        config: config,
        maxChars: 3500,
      );
      expect(trimmed.length, lessThanOrEqualTo(3500));
      // 关键词段落被保留（"帮助"在 positiveSignals 中）
      expect(trimmed, contains('修好了漏水的屋顶'));
      // 首段保留
      expect(trimmed, contains('她默默整理'));
    });

    test('无关键词时保留开头', () {
      final config = _config();
      final text = List.filled(300, '无意义内容行').join('\n');
      final trimmed =
          TrackerRuntime.selectRelevantText(text, config: config);
      expect(trimmed.length, lessThanOrEqualTo(3500));
      expect(trimmed, contains('无意义内容行'));
    });
  });
}
