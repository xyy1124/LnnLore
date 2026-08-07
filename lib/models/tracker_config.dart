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
///   "uiHints": {"order": ["location", "energy"], "template": "<div>…</div>"}
/// }
/// ```
/// 卡只负责声明；解析/校验/reducer/渲染全部由 App 运行时执行。

class TrackerFieldSchema {
  const TrackerFieldSchema({
    required this.type,
    this.label = '',
    this.min,
    this.max,
    this.hidden = false,
  });

  /// 'string' | 'number'
  final String type;
  final String label;
  final num? min;
  final num? max;
  final bool hidden;

  bool get isNumber => type == 'number';

  factory TrackerFieldSchema.fromJson(Map<String, dynamic> json) {
    return TrackerFieldSchema(
      type: json['type'] is String ? json['type'] as String : 'string',
      label: json['label'] is String ? json['label'] as String : '',
      min: json['min'] is num ? json['min'] as num : null,
      max: json['max'] is num ? json['max'] as num : null,
      hidden: json['hidden'] is bool ? json['hidden'] as bool : false,
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
  });

  final int schemaVersion;
  final Map<String, TrackerFieldSchema> stateSchema;
  final Map<String, dynamic> initialState;
  final List<TrackerAction> actions;
  final List<String> uiOrder;
  final String? template;

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
      template: tracker['template'] is String
          ? tracker['template'] as String
          : null,
    );
  }
}
