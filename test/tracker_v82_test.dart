// v82 回归测试：状态栏修复——
//  - TRACKER_UPDATE 标签大小写不敏感 + 允许空白（协议块不再残留正文）
//  - 标记内坏 JSON 也剥离完整块（正文干净）
//  - selectRelevantText 无关键词命中时保留开头+结尾（状态事件不再被裁掉）
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

const Map<String, dynamic> _cardJson = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': '1.0',
        'stateSchema': {
          'xno_depth': {
            'type': 'number',
            'label': '洗脑深度',
            'min': 0,
            'max': 100,
            'updatePolicy': {
              'qualitativeDeltas': {'一点': 1, '稍微': 2, '明显': 5, '大幅': 10},
              'semanticHints': {
                'meaning': '洗脑深度',
                'positiveSignals': ['洗脑', '灌输', '精神压制'],
                'negativeSignals': ['清醒'],
                'neutralSignals': ['普通对话'],
              },
            },
          },
          'xno_cloth': {
            'type': 'string',
            'label': '服装状态',
            'allowCustomValues': true,
          },
        },
        'initialState': {'xno_depth': 90, 'xno_cloth': '松散半敞'},
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_cardJson);

void main() {
  group('v82 TRACKER_UPDATE 标签宽松解析', () {
    test('标准大写标签正常剥离', () {
      const text = '正文内容\n<TRACKER_UPDATE>\n{"patch":{"add":{"xno_depth":5}}}\n</TRACKER_UPDATE>';
      final (json, display) = TrackerRuntime.extractTrackerUpdateBlock(text);
      expect(json, isNotNull);
      expect(json, contains('xno_depth'));
      expect(display, '正文内容');
    });

    test('小写标签也能剥离（case-insensitive）', () {
      const text = '正文内容\n<tracker_update>\n{"patch":{"add":{"xno_depth":5}}}\n</tracker_update>';
      final (json, display) = TrackerRuntime.extractTrackerUpdateBlock(text);
      expect(json, isNotNull);
      expect(display, '正文内容');
    });

    test('标签带空白也能剥离（<TRACKER_UPDATE >）', () {
      const text = '正文内容\n<TRACKER_UPDATE >\n{"patch":{"add":{"xno_depth":5}}}\n</ TRACKER_UPDATE >';
      final (json, display) = TrackerRuntime.extractTrackerUpdateBlock(text);
      expect(json, isNotNull);
      expect(display, '正文内容');
    });

    test('标记内坏 JSON 也剥离完整块，正文干净', () {
      const text = '正文内容\n<TRACKER_UPDATE>\n{"patch":{"add":{"xno_depth":5,}\n</TRACKER_UPDATE>';
      final (json, display) = TrackerRuntime.extractTrackerUpdateBlock(text);
      expect(json, isNotNull);
      expect(display, '正文内容');
      // 坏 JSON 解析失败 → patch 为空但不报错
      final patch = TrackerRuntime.extractPatch(text);
      expect(patch.addValues, isEmpty);
      expect(patch.setValues, isEmpty);
    });

    test('无闭标签时保持原文本（兼容旧协议）', () {
      const text = '只有正文没有标签';
      final (json, display) = TrackerRuntime.extractTrackerUpdateBlock(text);
      expect(json, isNull);
      expect(display, text);
    });
  });

  group('v82 selectRelevantText 保留首尾', () {
    test('长正文无关键词命中时保留开头+结尾（不再只留首段）', () {
      // 构造 >3500 字符且不含任何 label/alias 的长正文
      final head = '她站在窗前，望着远处。';
      final tail = '最后，她缓缓起身，走向门外。';
      final middle = List.filled(200, '这一整段都是无关的风景描写与内心独白，云朵缓慢移动，檐角的铜铃被风轻轻吹动，偶尔有鸟雀掠过。').join('\n');
      final longText = '$head\n$middle\n$tail';
      expect(longText.length, greaterThan(3500));
      final result = TrackerRuntime.selectRelevantText(
        longText,
        config: _config(),
      );
      // 必须同时包含开头和结尾（旧实现只留首段 → 结尾丢失）
      expect(result, contains(head));
      expect(result, contains(tail));
    });

    test('长正文命中关键词段落按字符预算保留且结尾不丢', () {
      final head = '她坐在蒲团上。';
      final tail = '她终于睁开眼睛，目光清明。';
      final event1 = '你施展洗脑之术，她的眼神逐渐涣散。';
      final filler = List.filled(150, '这是漫长的过渡描写，洞府内檀香袅袅，壁上的烛火轻轻摇曳，她维持着打坐的姿势一动不动。').join('\n');
      final longText = '$head\n$event1\n$filler\n$tail';
      expect(longText.length, greaterThan(3500));
      final result = TrackerRuntime.selectRelevantText(
        longText,
        config: _config(),
      );
      // 关键词段落（含"洗脑"）保留 + 结尾保留
      expect(result, contains('洗脑'));
      expect(result, contains(tail));
      // 总长受 maxChars 约束
      expect(result.length, lessThanOrEqualTo(3500));
    });
  });
}
