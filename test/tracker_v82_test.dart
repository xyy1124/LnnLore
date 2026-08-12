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

  group('v83 formatter 语义提示注入', () {
    const cardWithStringHints = {
      'data': {
        'extensions': {
          'tracker': {
            'schemaVersion': '1.0',
            'stateSchema': {
              'xno_cloth': {
                'type': 'string',
                'label': '服装状态',
                'allowCustomValues': true,
                'updatePolicy': {
                  'semanticHints': {
                    'meaning': '当前衣着状态的短文本描述。仅当本轮文本明确建立、改变、移除或恢复衣着状态时，依据文本证据概括新的当前状态并执行 set；新值是自由文本，不是固定枚举。没有明确证据时保持 current，不猜测。',
                    'positiveSignals': ['明确穿上、换上、脱下、撕裂、弄脏或恢复衣物，且结果明确'],
                    'negativeSignals': ['仅提及、触碰、注视衣物而没有状态变化'],
                    'neutralSignals': ['本轮没有衣着信息'],
                  },
                },
              },
            },
            'initialState': {'xno_cloth': '松散半敞'},
          },
        },
      },
    };

    test('string 字段带 semanticHints 时注入四类语义行', () {
      final config = TrackerConfig.fromCardJson(cardWithStringHints);
      final state = <String, dynamic>{'xno_cloth': '松散半敞'};
      final result = TrackerRuntime.formatTrackerInstruction(
        state: state,
        config: config,
      );
      expect(result, contains('meaning='));
      expect(result, contains('positive='));
      expect(result, contains('negative='));
      expect(result, contains('neutral='));
      expect(result, contains('自由文本'));
      expect(result, contains('保持 current'));
    });

    test('string 字段无 hints（旧卡）仍正常生成，不崩溃', () {
      final config = _config();
      final state = <String, dynamic>{'xno_cloth': '松散半敞'};
      final result = TrackerRuntime.formatTrackerInstruction(
        state: state,
        config: config,
      );
      expect(result, contains('key=xno_cloth'));
      expect(result, contains('type=string'));
      // 旧卡不注入任何 meaning/positive 行（不凭空生成激进信号）
      expect(result, isNot(contains('meaning=')));
    });

    test('超长 meaning 被截断（长度上限）', () {
      final longCard = {
        'data': {
          'extensions': {
            'tracker': {
              'schemaVersion': '1.0',
              'stateSchema': {
                'xno_cloth': {
                  'type': 'string',
                  'label': '服装状态',
                  'allowCustomValues': true,
                  'updatePolicy': {
                    'semanticHints': {
                      'meaning': '长' * 500,
                      'positiveSignals': ['短'],
                      'negativeSignals': ['短'],
                      'neutralSignals': ['短'],
                    },
                  },
                },
              },
              'initialState': {'xno_cloth': '松散半敞'},
            },
          },
        },
      };
      final config = TrackerConfig.fromCardJson(longCard);
      final result = TrackerRuntime.formatTrackerInstruction(
        state: <String, dynamic>{'xno_cloth': '松散半敞'},
        config: config,
      );
      final meaningLine = result.split('\n').firstWhere((l) => l.startsWith('  meaning='));
      expect(meaningLine.length, lessThanOrEqualTo(301 + '  meaning='.length));
      expect(meaningLine, endsWith('…'));
    });

    test('裁判指令不包含卡 PHI 原文（结构化 hints 注入，非原始 PHI）', () {
      // 卡 PHI 里的自由文本规则（历史遗留写法）不应被原样注入指令
      const phiText = '服装状态：换上新衣/穿回衣服→完整；衣襟扯松→松散半敞。';
      final cardWithPhi = {
        'data': {
          'post_history_instructions': phiText,
          'extensions': {
            'tracker': {
              'schemaVersion': '1.0',
              'stateSchema': {
                'xno_cloth': {
                  'type': 'string',
                  'label': '服装状态',
                  'allowCustomValues': true,
                  'updatePolicy': {
                    'semanticHints': {
                      'meaning': '当前衣着状态的短文本描述。',
                      'positiveSignals': ['明确换上、脱下衣物且结果明确'],
                      'negativeSignals': ['仅提及衣物无变化'],
                      'neutralSignals': ['本轮没有衣着信息'],
                    },
                  },
                },
              },
              'initialState': {'xno_cloth': '松散半敞'},
            },
          },
        },
      };
      final config = TrackerConfig.fromCardJson(cardWithPhi);
      final result = TrackerRuntime.formatTrackerInstruction(
        state: <String, dynamic>{'xno_cloth': '松散半敞'},
        config: config,
      );
      // 只注入结构化 hints；PHI 原文（箭头规则）不进入裁判指令
      expect(result, isNot(contains('换上新衣/穿回衣服→完整')));
      expect(result, contains('当前衣着状态的短文本描述'));
    });
  });
}
