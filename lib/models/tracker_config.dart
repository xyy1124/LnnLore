import 'package:flutter/foundation.dart';

import '../services/character_card_extensions_reader.dart';

/// 特别版：角色卡状态跟踪（Tracker）协议——卡声明部分。
///
/// 读取角色卡 `data.extensions.tracker`（Character Cards V2 扩展数据）：
/// ```json
/// {
///   "schemaVersion": 1,
///   "stateSchema": {
///     "location": {"type": "string", "label": "地点"},
///     "energy":  {"type": "number", "label": "体力", "min": 0, "max": 100}
///   },
///   "initialState": {"location": "旅馆", "energy": 80},
///   "actions": [{"id": "rest", "label": "休息", "prompt": "……"}],
///   "uiHints": {"order": ["location", "energy"]},
///   "template": "<div>…</div>",
///   "defaultExpanded": false
/// }
/// ```
/// 卡只负责声明；解析/校验/reducer/渲染全部由 App 运行时执行。
///
/// v54：`template` 放在 tracker 顶层（推荐）；兼容读取 `uiHints.template`
/// （早期注释示例曾把 template 写在 uiHints 里——两个位置都读，照旧
/// 写法写的卡也能生效）。`defaultExpanded` 控制状态面板初始是否展开。

/// v52：数值字段的分段描述（presentation.ranges）——按当前值所在区间
/// 确定性渲染阶段标题/颜色/长描述，不依赖模型临时生成。
class TrackerRangeDescription {
  const TrackerRangeDescription({
    this.gte,
    this.lt,
    this.title = '',
    this.color = '',
    this.text = '',
  });

  /// 区间下限（含）；null = 不设下限
  final num? gte;
  /// 区间上限（不含）；null = 兜底到最后一段
  final num? lt;
  final String title;
  final String color;
  final String text;

  factory TrackerRangeDescription.fromJson(Map<String, dynamic> json) {
    return TrackerRangeDescription(
      gte: json['gte'] is num ? json['gte'] as num : null,
      lt: json['lt'] is num ? json['lt'] as num : null,
      title: json['title'] is String ? json['title'] as String : '',
      color: json['color'] is String ? json['color'] as String : '',
      text: json['text'] is String ? json['text'] as String : '',
    );
  }
}

/// v52：字符串字段的状态描述（presentation.states）——按枚举值精确匹配。
class TrackerEnumDescription {
  const TrackerEnumDescription({
    this.title = '',
    this.color = '',
    this.text = '',
  });

  final String title;
  final String color;
  final String text;

  factory TrackerEnumDescription.fromJson(Map<String, dynamic> json) {
    return TrackerEnumDescription(
      title: json['title'] is String ? json['title'] as String : '',
      color: json['color'] is String ? json['color'] as String : '',
      text: json['text'] is String ? json['text'] as String : '',
    );
  }
}

/// v52：字段的展示描述声明（stateSchema 字段内的 `presentation`）——
/// number 字段用 [ranges]（分段），string 字段用 [states]（枚举）。
/// 渲染时 App 按当前值确定性给出：阶段标题 / 颜色 / 长描述 / 百分比。
class TrackerFieldPresentation {
  const TrackerFieldPresentation({
    this.ranges = const [],
    this.states = const {},
  });

  final List<TrackerRangeDescription> ranges;
  final Map<String, TrackerEnumDescription> states;

  bool get hasRanges => ranges.isNotEmpty;
  bool get hasStates => states.isNotEmpty;

  factory TrackerFieldPresentation.fromJson(Map<String, dynamic> json) {
    final ranges = <TrackerRangeDescription>[];
    final rawRanges = json['ranges'];
    if (rawRanges is List) {
      for (final item in rawRanges) {
        final map = CharacterCardExtensionsReader.asMap(item);
        if (map != null) {
          final range = TrackerRangeDescription.fromJson(map);
          if (range.title.isNotEmpty || range.text.isNotEmpty) {
            ranges.add(range);
          }
        }
      }
    }
    final states = <String, TrackerEnumDescription>{};
    final rawStates = CharacterCardExtensionsReader.asMap(json['states']);
    if (rawStates != null) {
      rawStates.forEach((key, value) {
        if (key is String) {
          final map = CharacterCardExtensionsReader.asMap(value);
          if (map != null) {
            final state = TrackerEnumDescription.fromJson(map);
            if (state.title.isNotEmpty || state.text.isNotEmpty) {
              states[key] = state;
            }
          }
        }
      });
    }
    return TrackerFieldPresentation(ranges: ranges, states: states);
  }
}

