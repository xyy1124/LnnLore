// v70 回归测试：单一写入者架构——
//  - <TRACKER_UPDATE> 标记协议（正文在标记外，不塞进 JSON reply）
//  - extractTrackerUpdateBlock / extractPatch 支持标记
//  - kStoryOnlySuffix（后台/严格模式主模型只输出正文）
//  - extractFinalState（裁判可选最终状态）
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
          'ml_like': {
            'type': 'number',
            'label': '好感度',
            'min': 0,
            'max': 100,
            'aliases': ['好感'],
          },
          'ml_status': {
            'type': 'string',
            'label': '当前状态',
            'presentation': {
              'states': {
                '警戒': {'title': '警戒', 'color': '#78909C', 'text': '她保持距离。'},
              },
            },
          },
        },
        'initialState': {'ml_like': 20, 'ml_status': '警戒'},
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_cardJson);

void main() {
  group('v70 <TRACKER_UPDATE> 标记协议', () {
    test('正文在标记外、协议在标记内', () {
      const text = '她看着你，微微后退了一步。\n\n'
          '<TRACKER_UPDATE>\n'
          '{\n'
          '  "patch": {\n'
          '    "set": {},\n'
          '    "add": {"ml_like": 2}\n'
          '  },\n'
          '  "narrative": {"ml_like": "她稍微降低了戒备。"},\n'
          '  "consequence": {"ml_like": "下一轮应表现出有限但明确的信任。"}\n'
          '}\n'
          '</TRACKER_UPDATE>';
      final (markerJson, displayText) =
          TrackerRuntime.extractTrackerUpdateBlock(text);
      expect(markerJson, isNotNull);
      expect(displayText, '她看着你，微微后退了一步。');
      expect(displayText.contains('TRACKER_UPDATE'), isFalse);
      final decoded = jsonDecode(markerJson!);
      expect(decoded['patch'], isA<Map<String, dynamic>>());
    });

    test('extractPatch 从标记提取 patch（add 增量）', () {
      const text = '正文内容\n'
          '<TRACKER_UPDATE>\n'
          '{"patch":{"set":{},"add":{"好感度":2}}}\n'
          '</TRACKER_UPDATE>';
      final patch = TrackerRuntime.extractPatch(text);
      expect(patch.protocolDetected, isTrue);
      expect(patch.addValues['好感度'], 2);
    });

    test('extractPatch 从标记提取 patch（set 字符串）', () {
      const text = '正文\n'
          '<TRACKER_UPDATE>\n'
          '{"patch":{"set":{"当前状态":"压制中"},"add":{}}}\n'
          '</TRACKER_UPDATE>';
      final patch = TrackerRuntime.extractPatch(text);
      expect(patch.setValues['当前状态'], '压制中');
    });

    test('无标记时回退 JSON 块解析（旧协议兼容）', () {
      const text = '```json\n{"reply":"正文","patch":{"set":{},"add":{"ml_like":3}}}\n```';
      final patch = TrackerRuntime.extractPatch(text);
      expect(patch.protocolDetected, isTrue);
      expect(patch.addValues['ml_like'], 3);
      expect(patch.reply, '正文');
    });

    test('标记内非法 JSON 时正文仍完整（只丢状态）', () {
      const text = '完整剧情正文\n'
          '<TRACKER_UPDATE>\n'
          '{"patch":{"set":{},"add":{"ml_like":  （截断\n'
          '</TRACKER_UPDATE>';
      final (_, displayText) = TrackerRuntime.extractTrackerUpdateBlock(text);
      expect(displayText, '完整剧情正文');
      // 标记内 JSON 解析失败 → extractPatch 回退（不崩）
      final patch = TrackerRuntime.extractPatch(text);
      expect(patch.protocolDetected, isFalse);
    });
  });

  group('v70 分模式协议', () {
    test('kInlineTrackerProtocolSuffix 是快速模式协议（含标记）', () {
      final suffix = TrackerRuntime.kInlineTrackerProtocolSuffix;
      expect(suffix, contains('<TRACKER_UPDATE>'));
      expect(suffix, contains('</TRACKER_UPDATE>'));
      expect(suffix, contains('禁止输出 <details>'));
    });

    test('kStoryOnlySuffix 是后台/严格模式指令（只输出正文）', () {
      final suffix = TrackerRuntime.kStoryOnlySuffix;
      expect(suffix, contains('只输出剧情正文'));
      expect(suffix, contains('禁止输出 JSON、STATE、HTML、状态栏或状态面板'));
      expect(suffix, contains('状态判断由独立裁判完成'));
    });
  });

  group('v70 裁判最终状态', () {
    test('extractFinalState 提取 state 字段并规范化 key', () {
      const text = '```json\n'
          '{"state":{"好感度":27,"当前状态":"压制中"},'
          '"narrative":{},"consequence":{}}\n'
          '```';
      final state = TrackerRuntime.extractFinalState(text, _config());
      expect(state['ml_like'], '27');
      expect(state['ml_status'], '压制中');
    });

    test('无 state 字段返回空', () {
      const text = '{"patch":{"set":{},"add":{}}}';
      expect(TrackerRuntime.extractFinalState(text, _config()), isEmpty);
    });

    test('state 值经 reducer 后 clamp（裸 JSON 也支持）', () {
      const text = '{"state":{"ml_like":999}}';
      final state = TrackerRuntime.extractFinalState(text, _config());
      expect(state['ml_like'], '999');
      // reduce 时会被 clamp 到 max=100
      final next = TrackerRuntime.reduce(
        current: {'ml_like': '20'},
        patch: StatePatch(setValues: state),
        config: _config(),
      );
      expect(next['ml_like'], 100);
    });
  });
}
