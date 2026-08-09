// v78 回归测试：tracker 数值修复——
//  - reduce 中 set 与 add 同字段不双计（v73 只修了裁判 finalState 路径，
//    快速模式主模型 marker 内 {"set":30,"add":5} 会双计成 35）
//  - number 字段拒绝非数字 set 值（此前宽松保留会污染变量表，
//    后续 add/百分比/进度条全部失效且不自愈）
//  - stageInfo 越界双向兜底（此前无匹配一律取最后一段，
//    数值低于首段 gte 时阶段标题/描述完全颠倒）
//  - 快速模式 <TRACKER_UPDATE> 标记前正文的残留清洗能力（extract
//    必须能剥 JSON 协议块 / setvar 宏——_processAssistantOutput 的
//    marker 路径 v78 起复用 extract 清洗后再入库）
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/chat_display_sanitizer.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

TrackerConfig _config() {
  return TrackerConfig(
    schemaVersion: 1,
    stateSchema: {
      'energy': const TrackerFieldSchema(
        type: 'number',
        label: '体力',
        min: 0,
        max: 100,
      ),
      'relationship': const TrackerFieldSchema(
        type: 'number',
        label: '关系',
        min: -100,
        max: 100,
      ),
    },
    initialState: {
      'energy': 80,
      'relationship': 0,
    },
    uiOrder: ['energy', 'relationship'],
  );
}

void main() {
  group('v78 reduce set+add 同字段不双计', () {
    test('set 与 add 同时出现时只按 set', () {
      final config = _config();
      final result = TrackerRuntime.reduce(
        current: {'energy': 20},
        patch: StatePatch(
          setValues: {'energy': 30},
          addValues: {'energy': 5},
        ),
        config: config,
      );
      expect(result['energy'], 30); // 不是 35
    });

    test('不同字段 set 与 add 互不影响', () {
      final config = _config();
      final result = TrackerRuntime.reduce(
        current: {'energy': 20, 'relationship': 0},
        patch: StatePatch(
          setValues: {'energy': 30},
          addValues: {'relationship': 5},
        ),
        config: config,
      );
      expect(result['energy'], 30);
      expect(result['relationship'], 5);
    });
  });

  group('v78 number 字段拒绝非数字 set 值', () {
    test('非数字值被拒绝，保持原值', () {
      final config = _config();
      final result = TrackerRuntime.reduce(
        current: {'energy': 20},
        patch: StatePatch(setValues: {'energy': '很多'}),
        config: config,
      );
      expect(result['energy'], 20);
    });

    test('合法数字 set 正常写入', () {
      final config = _config();
      final result = TrackerRuntime.reduce(
        current: {'energy': 20},
        patch: StatePatch(setValues: {'energy': 45}),
        config: config,
      );
      expect(result['energy'], 45);
    });
  });

  group('v78 stageInfo 越界双向兜底', () {
    TrackerConfig rangedConfig() {
      return TrackerConfig(
        schemaVersion: 1,
        stateSchema: {
          'dld': const TrackerFieldSchema(
            type: 'number',
            label: '堕落',
            min: 0,
            max: 100,
            presentation: TrackerFieldPresentation(ranges: [
              TrackerRangeDescription(gte: 1, lt: 40, title: '初期'),
              TrackerRangeDescription(gte: 40, lt: 80, title: '中期'),
              TrackerRangeDescription(gte: 80, title: '后期'),
            ]),
          ),
        },
        initialState: {'dld': 0},
        uiOrder: ['dld'],
      );
    }

    test('低于所有区间下限取第一段（不颠倒）', () {
      final info = TrackerRuntime.stageInfo('dld', 0, rangedConfig());
      expect(info, isNotNull);
      expect(info!.title, '初期');
    });

    test('高于所有区间上限取最后一段', () {
      final info = TrackerRuntime.stageInfo('dld', 90, rangedConfig());
      expect(info, isNotNull);
      expect(info!.title, '后期');
    });

    test('区间内正常匹配', () {
      final info = TrackerRuntime.stageInfo('dld', 50, rangedConfig());
      expect(info, isNotNull);
      expect(info!.title, '中期');
    });
  });

  group('v78 marker 前缀残留清洗能力', () {
    test('extract 拆解标记前正文中的旧 JSON 协议块（reply 提取、patch 不残留）', () {
      final prefix =
          '正文内容 {"reply":"不应入库的 JSON 正文","patch":{"add":{"a":1}}}';
      final extracted = ChatDisplaySanitizer.extract(prefix);
      // JSON 协议块被拆解：patch 键与花括号 JSON 形态不残留正文，
      // reply 按协议语义提取为正文
      expect(extracted.displayText, isNot(contains('"patch"')));
      expect(extracted.displayText, isNot(contains('"add"')));
      expect(extracted.displayText, contains('正文内容'));
      expect(extracted.displayText, contains('不应入库的 JSON 正文'));
    });

    test('extract 剥离 {{setvar::}} 宏', () {
      final prefix = '正文内容 {{setvar::体力::90}}';
      final extracted = ChatDisplaySanitizer.extract(prefix);
      expect(extracted.displayText, isNot(contains('setvar')));
      expect(extracted.displayText, contains('正文内容'));
    });
  });
}
