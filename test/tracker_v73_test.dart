// v73 回归测试：状态一致性收口——
//  - state 存在时忽略 patch.add（最终状态一次性保存不叠加）
//  - 会话独立 turn（不同 sessionId 互不影响）
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
          },
          'ml_status': {
            'type': 'string',
            'label': '当前状态',
          },
        },
        'initialState': {'ml_like': 20, 'ml_status': '警戒'},
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_cardJson);

void main() {
  group('v73 裁判 state 优先级', () {
    test('state 存在时完全忽略 patch.add（不叠加）', () {
      const text = '```json\n'
          '{"state":{"ml_like":30},'
          '"patch":{"add":{"ml_like":5}},'
          '"narrative":{},"consequence":{}}\n'
          '```';
      // extractFinalState 提取 state（30）
      final state = TrackerRuntime.extractFinalState(text, _config());
      expect(state['ml_like'], '30');
      // extractPatch 提取 patch（add ml_like=5）
      final patch = TrackerRuntime.extractPatch(text);
      expect(patch.addValues['ml_like'], 5);
      // v73 逻辑：state 存在时以 state 为 set、addValues 清空
      final finalPatch = StatePatch(
        setValues: state,
        addValues: const {},
        protocolDetected: true,
      );
      // 应用到候选 25 → 结果 30（不是 35）
      final next = TrackerRuntime.applyPatchToVariables(
        variables: {'ml_like': '25'},
        patch: finalPatch,
        config: _config(),
      );
      expect(next['ml_like'], '30');
    });

    test('无 state 时仍用增量 patch（兼容）', () {
      const text = '{"patch":{"set":{},"add":{"ml_like":5}}}';
      final state = TrackerRuntime.extractFinalState(text, _config());
      expect(state, isEmpty);
      final patch = TrackerRuntime.extractPatch(text);
      expect(patch.addValues['ml_like'], 5);
      final next = TrackerRuntime.applyPatchToVariables(
        variables: {'ml_like': '25'},
        patch: patch,
        config: _config(),
      );
      expect(next['ml_like'], '30');
    });
  });

  group('v73 会话独立令牌', () {
    test('不同会话各自计数互不影响', () {
      // 模拟 _trackerJudgeTurns 逻辑：每会话独立 Map
      final turns = <String, int>{};
      int next(String sessionId) {
        final n = (turns[sessionId] ?? 0) + 1;
        turns[sessionId] = n;
        return n;
      }

      int current(String sessionId) => turns[sessionId] ?? 0;

      // 会话 A 第一轮
      final a1 = next('sessionA');
      expect(a1, 1);
      // 会话 B 第一轮（不应影响 A）
      final b1 = next('sessionB');
      expect(b1, 1);
      // 会话 A 裁判返回时判断是否过期
      expect(a1 == current('sessionA'), isTrue, reason: 'A 仍是当前轮');
      // 会话 A 第二轮
      final a2 = next('sessionA');
      expect(a2, 2);
      // A 的旧裁判（turn=1）过期，但 B 的裁判不受影响
      expect(a1 == current('sessionA'), isFalse, reason: 'A 旧裁判过期');
      expect(b1 == current('sessionB'), isTrue, reason: 'B 裁判仍是当前轮');
    });
  });

  group('v73 上下文估算协议尾部', () {
    test('快速模式估算用内联协议尾部', () {
      final suffix = TrackerRuntime.kInlineTrackerProtocolSuffix;
      expect(suffix, contains('<TRACKER_UPDATE>'));
    });

    test('后台/严格模式估算用只输出正文尾部', () {
      final suffix = TrackerRuntime.kStoryOnlySuffix;
      expect(suffix, contains('只输出剧情正文'));
      expect(suffix, contains('状态判断由独立裁判完成'));
    });

    test('两种尾部长度差异显著（估算精确性）', () {
      final inline = TrackerRuntime.kInlineTrackerProtocolSuffix.length;
      final story = TrackerRuntime.kStoryOnlySuffix.length;
      // 内联协议远长于只输出正文指令
      expect(inline, greaterThan(story + 100));
    });
  });
}