/// v60：字段自主更新策略（updatePolicy）——把"模糊程度词 → 数值增量"
/// 定义为协议，模型/裁判据此确定性量化剧情变化，不再因没有数字而
/// 输出空 patch。
///
/// mode：
/// - `explicit`：只处理明确数值指令（（好感度+2）/好感度提高5），
///   不因剧情自行推断；
/// - `conservative`（推荐默认）：允许从非常明确的剧情结果推断小幅
///   变化（她接受了道歉、戒备明显放松 → +1），普通对话/心理描写/
///   重复描述不更新；
/// - `active`：允许根据整体剧情主动调整（共同战斗/赠送礼物/冲突等
///   都可能触发变化）。
class TrackerUpdatePolicy {
  const TrackerUpdatePolicy({
    this.mode = 'conservative',
    this.qualitativeDeltas = const {},
    this.maxAutoDeltaPerTurn,
    this.semanticHints,
  });

  /// explicit | conservative | active
  final String mode;

  /// 程度词 → 增量（如 {"一点": 1, "稍微": 2, "明显": 5, "大幅": 10}）
  final Map<String, num> qualitativeDeltas;

  /// 每轮自动增减上限（防膨胀；null 不限制）
  final num? maxAutoDeltaPerTurn;

  /// v63：字段语义提示——卡提供"理解方向"而非死规则：
  /// meaning（字段代表什么）/ positiveSignals（通常提升的行为）/
  /// negativeSignals（通常降低的行为）/ neutralSignals（不应触发
  /// 变化的行为）——注入状态裁判，让模型根据实际剧情自由判断，
  /// 但 App 仍限制未知字段/上下限/单轮上限/重复事件。
  final TrackerSemanticHints? semanticHints;

  factory TrackerUpdatePolicy.fromJson(Map<String, dynamic> json) {
    final deltas = <String, num>{};
    final rawDeltas = CharacterCardExtensionsReader.asMap(
      json['qualitativeDeltas'],
    );
    if (rawDeltas != null) {
      rawDeltas.forEach((k, v) {
        if (k is String && v is num) {
          deltas[k] = v;
        }
      });
    }
    final rawHints = CharacterCardExtensionsReader.asMap(
      json['semanticHints'],
    );
    return TrackerUpdatePolicy(
      mode: json['mode'] is String ? json['mode'] as String : 'conservative',
      qualitativeDeltas: deltas,
      maxAutoDeltaPerTurn: json['maxAutoDeltaPerTurn'] is num
          ? json['maxAutoDeltaPerTurn'] as num
          : null,
      semanticHints: rawHints == null
          ? null
          : TrackerSemanticHints.fromJson(rawHints),
    );
  }
}

/// v63：字段语义提示（updatePolicy.semanticHints）。
class TrackerSemanticHints {
  const TrackerSemanticHints({
    this.meaning = '',
    this.positiveSignals = const [],
    this.negativeSignals = const [],
    this.neutralSignals = const [],
  });

  /// 这个字段代表什么（剧情含义）
  final String meaning;
  /// 通常提升该字段的行为
  final List<String> positiveSignals;
  /// 通常降低该字段的行为
  final List<String> negativeSignals;
  /// 不应触发变化的行为（普通闲聊/重复描写等）
  final List<String> neutralSignals;

  factory TrackerSemanticHints.fromJson(Map<String, dynamic> json) {
    List<String> listOf(String key) {
      final raw = json[key];
      if (raw is List) {
        return raw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return const [];
    }

    return TrackerSemanticHints(
      meaning: json['meaning'] is String ? json['meaning'] as String : '',
      positiveSignals: listOf('positiveSignals'),
      negativeSignals: listOf('negativeSignals'),
      neutralSignals: listOf('neutralSignals'),
    );
  }
}

class TrackerFieldSchema {
  const TrackerFieldSchema({
    required this.type,
    this.label = '',
    this.min,
    this.max,
    this.hidden = false,
    this.presentation,
    this.aliases = const [],
    this.updatePolicy,
  });

  /// 'string' | 'number'
  final String type;
  final String label;
  final num? min;
  final num? max;
  final bool hidden;

  /// v52：阶段描述声明（ranges/states）——解析器不认识时保持 null，
  /// 渲染回退到纯数值/纯文本（旧卡完全不受影响）。
  final TrackerFieldPresentation? presentation;

  /// v60：字段别名（"好感"/"亲密感"/"信任" 等口语说法）——本地解析
  /// 与裁判判断时与 label/key 同等匹配。
  final List<String> aliases;

  /// v60：自主更新策略（程度词量化规则）。
  final TrackerUpdatePolicy? updatePolicy;

  bool get isNumber => type == 'number';

  factory TrackerFieldSchema.fromJson(Map<String, dynamic> json) {
    final rawPresentation = CharacterCardExtensionsReader.asMap(
      json['presentation'],
    );
    final rawPolicy = CharacterCardExtensionsReader.asMap(
      json['updatePolicy'],
    );
    final rawAliases = json['aliases'];
    final aliases = <String>[];
    if (rawAliases is List) {
      for (final item in rawAliases) {
        if (item is String && item.trim().isNotEmpty) {
          aliases.add(item.trim());
        }
      }
    }
    return TrackerFieldSchema(
      type: json['type'] is String ? json['type'] as String : 'string',
      label: json['label'] is String ? json['label'] as String : '',
      min: json['min'] is num ? json['min'] as num : null,
      max: json['max'] is num ? json['max'] as num : null,
      hidden: json['hidden'] is bool ? json['hidden'] as bool : false,
      presentation: rawPresentation == null
          ? null
          : TrackerFieldPresentation.fromJson(rawPresentation),
      aliases: aliases,
      updatePolicy: rawPolicy == null
          ? null
          : TrackerUpdatePolicy.fromJson(rawPolicy),
    );
  }
}

class TrackerAction {
  const TrackerAction({
    required this.id,
    required this.label,
    required this.prompt,
  });

