import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/tracker_config.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

TrackerConfig _config() {
  return TrackerConfig(
    schemaVersion: 1,
    stateSchema: {
      'location': const TrackerFieldSchema(type: 'string', label: '地点'),
      'time': const TrackerFieldSchema(type: 'string', label: '时间'),
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
      'mood': const TrackerFieldSchema(type: 'string', label: '情绪'),
    },
    initialState: {
      'location': '旅馆',
      'time': '夜晚',
      'energy': 80,
      'relationship': 0,
      'mood': '平静',
    },
    uiOrder: ['location', 'time', 'energy', 'relationship', 'mood'],
  );
}

void main() {
  group('TrackerConfig.fromCardJson', () {
    test('读取 data.extensions.tracker 完整声明', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'schemaVersion': 1,
              'stateSchema': {
                'energy': {'type': 'number', 'label': '体力', 'min': 0, 'max': 100},
                'location': {'type': 'string', 'label': '地点'},
              },
              'initialState': {'energy': 80, 'location': '旅馆'},
              'uiHints': {
                'order': ['location', 'energy'],
              },
            },
          },
        },
      });
      expect(config.isEnabled, isTrue);
      expect(config.stateSchema['energy']!.type, 'number');
      expect(config.stateSchema['energy']!.max, 100);
      expect(config.initialState['energy'], 80);
      expect(config.displayOrder, ['location', 'energy']);
    });

    test('简写 schema 类型字符串', () {
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
      expect(config.stateSchema['name']!.isNumber, isFalse);
    });

    test('无 tracker / 缺字段返回禁用配置', () {
      expect(TrackerConfig.fromCardJson(null).isEnabled, isFalse);
      expect(
        TrackerConfig.fromCardJson({'data': {'extensions': {}}}).isEnabled,
        isFalse,
      );
    });

    test('schemaVersion 为字符串 "1.0" 不崩溃（真实卡格式）', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'schemaVersion': '1.0',
              'stateSchema': {'energy': {'type': 'number', 'label': '体力'}},
              'initialState': {'energy': 80},
              'uiHints': {'order': ['energy']},
            },
          },
        },
      });
      expect(config.isEnabled, isTrue);
      expect(config.stateSchema['energy']!.type, 'number');
      expect(config.initialState['energy'], 80);
    });

    test('tracker 为畸形结构（template 为对象）不崩溃', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'template': {'div': true},
              'stateSchema': 'not-a-map',
            },
          },
        },
      });
      // 顶层兜底返回禁用配置，不抛异常
      expect(config, isA<TrackerConfig>());
    });
  });

  group('extractPatch', () {
    test('JSON patch set/add 解析', () {
      final patch = TrackerRuntime.extractPatch(
        '正文内容\n```json\n{"patch": {"set": {"location": "旅馆"},'
        ' "add": {"energy": -3}}}\n```',
      );
      expect(patch.setValues['location'], '旅馆');
      expect(patch.addValues['energy'], -3);
      expect(patch.reply, isNull);
    });

    test('{reply, patch} 结构提取 reply 为正文', () {
      final patch = TrackerRuntime.extractPatch(
        '```json\n{"reply": "她推开窗，冷风灌了进来。",'
        ' "patch": {"set": {"location": "雪山"}}}\n```',
      );
      expect(patch.setValues['location'], '雪山');
      expect(patch.reply, '她推开窗，冷风灌了进来。');
    });

    test('extractChoices 提取动作列表', () {
      final choices = TrackerRuntime.extractChoices(
        '```json\n{"reply": "你想怎么做？", "choices": ['
        '{"id": "rest", "label": "休息"},'
        '{"id": "leave", "label": "离开", "action": "角色送我离开"}]}\n```',
      );
      expect(choices.length, 2);
      expect(choices[0].id, 'rest');
      expect(choices[0].label, '休息');
      expect(choices[1].action, '角色送我离开');
    });

    test('无 choices 返回空列表', () {
      expect(
        TrackerRuntime.extractChoices('普通回复没有 choices'),
        isEmpty,
      );
    });

    test('stripStateBlocks 含 reply 时用 reply 替换整块', () {
      final out = TrackerRuntime.stripStateBlocks(
        '```json\n{"reply": "她说：\\"走吧\\"\\n第二行。",'
        ' "patch": {"add": {"energy": -3}}}\n```',
      );
      expect(out, '她说："走吧"\n第二行。');
    });

    test('裸 JSON 对象（无代码块）解析', () {
      final patch = TrackerRuntime.extractPatch(
        '正文 {"patch": {"add": {"relationship": 2}}} 结尾',
      );
      expect(patch.addValues['relationship'], 2);
    });

    test('格式化裸 JSON（换行/空格）也能解析', () {
      final patch = TrackerRuntime.extractPatch(
        '正文 {\n  "patch": {\n    "set": {"location": "旅馆"}\n  }\n} 结尾',
      );
      expect(patch.setValues['location'], '旅馆');
    });

    test('STATE 块兜底：纯数字绝对值 / 增减量 / 字符串', () {
      final patch = TrackerRuntime.extractPatch(
        '回复内容 <STATE> location=深山 energy=-3 relationship=+2 mood=警惕 </STATE>',
      );
      expect(patch.setValues['location'], '深山');
      expect(patch.setValues['mood'], '警惕');
      expect(patch.addValues['energy'], -3);
      expect(patch.addValues['relationship'], 2);
    });

    test('无状态块返回空 patch', () {
      expect(TrackerRuntime.extractPatch('普通回复没有状态').isEmpty, isTrue);
    });
  });

  group('stripStateBlocks', () {
    test('剥离 STATE 块', () {
      expect(
        TrackerRuntime.stripStateBlocks('正文 <STATE> a=1 </STATE> 继续'),
        '正文  继续',
      );
    });

    test('剥离 JSON patch 代码块（含 patch 键）', () {
      final out = TrackerRuntime.stripStateBlocks(
        '正文\n```json\n{"patch": {"set": {"a": 1}}}\n```',
      );
      expect(out, '正文');
    });

    test('不误删正文 json 代码块（无 patch 键）', () {
      final code = '```json\n{"a": 1}\n```';
      expect(TrackerRuntime.stripStateBlocks(code), code);
    });
  });

  group('reduce', () {
    test('set 覆盖 + add 叠加', () {
      final next = TrackerRuntime.reduce(
        current: _config().initialState,
        patch: StatePatch(
          setValues: {'location': '雪山'},
          addValues: {'energy': -10, 'relationship': 5},
        ),
        config: _config(),
      );
      expect(next['location'], '雪山');
      expect(next['energy'], 70);
      expect(next['relationship'], 5);
    });

    test('数值 clamp 到 schema min/max', () {
      final next = TrackerRuntime.reduce(
        current: {'energy': 95},
        patch: StatePatch(addValues: {'energy': 10}),
        config: _config(),
      );
      expect(next['energy'], 100);
    });

    test('字符串字段忽略 add（仅 set）', () {
      final next = TrackerRuntime.reduce(
        current: {'mood': '平静'},
        patch: StatePatch(
          setValues: {'mood': '兴奋'},
          addValues: {'mood': 2},
        ),
        config: _config(),
      );
      expect(next['mood'], '兴奋');
    });

    test('add 对字符串数字当前值也能叠加（SQLite TEXT）', () {
      final next = TrackerRuntime.reduce(
        current: {'energy': '80'},
        patch: StatePatch(addValues: {'energy': -10}),
        config: _config(),
      );
      expect(next['energy'], 70);
    });

    test('add 字段缺失时回退 initialState 再叠加', () {
      final next = TrackerRuntime.reduce(
        current: const {},
        patch: StatePatch(addValues: {'energy': -3}),
        config: _config(),
      );
      expect(next['energy'], 77); // 80 - 3
    });

    test('add 缺失且无初始值时用 delta 作为绝对值（clamp）', () {
      final next = TrackerRuntime.reduce(
        current: const {},
        patch: StatePatch(addValues: {'relationship': 200}),
        config: _config(),
      );
      expect(next['relationship'], 100); // clamp 到 max
    });

    test('未声明字段宽松保留', () {
      final next = TrackerRuntime.reduce(
        current: const {},
        patch: StatePatch(setValues: {'customFlag': 'x'}),
        config: _config(),
      );
      expect(next['customFlag'], 'x');
    });
  });

  group('initState / formatStateText', () {
    test('initState 补缺失字段不覆盖已有', () {
      final state = TrackerRuntime.initState(
        config: _config(),
        existing: {'energy': 50},
      );
      expect(state['energy'], 50);
      expect(state['location'], '旅馆');
    });

    test('formatStateText 按 uiOrder 输出中文标签', () {
      final text = TrackerRuntime.formatStateText(
        state: {'location': '旅馆', 'energy': 87, 'mood': '警惕'},
        config: _config(),
      );
      expect(text, contains('【当前状态】'));
      expect(text, contains('地点：旅馆'));
      expect(text, contains('体力：87'));
      expect(text, contains('情绪：警惕'));
      // 顺序：location 在 energy 前（uiOrder）
      expect(text.indexOf('地点'), lessThan(text.indexOf('体力')));
    });
  });

  group('TrackerRuntime.extractValuesFromPanelText', () {
    test('解析面板 label:值 回写（number 取数字 / string 取文本）', () {
      const panel =
          '<div>❤️ 体力：35/100 · 地点：木屋 · 情绪：紧张</div>';
      final result = TrackerRuntime.extractValuesFromPanelText(panel, _config());
      expect(result['energy'], '35');
      expect(result['location'], '木屋');
      expect(result['mood'], '紧张');
    });
    test('中文冒号与全角逗号分隔', () {
      const panel = '体力：66，地点：木屋，情绪：紧张';
      final result = TrackerRuntime.extractValuesFromPanelText(panel, _config());
      expect(result['energy'], '66');
      expect(result['location'], '木屋');
      expect(result['mood'], '紧张');
    });
    test('number 带单位后缀取数字', () {
      const panel = '体力：42% · 关系：-10';
      final result = TrackerRuntime.extractValuesFromPanelText(panel, _config());
      expect(result['energy'], '42');
      expect(result['relationship'], '-10');
    });
    test('无冒号格式（<summary>❤️ 烙印值 35/100</summary>）容错', () {
      const panel = '<summary>❤️ 体力 35/100</summary><div>地点 木屋</div>';
      final result = TrackerRuntime.extractValuesFromPanelText(panel, _config());
      expect(result['energy'], '35');
      expect(result['location'], '木屋');
    });
  });
}
