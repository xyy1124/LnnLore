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

    test('v50: formatTrackerInstruction 注入真实 key 映射（key/label/type/range/current）', () {
      final text = TrackerRuntime.formatTrackerInstruction(
        state: {'energy': 87, 'location': '旅馆'},
        config: _config(),
      );
      expect(text, contains('key=energy'));
      expect(text, contains('label=体力'));
      expect(text, contains('type=number'));
      expect(text, contains('range=0..100'));
      expect(text, contains('current=87'));
      expect(text, contains('key=location | label=地点 | type=string'));
      // 禁止使用中文 label 的说明
      expect(text, contains('禁止使用中文 label'));
    });

    test('v50: formatTrackerInstruction 字符串字段无 range', () {
      final text = TrackerRuntime.formatTrackerInstruction(
        state: {'location': '旅馆', 'mood': '平静'},
        config: _config(),
      );
      expect(text, contains('type=string | current=旅馆'));
      expect(text, isNot(contains('range=')));
    });
  });

  group('v50: canonicalizePatch（label→key 映射 + 未知丢弃）', () {
    test('中文 label 映射回真实 key', () {
      final config = TrackerConfig.fromCardJson({
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
                'yw_cloth': {'type': 'string', 'label': '黑丝状态'},
              },
              'initialState': {'yw_brand': 20, 'yw_cloth': '完好'},
            },
          },
        },
      });
      // 模型输出中文 label（v49 之前会被当成新变量保存）
      final (patch, dropped) = TrackerRuntime.canonicalizePatch(
        StatePatch(
          setValues: {'黑丝状态': '轻微破损'},
          addValues: {'烙印值': 10},
        ),
        config,
      );
      expect(patch.setValues, {'yw_cloth': '轻微破损'});
      expect(patch.addValues, {'yw_brand': 10});
      expect(dropped, isEmpty);
    });

    test('真实 key 原样保留', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'yw_brand': {'type': 'number', 'label': '烙印值'},
              },
              'initialState': {'yw_brand': 20},
            },
          },
        },
      });
      final (patch, dropped) = TrackerRuntime.canonicalizePatch(
        StatePatch(addValues: {'yw_brand': 5}),
        config,
      );
      expect(patch.addValues, {'yw_brand': 5});
      expect(dropped, isEmpty);
    });

    test('完全未知字段丢弃并记录', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'yw_brand': {'type': 'number', 'label': '烙印值'},
              },
              'initialState': {'yw_brand': 20},
            },
          },
        },
      });
      final (patch, dropped) = TrackerRuntime.canonicalizePatch(
        StatePatch(
          setValues: {'unknownField': 'x'},
          addValues: {'yw_brand': 3},
        ),
        config,
      );
      expect(patch.setValues, isEmpty);
      expect(patch.addValues, {'yw_brand': 3});
      expect(dropped, ['unknownField']);
    });

    test('卡未启用时未知字段宽松保留（自定义 patch 变量）', () {
      final config = TrackerConfig.fromCardJson({'data': {'extensions': {}}});
      final (patch, dropped) = TrackerRuntime.canonicalizePatch(
        StatePatch(setValues: {'customFlag': 'x'}),
        config,
      );
      expect(patch.setValues, {'customFlag': 'x'});
      expect(dropped, isEmpty);
    });

    test('空 patch 原样返回', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'yw_brand': {'type': 'number', 'label': '烙印值'},
              },
              'initialState': {'yw_brand': 20},
            },
          },
        },
      });
      final (patch, dropped) =
          TrackerRuntime.canonicalizePatch(StatePatch(), config);
      expect(patch.isEmpty, isTrue);
      expect(dropped, isEmpty);
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
    test('复杂 HTML 结构（span 分离 label 与值）也能解析', () {
      const panel =
          '<div><span>体力：</span><b>42</b></div><div><span>地点</span><b>雪山</b></div>';
      final result = TrackerRuntime.extractValuesFromPanelText(panel, _config());
      expect(result['energy'], '42');
      expect(result['location'], '雪山');
    });
    test('label 首次出现无效、后续出现有效时取后续值', () {
      const panel = '<div>体力：N/A</div><div>体力：66</div>';
      final result = TrackerRuntime.extractValuesFromPanelText(panel, _config());
      expect(result['energy'], '66');
    });
  });

  group('TrackerRuntime.parseNarrationStateChanges', () {
    test('旁白（体力+10）解析为 add', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（体力+10）', _config());
      expect(changes['energy'], ('10', true));
    });
    test('旁白（体力=35）解析为 set', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（体力=35）', _config());
      expect(changes['energy'], ('35', false));
    });
    test('旁白（地点=雪山）字符串赋值', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（地点=雪山）', _config());
      expect(changes['location'], ('雪山', false));
    });
    test('旁白（黑丝状态=破损）无 schema 字段不解析', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（黑丝状态=破损）', _config());
      expect(changes, isEmpty);
    });
    test('v49: 旁白（体力-5）负号保留（-5 而非 +5）', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（体力-5）', _config());
      expect(changes['energy'], ('-5', true));
    });
    test('v49: 旁白（体力 - 5）带空格负号也保留', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（体力 - 5）', _config());
      expect(changes['energy'], ('-5', true));
    });
    test('v49: 旁白（关系-10）负增量（min<0 字段）', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（关系-10）', _config());
      expect(changes['relationship'], ('-10', true));
    });
    test('v49: 自然语言 体力提高40% → add +40', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('烙印值？体力提高40%', _config());
      expect(changes['energy'], ('40', true));
    });
    test('v49: 自然语言 体力增加10 → add +10', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('旁白：体力增加10', _config());
      expect(changes['energy'], ('10', true));
    });
    test('v49: 自然语言 体力上升8 → add +8', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('体力上升8', _config());
      expect(changes['energy'], ('8', true));
    });
    test('v49: 自然语言 体力加3 → add +3', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('体力加3', _config());
      expect(changes['energy'], ('3', true));
    });
    test('v49: 自然语言 体力减少5 → add -5', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('体力减少5', _config());
      expect(changes['energy'], ('-5', true));
    });
    test('v49: 自然语言 体力降低3 → add -3', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('体力降低3', _config());
      expect(changes['energy'], ('-3', true));
    });
    test('v49: 自然语言 体力下降2 → add -2', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('体力下降2', _config());
      expect(changes['energy'], ('-2', true));
    });
    test('v49: 自然语言 体力减 5（带空格）→ add -5', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('体力减 5', _config());
      expect(changes['energy'], ('-5', true));
    });
    test('v49: 括号格式优先于自然语言（（体力+10）体力提高40）', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('（体力+10）体力提高40', _config());
      expect(changes['energy'], ('10', true));
    });
    test('v49: 字符串字段自然语言增减不解析', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('地点提高2', _config());
      expect(changes, isEmpty);
    });
    test('v49: 自然语言 关系降低10 → add -10', () {
      final changes =
          TrackerRuntime.parseNarrationStateChanges('关系降低10', _config());
      expect(changes['relationship'], ('-10', true));
    });
    test('无旁白文本返回空', () {
      expect(TrackerRuntime.parseNarrationStateChanges('正常聊天', _config()),
          isEmpty);
    });
  });

  group('旁白应用链路（与 chat_service 发送时同款逻辑）', () {
    // 与 chat_service.dart 里旁白块逐行对应：isAdd 走 addValues，
    // number 字段 = 赋值走 setValues（_validate 会 clamp min/max），
    // string 字段直接写入。
    Map<String, String> applyNarration(
      String input,
      TrackerConfig config,
      Map<String, String> vars,
    ) {
      final changes =
          TrackerRuntime.parseNarrationStateChanges(input, config);
      final result = Map<String, String>.from(vars);
      for (final entry in changes.entries) {
        final key = entry.key;
        final (value, isAdd) = entry.value;
        if (isAdd) {
          final next = TrackerRuntime.reduce(
            current: TrackerRuntime.initState(
              config: config,
              existing: result,
            ),
            patch: StatePatch(addValues: {key: num.tryParse(value) ?? 0}),
            config: config,
          );
          result[key] = '${next[key]}';
        } else {
          final schema = config.stateSchema[key];
          if (schema != null && schema.isNumber) {
            final next = TrackerRuntime.reduce(
              current: TrackerRuntime.initState(
                config: config,
                existing: result,
              ),
              patch: StatePatch(
                setValues: {key: num.tryParse(value) ?? 0},
              ),
              config: config,
            );
            result[key] = '${next[key]}';
          } else {
            result[key] = value;
          }
        }
      }
      return result;
    }

    test('（体力=999）越界赋值被 clamp 到 max=100', () {
      final result = applyNarration('（体力=999）', _config(), {'energy': '80'});
      expect(result['energy'], '100');
    });
    test('（体力=-999）越界赋值被 clamp 到 min=0', () {
      final result = applyNarration('（体力=-999）', _config(), {'energy': '80'});
      expect(result['energy'], '0');
    });
    test('（体力=35）正常赋值保留', () {
      final result = applyNarration('（体力=35）', _config(), {'energy': '80'});
      expect(result['energy'], '35');
    });
    test('（地点=雪山）字符串字段直接写入', () {
      final result =
          applyNarration('（地点=雪山）', _config(), {'location': '旅馆'});
      expect(result['location'], '雪山');
    });
    test('（体力+10）仍走 add 叠加', () {
      final result = applyNarration('（体力+10）', _config(), {'energy': '80'});
      expect(result['energy'], '90');
    });
    test('（体力+1000）add 越界也 clamp 到 100', () {
      final result = applyNarration('（体力+1000）', _config(), {'energy': '80'});
      expect(result['energy'], '100');
    });
  });

  group('v51: applyNarrationChanges（分支回滚共用旁白应用）', () {
    test('add 与字符串赋值组合应用', () {
      final result = TrackerRuntime.applyNarrationChanges(
        {'energy': '80', 'location': '旅馆'},
        {
          'energy': ('-5', true),
          'location': ('雪山', false),
        },
        _config(),
      );
      expect(result['energy'], 75);
      expect(result['location'], '雪山');
    });

    test('number = 赋值越界 clamp', () {
      final result = TrackerRuntime.applyNarrationChanges(
        {'energy': '80'},
        {'energy': ('999', false)},
        _config(),
      );
      expect(result['energy'], 100);
    });

    test('空旁白返回原状态副本（不修改原 map）', () {
      final original = {'energy': '80', 'location': '旅馆'};
      final result = TrackerRuntime.applyNarrationChanges(
        original,
        {},
        _config(),
      );
      expect(result, original);
      expect(identical(result, original), isFalse);
    });

    test('缺失字段经 initState 补全后再叠加', () {
      final result = TrackerRuntime.applyNarrationChanges(
        {'energy': '30'},
        {'energy': ('+10', true)},
        _config(),
      );
      expect(result['energy'], 40);
    });
  });

  group('v52: presentation 阶段描述系统', () {
    TrackerConfig configWithPresentation() {
      return TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'mz_nano': {
                  'type': 'number',
                  'label': '纳米改造',
                  'min': 0,
                  'max': 100,
                  'presentation': {
                    'ranges': [
                      {
                        'gte': 0,
                        'lt': 20,
                        'title': '尚未启动',
                        'color': '#78909C',
                        'text': '纳米机械尚未建立有效连接。',
                      },
                      {
                        'gte': 40,
                        'lt': 60,
                        'title': '明显改造',
                        'color': '#FFA726',
                        'text': '部分反应不再完全受本人控制。',
                      },
                      {
                        'gte': 80,
                        'title': '完全接管',
                        'color': '#AB47BC',
                        'text': '意志与身体反应出现分离。',
                      },
                    ],
                  },
                },
                'mz_rank': {
                  'type': 'string',
                  'label': '母猪等级',
                  'presentation': {
                    'states': {
                      '新收': {
                        'title': '新收',
                        'color': '#90A4AE',
                        'text': '尚未完成第一次正式侍奉。',
                      },
                      '核心': {
                        'title': '核心母猪',
                        'color': '#AB47BC',
                        'text': '主动性和服从性都被重新定义。',
                      },
                    },
                  },
                },
              },
              'initialState': {'mz_nano': 0, 'mz_rank': '新收'},
            },
          },
        },
      });
    }

    test('number 字段按 ranges 分段匹配（40 ≤ v < 60）', () {
      final config = configWithPresentation();
      final stage = TrackerRuntime.stageInfo('mz_nano', 45, config);
      expect(stage, isNotNull);
      expect(stage!.title, '明显改造');
      expect(stage.color, '#FFA726');
      expect(stage.text, contains('部分反应'));
    });

    test('ranges 无匹配时最后一段兜底（值 70 无区间 → 完全接管）', () {
      final config = configWithPresentation();
      final stage = TrackerRuntime.stageInfo('mz_nano', 70, config);
      expect(stage, isNotNull);
      expect(stage!.title, '完全接管');
    });

    test('string 字段按 states 精确匹配', () {
      final config = configWithPresentation();
      final stage = TrackerRuntime.stageInfo('mz_rank', '核心', config);
      expect(stage, isNotNull);
      expect(stage!.title, '核心母猪');
      expect(stage.color, '#AB47BC');
    });

    test('无声明/无匹配返回 null（旧卡不受影响）', () {
      final config = configWithPresentation();
      expect(TrackerRuntime.stageInfo('mz_rank', '未知状态', config), isNull);
      // 旧 schema（无 presentation）也返回 null
      expect(TrackerRuntime.stageInfo('energy', 50, _config()), isNull);
    });

    test('presentation 解析：畸形结构不崩溃（宽松兜底）', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'bad': {
                  'type': 'number',
                  'label': '坏字段',
                  'presentation': {'ranges': 'not-a-list', 'states': 42},
                },
              },
              'initialState': {'bad': 10},
            },
          },
        },
      });
      expect(config.stateSchema['bad']!.presentation, isNotNull);
      expect(config.stateSchema['bad']!.presentation!.ranges, isEmpty);
      expect(config.stateSchema['bad']!.presentation!.states, isEmpty);
    });

    test('模板变量 gettitle/gettext/getcolor/getpercent 替换', () {
      final config = configWithPresentation();
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: {
          'data': {
            'extensions': {
              'tracker': {
                'stateSchema': {
                  'mz_nano': {
                    'type': 'number',
                    'label': '纳米改造',
                    'min': 0,
                    'max': 100,
                    'presentation': {
                      'ranges': [
                        {
                          'gte': 40,
                          'lt': 60,
                          'title': '明显改造',
                          'color': '#FFA726',
                          'text': '部分反应不再受控',
                        },
                      ],
                    },
                  },
                },
                'initialState': {'mz_nano': 0},
                'template':
                    '<div>{{getvar::mz_nano}}|{{gettitle::mz_nano}}|'
                    '{{gettext::mz_nano}}|{{getcolor::mz_nano}}|'
                    '{{getpercent::mz_nano}}</div>',
              },
            },
          },
        },
        variables: {'mz_nano': '45'},
      );
      expect(html, contains('45|明显改造|部分反应不再受控|#FFA726|45'));
    });

    test('getpercent 按 min/max 归一化', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: {
          'data': {
            'extensions': {
              'tracker': {
                'stateSchema': {
                  'progress': {
                    'type': 'number',
                    'label': '进度',
                    'min': 0,
                    'max': 200,
                  },
                },
                'initialState': {'progress': 0},
                'template': '<div>{{getpercent::progress}}%</div>',
              },
            },
          },
        },
        variables: {'progress': '150'},
      );
      expect(html, contains('75%')); // 150/200*100
    });

    test('v52: 变量值 HTML 转义（描述含 < > & 不破坏模板）', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: {
          'data': {
            'extensions': {
              'tracker': {
                'stateSchema': {
                  'flag': {
                    'type': 'string',
                    'label': '标记',
                    'presentation': {
                      'states': {
                        '危险': {
                          'title': '危险<警告>',
                          'color': '#FF0000',
                          'text': '状态&异常，值"X"',
                        },
                      },
                    },
                  },
                },
                'initialState': {'flag': '正常'},
                'template':
                    '<div>{{getvar::flag}}|{{gettitle::flag}}|{{gettext::flag}}</div>',
              },
            },
          },
        },
        variables: {'flag': '危险'},
      );
      // < > & 被转义，不破坏 HTML 结构
      expect(html, contains('危险&lt;警告&gt;'));
      expect(html, contains('状态&amp;异常，值&quot;X&quot;'));
      // 原始 < 不再出现（除模板自身的标签）
      expect(html, isNot(contains('危险<警告>')));
    });
  });

  group('v54: uiHints.template 兼容 + defaultExpanded', () {
    test('uiHints.template 兜底读取（早期注释示例写法）', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'a': {'type': 'number', 'label': 'A'},
              },
              'initialState': {'a': 1},
              'uiHints': {'order': ['a'], 'template': '<div>uiHints模板</div>'},
            },
          },
        },
      });
      expect(config.template, '<div>uiHints模板</div>');
    });

    test('tracker.template 优先于 uiHints.template', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'a': {'type': 'number', 'label': 'A'},
              },
              'initialState': {'a': 1},
              'template': '<div>顶层模板</div>',
              'uiHints': {'template': '<div>uiHints模板</div>'},
            },
          },
        },
      });
      expect(config.template, '<div>顶层模板</div>');
    });

    test('defaultExpanded 读取（默认收起）', () {
      final enabled = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'a': {'type': 'number', 'label': 'A'},
              },
              'initialState': {'a': 1},
              'defaultExpanded': true,
            },
          },
        },
      });
      expect(enabled.defaultExpanded, isTrue);
      final defaulted = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'a': {'type': 'number', 'label': 'A'},
              },
              'initialState': {'a': 1},
            },
          },
        },
      });
      expect(defaulted.defaultExpanded, isFalse);
    });
  });

  group('v54: 内置 fallback 进度条', () {
    Map<String, dynamic> cardWithoutTemplate() => {
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
                'initialState': {'yw_brand': 0},
              },
            },
          },
        };

    test('number 字段带 min/max 渲染进度条（width=45%）', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithoutTemplate(),
        variables: {'yw_brand': '45'},
      );
      expect(html, contains('45/100'));
      // Dart double 插值会输出 45.0——宽松匹配
      expect(html, contains('width:45'));
      expect(html, contains('height:4px'));
    });

    test('带 stage 的字段进度条颜色跟随阶段色', () {
      final card = cardWithoutTemplate();
      (card['data']! as Map<String, dynamic>)['extensions'] = {
        'tracker': {
          'stateSchema': {
            'yw_brand': {
              'type': 'number',
              'label': '烙印值',
              'min': 0,
              'max': 100,
              'presentation': {
                'ranges': [
                  {
                    'gte': 40,
                    'lt': 60,
                    'title': '刻印显现',
                    'color': '#8e44ad',
                    'text': '纹路清晰可见。',
                  },
                ],
              },
            },
          },
          'initialState': {'yw_brand': 0},
        },
      };
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'yw_brand': '45'},
      );
      expect(html, contains('width:45'));
      expect(html, contains('background:#8e44ad'));
      expect(html, contains('· 刻印显现'));
    });

    test('无 min/max 的 number 字段保持 chip（无进度条）', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: {
          'data': {
            'extensions': {
              'tracker': {
                'stateSchema': {
                  'cnt': {'type': 'number', 'label': '计数'},
                },
                'initialState': {'cnt': 3},
              },
            },
          },
        },
        variables: {'cnt': '3'},
      );
      expect(html, contains('计数：3'));
      expect(html, isNot(contains('height:4px')));
    });
  });

  group('v55: protocolDetected（空 patch 与无协议区分）', () {
    test('合法空 patch：protocolDetected=true 且 isEmpty', () {
      final patch = TrackerRuntime.extractPatch(
        '剧情正文\n```json\n{"reply":"正文","patch":{"set":{},"add":{}}}\n```',
      );
      expect(patch.isEmpty, isTrue);
      expect(patch.protocolDetected, isTrue);
    });

    test('非空 patch：protocolDetected=true', () {
      final patch = TrackerRuntime.extractPatch(
        '```json\n{"patch":{"set":{"mood":"平静"},"add":{"energy":-3}}}\n```',
      );
      expect(patch.isEmpty, isFalse);
      expect(patch.protocolDetected, isTrue);
    });

    test('无协议：protocolDetected=false', () {
      final patch = TrackerRuntime.extractPatch('普通剧情回复，没有状态协议');
      expect(patch.isEmpty, isTrue);
      expect(patch.protocolDetected, isFalse);
    });

    test('STATE 块：protocolDetected=true', () {
      final patch = TrackerRuntime.extractPatch(
        '正文 <STATE> energy=+5 </STATE>',
      );
      expect(patch.addValues, {'energy': 5});
      expect(patch.protocolDetected, isTrue);
    });

    test('filterProtectedPatch 透传 protocolDetected', () {
      final patch = StatePatch(
        setValues: {'energy': 10},
        protocolDetected: true,
      );
      final filtered = TrackerRuntime.filterProtectedPatch(patch, {'mood'});
      expect(filtered.protocolDetected, isTrue);
    });

    test('canonicalizePatch 透传 protocolDetected', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'energy': {'type': 'number', 'label': '体力'},
              },
              'initialState': {'energy': 80},
            },
          },
        },
      });
      final (canonical, _) = TrackerRuntime.canonicalizePatch(
        StatePatch(
          addValues: {'体力': 5},
          protocolDetected: true,
        ),
        config,
      );
      expect(canonical.addValues, {'energy': 5});
      expect(canonical.protocolDetected, isTrue);
    });
  });

  group('v58: 模板选择「第一个有效」（渲染回归根因）', () {
    test('uiHints.template 无效（占位文本）时回退 post_history HTML', () {
      // 真实卡结构：uiHints.template = "{label}：{value}"（无 getvar），
      // post_history_instructions 才有真正的 HTML 面板——v54 兼容读取
      // 后无效 template 截断了 HTML 面板（渲染回归根因）
      final card = {
        'data': {
          'name': '测试卡',
          'post_history_instructions': '规则\n'
              '<!--panel-->\n'
              '<details><summary>🩸 测试面板</summary>'
              '<div style="padding:10px;background-color:#171020;'
              'border:2px solid #8e44ad;">'
              '烙印值：<b>【{{getvar::yw_brand}}/100】</b></div>'
              '</details>\n'
              '<!--/panel-->',
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
              'initialState': {'yw_brand': 0},
              'uiHints': {
                'order': ['yw_brand'],
                'template': '{label}：{value}',
              },
            },
          },
        },
      };
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'yw_brand': '35'},
      );
      // 必须使用 post_history 的 HTML 面板（带卡的自定义样式）
      expect(html, contains('background-color:#171020'));
      expect(html, contains('border:2px solid #8e44ad'));
      expect(html, contains('烙印值：'));
      expect(html, contains('35/100'));
      // 不能掉进内置统一面板
      expect(html, isNot(contains('class="status-panel"')));
    });

    test('tracker.template 有效时优先于 post_history', () {
      final card = {
        'data': {
          'name': '测试卡',
          'post_history_instructions': '规则\n'
              '<!--panel-->\n'
              '<details><summary>面板</summary><div>PHI模板</div></details>\n'
              '<!--/panel-->',
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
              'initialState': {'yw_brand': 0},
              'template': '<div>tracker模板：{{getvar::yw_brand}}</div>',
            },
          },
        },
      };
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'yw_brand': '20'},
      );
      expect(html, contains('tracker模板：20'));
      expect(html, isNot(contains('PHI模板')));
    });

    test('全部候选无效时回退内置面板', () {
      final card = {
        'data': {
          'name': '测试卡',
          'post_history_instructions': '没有面板模板',
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
              'initialState': {'yw_brand': 0},
              'uiHints': {'template': '{label}：{value}'},
            },
          },
        },
      };
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'yw_brand': '20'},
      );
      expect(html, contains('class="status-panel"'));
      expect(html, contains('烙印值：20/100'));
    });
  });

  group('v60: updatePolicy 程度词 + aliases（剧情自主判断）', () {
    TrackerConfig configWithPolicy() {
      return TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'like': {
                  'type': 'number',
                  'label': '好感度',
                  'aliases': ['好感', '亲密感'],
                  'min': 0,
                  'max': 100,
                  'updatePolicy': {
                    'mode': 'conservative',
                    'qualitativeDeltas': {
                      '一点': 1,
                      '少许': 1,
                      '稍微': 2,
                      '明显': 5,
                      '大幅': 10,
                    },
                    'maxAutoDeltaPerTurn': 10,
                  },
                },
              },
              'initialState': {'like': 20},
            },
          },
        },
      });
    }

    test('aliases 解析（好感/亲密感）', () {
      final config = configWithPolicy();
      expect(config.stateSchema['like']!.aliases, contains('好感'));
      expect(config.stateSchema['like']!.aliases, contains('亲密感'));
    });

    test('updatePolicy 解析（mode/程度词/上限）', () {
      final config = configWithPolicy();
      final policy = config.stateSchema['like']!.updatePolicy!;
      expect(policy.mode, 'conservative');
      expect(policy.qualitativeDeltas['明显'], 5);
      expect(policy.maxAutoDeltaPerTurn, 10);
    });

    test('好感提升一点 → add +1（程度词确定性量化）', () {
      final config = configWithPolicy();
      final changes = TrackerRuntime.parseNarrationStateChanges(
        '好感提升一点',
        config,
      );
      expect(changes['like'], ('1', true));
    });

    test('好感明显提高 → add +5', () {
      final config = configWithPolicy();
      final changes = TrackerRuntime.parseNarrationStateChanges(
        '好感明显提高',
        config,
      );
      expect(changes['like'], ('5', true));
    });

    test('好感稍微下降 → add -2', () {
      final config = configWithPolicy();
      final changes = TrackerRuntime.parseNarrationStateChanges(
        '好感稍微下降',
        config,
      );
      expect(changes['like'], ('-2', true));
    });

    test('亲密感大幅增加 → add +10（aliases 匹配）', () {
      final config = configWithPolicy();
      final changes = TrackerRuntime.parseNarrationStateChanges(
        '亲密感大幅增加',
        config,
      );
      expect(changes['like'], ('10', true));
    });

    test('无 updatePolicy 时程度词不猜（保持无匹配）', () {
      final config = TrackerConfig.fromCardJson({
        'data': {
          'extensions': {
            'tracker': {
              'stateSchema': {
                'like': {
                  'type': 'number',
                  'label': '好感度',
                  'min': 0,
                  'max': 100,
                },
              },
              'initialState': {'like': 20},
            },
          },
        },
      });
      expect(
        TrackerRuntime.parseNarrationStateChanges('好感提升一点', config),
        isEmpty,
      );
    });

    test('格式注入 qualitative 规则与防膨胀约束', () {
      final config = configWithPolicy();
      final text = TrackerRuntime.formatTrackerInstruction(
        state: {'like': '20'},
        config: config,
      );
      expect(text, contains('qualitative: 一点=1，少许=1，稍微=2，明显=5，大幅=10'));
      expect(text, contains('maxAutoDeltaPerTurn=10'));
      expect(text, contains('mode=conservative'));
      expect(text, contains('不得因为用户没有提供精确数字而返回'));
      expect(text, contains('同一事件每轮最多更新一次'));
    });

    test('applyPatchToVariables：canonicalize + reduce + clamp', () {
      final config = configWithPolicy();
      final result = TrackerRuntime.applyPatchToVariables(
        variables: {'like': '20'},
        patch: StatePatch(addValues: {'好感度': 5}),
        config: config,
      );
      expect(result['like'], '25');
    });

    test('applyPatchToVariables：clamp 到 max', () {
      final config = configWithPolicy();
      final result = TrackerRuntime.applyPatchToVariables(
        variables: {'like': '97'},
        patch: StatePatch(addValues: {'like': 5}),
        config: config,
      );
      expect(result['like'], '100');
    });
  });

  group('filterProtectedPatch（旁白字段本轮去重）', () {
    test('模型对旁白已落地字段的 add 被过滤（20→30 而非 40）', () {
      // 发送链路：旁白（烙印值+10）确定性落地 → 模型又输出 add +10
      final config = TrackerConfig.fromCardJson({
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
      });
      // 1) 旁白落地：20 → 30
      final narrationChanges =
          TrackerRuntime.parseNarrationStateChanges('（烙印值+10）', config);
      var vars = Map<String, String>.from({'yw_brand': '20'});
      for (final entry in narrationChanges.entries) {
        final (value, isAdd) = entry.value;
        final next = TrackerRuntime.reduce(
          current: TrackerRuntime.initState(
            config: config,
            existing: vars,
          ),
          patch: StatePatch(
            addValues: isAdd ? {entry.key: num.tryParse(value) ?? 0} : {},
            setValues: isAdd ? {} : {entry.key: num.tryParse(value) ?? 0},
          ),
          config: config,
        );
        vars[entry.key] = '${next[entry.key]}';
      }
      expect(vars['yw_brand'], '30');

      // 2) 模型再输出 add +10 → protectedKeys 过滤 → 仍为 30
      final modelPatch = StatePatch(addValues: {'yw_brand': 10});
      final filtered = TrackerRuntime.filterProtectedPatch(
        modelPatch,
        narrationChanges.keys.toSet(),
      );
      expect(filtered.addValues, isEmpty);
      final next = TrackerRuntime.reduce(
        current: TrackerRuntime.initState(config: config, existing: vars),
        patch: filtered,
        config: config,
      );
      expect('${next['yw_brand']}', '30');
    });

    test('模型对旁白已落地字段的 set 也被过滤', () {
      final patch = StatePatch(setValues: {'energy': 10, 'mood': '愤怒'});
      final filtered = TrackerRuntime.filterProtectedPatch(
        patch,
        {'energy'},
      );
      expect(filtered.setValues, {'mood': '愤怒'});
    });

    test('未受保护字段照常应用', () {
      final patch = StatePatch(addValues: {'energy': 5}, setValues: {'time': '深夜'});
      final filtered = TrackerRuntime.filterProtectedPatch(patch, {'mood'});
      expect(filtered.addValues, {'energy': 5});
      expect(filtered.setValues, {'time': '深夜'});
    });

    test('空保护集合原样返回（不产生新 patch 对象语义差异）', () {
      final patch = StatePatch(addValues: {'energy': 5});
      final filtered = TrackerRuntime.filterProtectedPatch(patch, {});
      expect(filtered.addValues, {'energy': 5});
    });

    test('重生成：只解析 keys 不应用，模型 add 被过滤（状态不重复增加）', () {
      final config = TrackerConfig.fromCardJson({
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
      });
      // 重生成链路：原用户消息含旁白，变量表已含首次应用后的值（30）
      const userTextForModel = '你继续（烙印值+10）';
      final protectedKeys = TrackerRuntime.parseNarrationStateChanges(
        userTextForModel,
        config,
      ).keys.toSet();
      expect(protectedKeys, {'yw_brand'});
      // 重生成时**不应用**旁白，只用于保护：模型 add +10 被过滤
      final filtered = TrackerRuntime.filterProtectedPatch(
        StatePatch(addValues: {'yw_brand': 10}),
        protectedKeys,
      );
      final next = TrackerRuntime.reduce(
        current: TrackerRuntime.initState(
          config: config,
          existing: {'yw_brand': '30'},
        ),
        patch: filtered,
        config: config,
      );
      expect('${next['yw_brand']}', '30');
    });
  });

  group('renderStatusPanelHtml（规范快照生成）', () {
    Map<String, dynamic> cardWithTemplate(String template) => {
          'data': {
            'extensions': {
              'regex_scripts': [
                {
                  'scriptName': 'StatusFallback',
                  'replaceString': template,
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

    test('JSON-only 回复也能生成规范快照（变量表+模板）', () {
      // 模型只输出 patch（无 HTML）——最终变量表已含新值 30
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithTemplate('<div>烙印值：{{getvar::yw_brand}}/100</div>'),
        variables: {'yw_brand': '30'},
      );
      expect(html, isNotNull);
      expect(html, contains('烙印值：30/100'));
    });

    test('快照数值=最终状态，patch 新值压过模型旧 HTML（30 而非 20）', () {
      // 模型旧 HTML 面板写死 20，但 patch 已更新变量表为 30——
      // 规范快照必须显示 30（快照来源是变量表，不是模型 HTML）
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithTemplate('<div>烙印值：{{getvar::yw_brand}}/100</div>'),
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('烙印值：30/100'));
      expect(html, isNot(contains('烙印值：20/100')));
    });

    test('缺失字段回退 initialState', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithTemplate('<div>烙印值：{{getvar::yw_brand}}/100</div>'),
        variables: {},
      );
      expect(html, contains('烙印值：20/100'));
    });

    test('富 HTML 模板直接渲染（不套 App 默认容器）', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithTemplate(
          '<table><tr><td>烙印值</td><td>{{getvar::yw_brand}}/100</td></tr></table>',
        ),
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('<table>'));
      // 富 HTML 不包 status-panel 容器（尊重卡定义样式）
      expect(html, isNot(contains('class="status-panel"')));
    });

    test('纯文本模板套默认容器', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithTemplate('烙印值：{{getvar::yw_brand}}/100'),
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('class="status-panel"'));
      expect(html, contains('烙印值：30/100'));
    });

    test('getvar 大小写不敏感（{{GETVAR::key}} 也能填充）', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: cardWithTemplate('<div>烙印值：{{GETVAR::yw_brand}}/100</div>'),
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('烙印值：30/100'));
    });

    test('卡无模板时回退内置 chips 卡片', () {
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

    test('卡未启用返回 null', () {
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: {'data': {'extensions': {}}},
        variables: {'yw_brand': '30'},
      );
      expect(html, isNull);
    });
  });

  group('postHistoryPanelTemplate（<!--panel--> HTML 模板提取）', () {
    Map<String, dynamic> cardWithPostHistory(String phi) => {
          'data': {
            'name': '测试角色',
            'post_history_instructions': phi,
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
        };

    const panelHtml =
        '<details><summary>🩸 烙印状态面板</summary><div style="padding:10px;'
        'background:#0d0a14;border:2px solid #8e44ad;">'
        '<span>烙印值</span>：<b>【{{getvar::yw_brand}}/100】</b></div></details>';

    test('提取 <!--panel--> 之间的 HTML 模板', () {
      final phi = '【状态栏三件套】\n必须输出面板：\n'
          '<!--panel-->\n$panelHtml\n<!--/panel-->\n'
          '其他说明文字';
      final template = TrackerRuntime.postHistoryPanelTemplate(
        cardWithPostHistory(phi),
      );
      expect(template, isNotNull);
      expect(template, contains('<details>'));
      expect(template, contains('{{getvar::yw_brand}}'));
    });

    test('panel 块无 getvar 时不提取（避免把说明文字当模板）', () {
      final phi = '<!--panel-->\n<div>纯静态内容</div>\n<!--/panel-->';
      expect(
        TrackerRuntime.postHistoryPanelTemplate(cardWithPostHistory(phi)),
        isNull,
      );
    });

    test('无 panel 标记返回 null', () {
      expect(
        TrackerRuntime.postHistoryPanelTemplate(
          cardWithPostHistory('没有任何 panel 标记的说明文字'),
        ),
        isNull,
      );
    });

    test('多个 panel 块取第一个满足条件的', () {
      final phi = '<!--panel-->\n<div>无效</div>\n<!--/panel-->\n'
          '<!--panel-->\n$panelHtml\n<!--/panel-->';
      final template = TrackerRuntime.postHistoryPanelTemplate(
        cardWithPostHistory(phi),
      );
      expect(template, contains('{{getvar::yw_brand}}'));
    });

    test('v48: 说明句含字面 <!--panel--> 时不误当面板起点', () {
      // 真实卡结构：说明句"提到" <!--panel--> 标记（嵌在句中，非独占
      // 整行），随后才是真正的面板块——提取必须跳过假标记
      final phi = '必须保留 <!--panel--> 标记；数值用 {{getvar}} 引用，'
          '不得编造）：\n'
          '<!--panel-->\n$panelHtml\n<!--/panel-->';
      final template = TrackerRuntime.postHistoryPanelTemplate(
        cardWithPostHistory(phi),
      );
      expect(template, isNotNull);
      // 模板只能是从真面板开始的 HTML，不能包含说明句尾巴
      expect(template, isNot(contains('不得编造')));
      expect(template, contains('{{getvar::yw_brand}}'));
    });

    test('v48: stripPanelTemplates 与提取共用独占整行边界', () {
      final phi = '必须保留 <!--panel--> 标记；数值用 {{getvar}} 引用）：\n'
          '<!--panel-->\n$panelHtml\n<!--/panel-->\n'
          '其余规则';
      final stripped = TrackerRuntime.stripPanelTemplates(phi);
      // 说明句里的字面标记保留（非独占整行），真面板块被删
      expect(stripped, contains('必须保留 <!--panel--> 标记'));
      expect(stripped, isNot(contains('<details>')));
      expect(stripped, contains('其余规则'));
    });

    test('renderStatusPanelHtml 优先用 post_history_instructions 的 HTML 模板', () {
      final card = cardWithPostHistory(
        '【状态栏三件套】\n'
        '<!--panel-->\n$panelHtml\n<!--/panel-->\n',
      );
      // 卡同时有纯文本 StatusFallback——必须用 HTML panel，而非文本
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('【30/100】'));
      expect(html, contains('background:#0d0a14'));
    });

    test('tracker.template 优先于 post_history_instructions', () {
      final card = cardWithPostHistory(
        '<!--panel-->\n$panelHtml\n<!--/panel-->',
      );
      (card['data']! as Map<String, dynamic>)['extensions'] = {
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
          'template': '<div>自定义：{{getvar::yw_brand}}</div>',
        },
      };
      final html = TrackerRuntime.renderStatusPanelHtml(
        cardJson: card,
        variables: {'yw_brand': '30'},
      );
      expect(html, contains('自定义：30'));
      expect(html, isNot(contains('【30/100】')));
    });
  });
}