  final String id;
  final String label;
  final String prompt;

  factory TrackerAction.fromJson(Map<String, dynamic> json) {
    return TrackerAction(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '动作',
      prompt: json['prompt'] as String? ?? '',
    );
  }
}

class TrackerConfig {
  const TrackerConfig({
    this.schemaVersion = 1,
    this.stateSchema = const {},
    this.initialState = const {},
    this.actions = const [],
    this.uiOrder = const [],
    this.template,
    this.defaultExpanded = false,
  });

  final int schemaVersion;
  final Map<String, TrackerFieldSchema> stateSchema;
  final Map<String, dynamic> initialState;
  final List<TrackerAction> actions;
  final List<String> uiOrder;
  final String? template;

  /// v54：状态面板初始是否展开（卡声明；默认收起）。
  final bool defaultExpanded;

  bool get isEnabled =>
      stateSchema.isNotEmpty || initialState.isNotEmpty || actions.isNotEmpty;

  /// 状态栏显示顺序：uiHints.order 优先，否则 schema 声明顺序，否则空。
  List<String> get displayOrder {
    if (uiOrder.isNotEmpty) {
      return List<String>.from(uiOrder);
    }
    return stateSchema.keys.toList(growable: false);
  }

  factory TrackerConfig.fromCardJson(Map<String, dynamic>? cardJson) {
    try {
      return _parseFromCardJson(cardJson);
    } catch (error) {
      // 任何未知卡结构都不允许崩溃（发消息/状态栏/组装全链路兜底）；
      // 打印日志便于排查卡声明格式问题
      debugPrint('[TrackerConfig] 卡声明解析失败，已降级为禁用配置: $error');
      return const TrackerConfig();
    }
  }

  static TrackerConfig _parseFromCardJson(Map<String, dynamic>? cardJson) {
    if (cardJson == null) {
      return const TrackerConfig();
    }
    // 统一读取器：兼容真实手机导入链路的运行时 map 类型
    // （Map<dynamic, dynamic> / 顶层已展开 data 等），避免某张卡
    // 因类型检查过严而静默降级为禁用配置（"所有卡样式都一样"）。
    final tracker = CharacterCardExtensionsReader.tracker(cardJson);
    if (tracker == null) {
      return const TrackerConfig();
    }

    final rawSchema = CharacterCardExtensionsReader.asMap(tracker['stateSchema']);
    final schema = <String, TrackerFieldSchema>{};
    if (rawSchema != null) {
      rawSchema.forEach((key, value) {
        final field = CharacterCardExtensionsReader.asMap(value);
        if (field != null) {
          schema[key] = TrackerFieldSchema.fromJson(field);
        } else if (value is String) {
          // 简写：{"energy": "number"} 直接给类型
          schema[key] = TrackerFieldSchema(type: value);
        }
      });
    }

    final rawInitial = CharacterCardExtensionsReader.asMap(
      tracker['initialState'],
    );
    final initialState = <String, dynamic>{};
    if (rawInitial != null) {
      initialState.addAll(rawInitial);
    }

    final rawActions = tracker['actions'];
    final actions = <TrackerAction>[];
    if (rawActions is List) {
      for (final item in rawActions) {
        final actionMap = CharacterCardExtensionsReader.asMap(item);
        if (actionMap == null) {
          continue;
        }
        final action = TrackerAction.fromJson(actionMap);
        if (action.id.isNotEmpty) {
          actions.add(action);
        }
      }
    }

    final rawUiHints = CharacterCardExtensionsReader.asMap(
      tracker['uiHints'],
    );
    final uiOrder = <String>[];
    if (rawUiHints != null) {
      final order = rawUiHints['order'];
      if (order is List) {
        for (final key in order) {
          if (key is String) {
            uiOrder.add(key);
          }
        }
      }
    }

    return TrackerConfig(
      schemaVersion: tracker['schemaVersion'] is int
          ? tracker['schemaVersion'] as int
          : 1,
      stateSchema: schema,
      initialState: initialState,
      actions: actions,
      uiOrder: uiOrder,
      // v54：template 兼容两个位置——tracker 顶层（推荐）优先，
      // uiHints.template（早期注释示例写法）兜底
      template: tracker['template'] is String
          ? tracker['template'] as String
          : (rawUiHints != null && rawUiHints['template'] is String
              ? rawUiHints['template'] as String
              : null),
      defaultExpanded:
          tracker['defaultExpanded'] is bool
              ? tracker['defaultExpanded'] as bool
              : false,
    );
  }
}
