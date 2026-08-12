// v86 回归测试：长回复中段状态事件被裁掉（v85 xno_layer 不更新根因）
//  - 常规单轮正文完整传入裁判，不再按 3000 字软阈值+关键词筛选裁剪
//  - 超 hard budget 时按段落均匀采样（非关键词驱动），中段事件
//    有同等机会保留；首尾保底不变
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

const Map<String, dynamic> _cardJson = {
  'data': {
    'extensions': {
      'tracker': {
        'schemaVersion': '1.0',
        'stateSchema': {
          'xno_layer': {
            'type': 'number',
            'label': '常识改写',
            'min': 0,
            'max': 100,
            'updatePolicy': {
              'mode': 'conservative',
              'qualitativeDeltas': {'一点': 1, '深度洗脑': 1, '认知灌输': 1},
              'maxAutoDeltaPerTurn': 1,
              'semanticHints': {
                'meaning': '认知被改写、灌输、替换、重构时上升',
                'positiveSignals': ['深度洗脑', '认知灌输'],
                'negativeSignals': ['清醒剂', '记忆修正'],
                'neutralSignals': ['普通对话'],
              },
            },
          },
          'xno_cloth': {
            'type': 'string',
            'label': '服装状态',
            'allowCustomValues': true,
            'updatePolicy': {
              'semanticHints': {
                'meaning': '当前衣着状态的短文本描述。',
                'positiveSignals': ['明确穿上、换上、脱下、撕裂、弄脏或恢复衣物，且结果明确'],
                'negativeSignals': ['仅提及、触碰、注视衣物而没有状态变化'],
                'neutralSignals': ['本轮没有衣着信息'],
              },
            },
          },
        },
        'initialState': {'xno_layer': 2, 'xno_cloth': '松散半敞'},
      },
    },
  },
};

TrackerConfig _config() => TrackerConfig.fromCardJson(_cardJson);

void main() {
  group('v86 selectRelevantText 常规单轮完整传入', () {
    test('超过旧 3000 阈值但 ≤8000 的回复完整返回（事件中段不被裁）', () {
      // 模拟真实 NSFW 长回复：>3000 字（旧软阈值）但 <8000（v86 hard budget）
      final head = '她跪坐在蒲团上，睫毛低垂。';
      final event1 = '你继续施展洗脑，她的眼神逐渐涣散，思维被一点点重塑，认知已被扭曲得更深。';
      final event2 = '她顺从地套上那件薄纱，肌肤若隐若现。';
      final filler1 = List.filled(50, '她维持着打坐的姿势，洞府内檀香袅袅，烛火轻轻摇曳，她的呼吸平缓而规律，偶尔有风吹动发丝。').join('\n');
      final filler2 = List.filled(50, '殿外传来隐约的水声，天色渐暗，她的手指无意识地绞着衣角，脸上浮起一层薄薄的红晕。').join('\n');
      final tail = '最后，她缓缓睁开眼睛，目光里多了一层说不清的顺从。';
      final longText = '$head\n$filler1\n$event1\n$filler2\n$event2\n$tail';
      expect(longText.length, greaterThan(3000), reason: '前置条件：必须超过旧 3000 字软阈值');

      final result = TrackerRuntime.selectRelevantText(
        longText,
        config: _config(),
        maxChars: 8000, // chat_service 当前 hard budget
      );
      // 完整返回，一个字节都不裁——常规单轮正文全部进入裁判
      expect(result, longText);
      // 两个关键事件都在（旧实现：无关键词命中 → 中段被裁，事件丢失）
      expect(result, contains('思维被一点点重塑'));
      expect(result, contains('套上那件薄纱'));
      // 首尾完整
      expect(result, contains(head));
      expect(result, contains(tail));
    });

    test('意图句（将来时/请求）短文本不裁剪原样返回', () {
      const intentText = '她的常识改写会加深，让她穿这种衣服。';
      final result = TrackerRuntime.selectRelevantText(
        intentText,
        config: _config(),
      );
      expect(result, intentText);
    });
  });

  group('v86 selectRelevantText 超 hard budget 均匀采样', () {
    test('超预算时首尾保底 + 中段非关键词事件有机会保留', () {
      // 构造确定性场景：中段 8 段、每段恰好 20 字；预算约容纳 4 段
      // → stride=2 → 保留索引 0,2,4,6；事件放在索引 2 和 4（必命中）
      String pad(String s, [int n = 20]) => s + '啊' * (n - s.length);
      final middle = <String>[
        pad('她站在门口。'), // 0 保留
        pad('墙角的香炉升起袅袅青烟。'),
        pad('她的思维被重塑，认知已在改写。'), // 2 保留（无任何关键词）
        pad('窗外的梧桐叶轻轻摆动。'),
        pad('她顺从地穿上那件衣服。'), // 4 保留（无关键词）        pad('桌上的烛火跳了一下。'),
        pad('她的呼吸逐渐平稳。'), // 6 保留
        pad('远处的钟声敲响。'),
      ];
      final longText =
          '开头：她跪坐在蒲团上。\n${middle.join('\n')}\n结尾：她缓缓睁开眼睛。';
      // budget = maxChars - head(11) - tail(10) - 40 ≈ 81 → 约 4 段 → stride=2
      final result = TrackerRuntime.selectRelevantText(
        longText,
        config: _config(),
        maxChars: 142,
      );
      expect(result.length, lessThanOrEqualTo(142));
      // 首尾保底（v82 不变）
      expect(result, contains('她跪坐在蒲团上'));
      expect(result, contains('她缓缓睁开眼睛'));
      // 非关键词中段事件被保留（旧实现：关键词驱动 → 确定性删除）
      expect(result, contains('思维被重塑'));
      expect(result, contains('穿上那件衣服'));
    });

    test('超预算时采样受长度约束且不崩溃（大量段落）', () {
      final head = '她跪坐下来。';
      final tail = '她站了起来。';
      final text = '$head\n' +
          List.filled(500, '普通的过渡描写，她维持着姿势，檀香缭绕，烛火摇曳，呼吸平稳。').join('\n') +
          '\n$tail';
      final result = TrackerRuntime.selectRelevantText(
        text,
        config: _config(),
        maxChars: 2000,
      );
      expect(result.length, lessThanOrEqualTo(2000));
      expect(result, isNotEmpty);
      // 首尾保底仍生效（v82 不变）
      expect(result, contains('她跪坐下来'));
      expect(result, contains('她站了起来'));
    });
  });
}
