import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pocket_inn/models/tracker_config.dart';

import 'character_card_extensions_reader.dart';

/// 特别版：状态跟踪（Tracker）运行时——LLM 输出解析 + reducer。
///
/// 模型只输出结构化 patch（不直接产 HTML）：
/// 1. JSON 形式（回复末尾 JSON 块，含 patch）：
///    ```json
///    {"patch": {"set": {"location": "旅馆"}, "add": {"energy": -3}},
///     "choices": [{"id": "rest", "label": "休息"}]}
///    ```
/// 2. STATE 兜底（模型 JSON 不稳时）：
///    `<STATE> location=旅馆 energy=-3 </STATE>`
///
/// reducer 语义：
/// - `set`：绝对值覆盖（字符串/数字皆可）
/// - `add`：数值叠加（仅 number 字段生效；字符串忽略）
/// - schema 校验：类型不匹配忽略、min/max clamp、未知字段仍保留（宽松）

/// v52：字段当前阶段信息（由 [TrackerRuntime.stageInfo] 按卡声明的
/// presentation.ranges/states 确定性解析，不依赖模型生成）。
class TrackerStageInfo {
  const TrackerStageInfo({
    this.title = '',
    this.color = '',
    this.text = '',
  });

  /// 阶段标题（如"明显改造"）
  final String title;
  /// 阶段颜色（如 #FFA726）
  final String color;
  /// 阶段长描述
  final String text;
}

/// 解析出的结构化 patch。
class StatePatch {
  StatePatch({
    this.setValues = const {},
    this.addValues = const {},
    /// 协议正文：JSON 输出含 "reply" 字段时，用它作为消息正文（
    /// 防止 {reply, patch} 结构正文丢失）。
    this.reply,
    /// v55：是否检测到状态协议（JSON `patch` 键或 `<STATE>` 块）。
    /// 用于区分"模型输出了合法空 patch（判断无变化）"与"模型完全没
    /// 有输出协议"——空 patch 的 set/add 为空，但 protocolDetected=true。
    this.protocolDetected = false,
  });

  final Map<String, dynamic> setValues;
  final Map<String, num> addValues;
  final String? reply;
  final bool protocolDetected;

  bool get isEmpty => setValues.isEmpty && addValues.isEmpty;
}

/// 模型输出的可选动作（choices）：显示为消息下方的动作按钮，
/// 点击后把动作作为事件发送给模型。与卡声明的静态 actions 不同，
/// choices 是模型每轮动态给出的可选项。
class DecisionChoice {
  const DecisionChoice({
    required this.id,
    required this.label,
    this.action = '',
  });

  final String id;
  final String label;

  /// 可选：点击时发送的具体指令（缺省用 label）
  final String action;

  factory DecisionChoice.fromJson(Map<String, dynamic> json) {
    return DecisionChoice(
      id: json['id'] is String ? json['id'] as String : '',
      label: json['label'] is String ? json['label'] as String : '动作',
      action: json['action'] is String ? json['action'] as String : '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (action.isNotEmpty) 'action': action,
      };
}

class TrackerRuntime {
  TrackerRuntime._();

  /// 从模型输出提取 patch。优先 JSON 块（含 patch.set/add），
  /// 失败回退 STATE 块。找不到返回空 patch。
  static StatePatch extractPatch(String text) {
    final jsonPatch = _extractJsonPatch(text);
    if (jsonPatch != null) {
      return jsonPatch;
    }
    return _extractStateBlockPatch(text);
  }

  /// 从模型输出提取 choices（可选动作按钮列表）。
  /// 遍历所有候选 JSON 块，取含 "choices" 数组的顶层字段。
  static List<DecisionChoice> extractChoices(String text) {
    final result = <DecisionChoice>[];
    for (final body in _allJsonBlocks(text)) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final choices = decoded['choices'];
        if (choices is! List) {
          continue;
        }
        for (final item in choices) {
          if (item is Map<String, dynamic>) {
            final choice = DecisionChoice.fromJson(item);
            if (choice.id.isNotEmpty || choice.label.isNotEmpty) {
              result.add(choice);
            }
          }
        }
        if (result.isNotEmpty) {
          return result;
        }
      } catch (_) {
        // 跳过解析失败的候选
      }
    }
    return result;
  }

  /// 收集文本中所有候选 JSON 块（围栏 + 裸含协议键的对象）。
  static List<String> _allJsonBlocks(String text) {
    final blocks = <String>[];
    final fenced = RegExp(
      r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
      caseSensitive: false,
    );
    for (final match in fenced.allMatches(text)) {
      blocks.add(match.group(1)!);
    }
    // 裸 JSON（含 reply/patch/choices 键）
    var probe = 0;
    while (probe < text.length) {
      final marker = _nextProtocolMarker(text, probe);
      if (marker < 0) {
        break;
      }
      final start = _backtrackToOpenBrace(text, marker);
      final end = _findBalancedJsonEnd(text, start);
      if (end <= start) {
        probe = marker + 1;
        continue;
      }
      blocks.add(text.substring(start, end + 1));
      probe = end + 1;
    }
    return blocks;
  }

  static int _nextProtocolMarker(String text, int from) {
    final patchIdx = text.indexOf('"patch"', from);
    final choiceIdx = text.indexOf('"choices"', from);
    final replyIdx = text.indexOf('"reply"', from);
    final indexes = [patchIdx, choiceIdx, replyIdx]
        .where((i) => i >= 0)
        .toList();
    return indexes.isEmpty ? -1 : indexes.reduce((a, b) => a < b ? a : b);
  }

  /// 从模型输出剥离状态块（JSON reply/patch 块 / <STATE> 块），返回显示文本。
  /// JSON 对象含顶层 "reply" 时用 reply 值替换整块（协议正文保留，
  /// 仅顶层字段识别，避免 patch 内同名状态字段误当正文）；
  /// 仅含 patch/choices 时删整块；无状态键的代码块原样保留。
  static String stripStateBlocks(String text) {
    var result = text;
    // <STATE> ... </STATE>（大小写不敏感、可带空格）
    result = result.replaceAll(
      RegExp(r'<\s*STATE\s*>[\s\S]*?<\s*/\s*STATE\s*>', caseSensitive: false),
      '',
    );
    // 1) 围栏 JSON 块（```json ... ``` 或 ``` ... ```）
    final fenced = RegExp(
      r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
      caseSensitive: false,
    );
    result = result.replaceAllMapped(fenced, (match) {
      final body = match.group(1) ?? '';
      final hasTrackerKey =
          body.contains('"patch"') ||
          body.contains('"choices"') ||
          body.contains('"reply"');
      if (!hasTrackerKey) {
        return match.group(0)!; // 普通 JSON 代码块原样保留（含围栏）
      }
      return _processJsonBlock(body);
    });
    // 2) 裸 JSON 对象（含 reply/patch/choices 键）：定位 + 平衡括号提取
    var probe = 0;
    while (probe < result.length) {
      final patchIdx = result.indexOf('"patch"', probe);
      final choiceIdx = result.indexOf('"choices"', probe);
      final replyIdx = result.indexOf('"reply"', probe);
      final indexes = [patchIdx, choiceIdx, replyIdx]
          .where((i) => i >= 0)
          .toList();
      if (indexes.isEmpty) {
        break;
      }
      final marker = indexes.reduce((a, b) => a < b ? a : b);
      final start = _backtrackToOpenBrace(result, marker);
      final end = _findBalancedJsonEnd(result, start);
      if (end <= start) {
        probe = marker + 1;
        continue;
      }
      final body = result.substring(start, end + 1);
      final replacement = _processJsonBlock(body);
      result = result.replaceRange(start, end + 1, replacement);
      probe = start + replacement.length;
    }
    return result.trim();
  }

  /// 处理单个 JSON 块：顶层含 reply → 返回 reply 正文；
  /// 顶层含 patch/choices → 删除；否则原样保留。
  /// 解析失败时保留原文（不误删普通正文；坏协议块至多露少量原文，
  /// 不会整块删除正文入库）。
  static String _processJsonBlock(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return body;
      }
      final hasTracker =
          decoded.containsKey('reply') ||
          decoded.containsKey('patch') ||
          decoded.containsKey('choices');
      if (!hasTracker) {
        return body; // 普通 JSON 代码块不动
      }
      final reply = decoded['reply'];
      return reply is String ? reply : '';
    } catch (_) {
      return body; // 解析失败保留原文（防误删普通正文）
    }
  }

  /// reducer：把 patch 应用到当前状态（先 set 后 add，schema 校验）。
  static Map<String, dynamic> reduce({
    required Map<String, dynamic> current,
    required StatePatch patch,
    required TrackerConfig config,
  }) {
    final next = Map<String, dynamic>.from(current);
    // set：绝对值覆盖
    patch.setValues.forEach((key, value) {
      final validated = _validate(key, value, config);
      if (validated != null) {
        next[key] = validated;
      }
    });
    // add：数值叠加（仅 number 字段；字符串字段忽略）。
    // 变量表值为 TEXT（SQLite），当前值可能是字符串数字，需 tryParse 后叠加。
    patch.addValues.forEach((key, delta) {
      final schema = config.stateSchema[key];
      if (schema != null && !schema.isNumber) {
        return; // 字符串字段忽略 add
      }
      final currentValue = next[key];
      num? base;
      if (currentValue is num) {
        base = currentValue;
      } else if (currentValue is String) {
        base = num.tryParse(currentValue);
      }
      if (base != null) {
        next[key] = _clamp(key, base + delta, config);
      } else {
        // 字段缺失：回退 initialState 再叠加；无初始值则直接用 delta
        final initial = config.initialState[key];
        final initialNum = initial is num
            ? initial
            : (initial is String ? num.tryParse(initial) : null);
        if (initialNum != null) {
          next[key] = _clamp(key, initialNum + delta, config);
        } else {
          next[key] = _clamp(key, delta, config);
        }
      }
    });
    return next;
  }

  /// 过滤 patch 中受保护字段：这些字段本轮已由旁白确定性修改（用户输入
  /// （烙印值+10）等）落地，模型若再次对同一字段输出 set/add 会重复叠加
  /// （20→30→40）。过滤后模型对本轮旁白字段的更新被忽略，其余字段照常。
  static StatePatch filterProtectedPatch(
    StatePatch patch,
    Set<String> protectedKeys,
  ) {
    if (protectedKeys.isEmpty) {
      return patch;
    }
    return StatePatch(
      setValues: {
        for (final e in patch.setValues.entries)
          if (!protectedKeys.contains(e.key)) e.key: e.value,
      },
      addValues: {
        for (final e in patch.addValues.entries)
          if (!protectedKeys.contains(e.key)) e.key: e.value,
      },
      reply: patch.reply,
      protocolDetected: patch.protocolDetected,
    );
  }

  /// v52：当前值对应的阶段信息（presentation 声明）——number 字段按
  /// ranges 分段匹配（gte <= v 且 v < lt；最后一段 lt 为 null 时兜底），
  /// string 字段按 states 枚举精确匹配。无声明/无匹配返回 null。
  static TrackerStageInfo? stageInfo(
    String key,
    dynamic value,
    TrackerConfig config,
  ) {
    final schema = config.stateSchema[key];
    if (schema == null || value == null) {
      return null;
    }
    final presentation = schema.presentation;
    if (presentation == null) {
      return null;
    }
    if (schema.isNumber) {
      final numValue = value is num ? value : num.tryParse('$value');
      if (numValue == null) {
        return null;
      }
      for (final range in presentation.ranges) {
        // 局部变量让 Dart 完成 null 类型提升（类字段不会提升）
        final gte = range.gte;
        final lt = range.lt;
        final inRange = (gte == null || numValue >= gte) &&
            (lt == null || numValue < lt);
        if (inRange) {
          return TrackerStageInfo(
            title: range.title,
            color: range.color,
            text: range.text,
          );
        }
      }
      // ranges 无匹配（如全部区间都有 lt 且值越界）→ 最后一段兜底
      if (presentation.ranges.isNotEmpty) {
        final last = presentation.ranges.last;
        return TrackerStageInfo(
          title: last.title,
          color: last.color,
          text: last.text,
        );
      }
      return null;
    }
    // string 字段：states 精确匹配
    final state = presentation.states['$value'];
    if (state == null) {
      return null;
    }
    return TrackerStageInfo(
      title: state.title,
      color: state.color,
      text: state.text,
    );
  }

  /// v52：number 字段的百分比文本（min/max 归一化；无 max 时返回原值）。
  static String _percentText(String key, dynamic value, TrackerConfig config) {
    final schema = config.stateSchema[key];
    if (schema == null || value == null) {
      return '';
    }
    final numValue = value is num ? value : num.tryParse('$value');
    if (numValue == null) {
      return '';
    }
    final min = schema.min ?? 0;
    final max = schema.max;
    if (max == null || max <= min) {
      return '$numValue';
    }
    final percent = ((numValue - min) / (max - min) * 100).round();
    return '$percent';
  }

  /// v52：HTML 转义——所有插入模板的文本值统一转义（长描述/阶段标题
  /// 可能含 `<`、`>`、`&`、引号，不转义会破坏模板结构或注入样式）。
  static String _htmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 用卡 StatusFallback 模板 + 变量表生成规范状态面板 HTML（service 层
  /// 保存消息快照与 UI 层运行时渲染共用同一套逻辑）。
  ///
  /// 值来源：会话变量优先，缺失回退卡 initialState；`{{getvar::key}}`
  /// 占位在生成时即替换为当时的具体值（快照不保留占位符，显示不依赖
  /// 当前全局变量——历史消息不会被最新状态污染）。
  ///
  /// 渲染策略（尊重卡样式）：
  /// - 模板是富 HTML（含标签）→ 直接返回清洗后的模板，不套 App 默认容器；
  /// - 模板是纯文本 → 套 App 默认容器（深色卡片）；
  /// - 卡无模板 → 内置字段 chips 卡片兜底。
  /// 返回 null 表示卡未启用/无任何可显示字段。
  static String? renderStatusPanelHtml({
    required Map<String, dynamic>? cardJson,
    required Map<String, String> variables,
  }) {
    final config = TrackerConfig.fromCardJson(cardJson);
    String? valueOf(String key) {
      final v = variables[key];
      if (v != null && v.isNotEmpty) {
        return v;
      }
      final init = config.initialState[key];
      return init == null ? null : '$init';
    }

    // ① 状态面板模板（卡内定义的状态栏样子），优先级：
    //    tracker.template → post_history_instructions 的 <!--panel--> HTML
    //    → StatusFallback.replaceString（纯文本兜底）。
    // 7 张卡的 HTML 面板都定义在 post_history_instructions 里
    // （<details><summary>…</summary><div style=…> 深色卡片），
    // StatusFallback 只是纯文本行——若只读 StatusFallback，所有卡
    // 都会退化成同一个紫色文字容器（"每张卡样式都一样"根因）。
    // getvar 检测大小写不敏感；模板渲染不依赖 tracker 是否解析成功。
    //
    // v58：模板选择"第一个**有效**"而非"第一个非 null"——卡声明的
    // uiHints.template 常是 "{label}：{value}" 占位文本（不含 get 变量），
    // 若优先命中它会截断 post_history_instructions 的真实 HTML 面板、
    // 掉进内置面板（v54 兼容 uiHints.template 后出现的渲染回归根因）。
    final templateCandidates = <(String, String?)>[
      ('tracker.template', config.template),
      ('post_history_instructions', postHistoryPanelTemplate(cardJson)),
      ('StatusFallback', statusFallbackTemplate(cardJson)),
    ];
    String? template;
    String templateSource = 'builtin';
    for (final (source, candidate) in templateCandidates) {
      if (_isValidStatusTemplate(candidate)) {
        template = candidate!.trim();
        templateSource = source;
        break;
      }
    }
    // v58：模板来源诊断日志——手机上确认读到的是哪个模板
    debugPrint(
      '[TRACKER_RENDER] source=$templateSource '
      'card=${cardJson?['data'] is Map ? (cardJson!['data'] as Map)['name'] : cardJson?['name']} '
      'html=${template != null && RegExp(r'<[a-zA-Z]').hasMatch(template)}',
    );
    // v52：模板检测扩展到所有展示变量（getvar/gettitle/gettext/getcolor/
    // getpercent 任一出现即视为模板）。
    if (template != null &&
        RegExp(
          r'get(var|title|text|color|percent)',
          caseSensitive: false,
        ).hasMatch(template)) {
      var rendered = template
          .replaceAll('{{match}}', '')
          .replaceAll(r'\n', '\n');
      // v52：统一替换展示变量——getvar 为原始值，gettitle/gettext/
      // getcolor 为当前阶段标题/长描述/颜色（presentation 声明），
      // getpercent 为 number 字段的百分比（min/max 归一，无 max 时原值）。
      // 所有插入 HTML 的文本统一 HTML 转义（长描述可能含 < > & 引号，
      // 不转义会破坏模板结构）。
      rendered = rendered.replaceAllMapped(
        RegExp(
          r'\{\{\s*(getvar|gettitle|gettext|getcolor|getpercent)::([^}]+)\}\}',
          caseSensitive: false,
        ),
        (m) {
          final kind = m.group(1)!.toLowerCase();
          final key = m.group(2)!.trim();
          switch (kind) {
            case 'gettitle':
              return _htmlEscape(stageInfo(key, valueOf(key), config)?.title ?? '');
            case 'gettext':
              return _htmlEscape(stageInfo(key, valueOf(key), config)?.text ?? '');
            case 'getcolor':
              return _htmlEscape(
                stageInfo(key, valueOf(key), config)?.color ?? '',
              );
            case 'getpercent':
              return _htmlEscape(_percentText(key, valueOf(key), config));
            default:
              return _htmlEscape(valueOf(key) ?? '');
          }
        },
      );
      rendered = _cleanStatusPanelText(rendered);
      if (rendered.trim().isNotEmpty) {
        // 富 HTML 模板直接渲染（尊重卡定义样式）；纯文本套默认容器
        if (RegExp(r'<[a-zA-Z][^>]*>').hasMatch(rendered)) {
          return rendered.trim();
        }
        return '<div class="status-panel" style="display:flex;'
            'flex-wrap:wrap;gap:6px 8px;align-items:center;padding:8px 10px;'
            'border-radius:10px;background:rgba(120,80,220,0.08);'
            'border:1px solid rgba(120,80,220,0.25);'
            'font-size:12px;">$rendered</div>';
      }
    }

    // 卡未启用（无 tracker 声明）且无模板 → 无状态面板
    if (!config.isEnabled) {
      return null;
    }

    // ② 内置深色卡片（卡无模板/无 getvar 时兜底）
    // v52：带 presentation 声明的字段渲染为块（阶段标题 + 长描述），
    // 其余字段保持紧凑 chips——"数值字段：进度+阶段描述；字符串字段：
    // 短值+描述"，不做成所有字段长段落。
    final parts = <String>[];
    for (final key in config.displayOrder) {
      final schema = config.stateSchema[key];
      if (schema == null || schema.hidden) {
        continue;
      }
      final value = valueOf(key);
      if (value == null) {
        continue;
      }
      final label = schema.label.isNotEmpty ? schema.label : key;
      // number 字段带 max → 显示 值/max（进度感）
      final display = (schema.type == 'number' && schema.max != null)
          ? '$value/${schema.max}'
          : value;
      final stage = stageInfo(key, value, config);
      final hasStage =
          stage != null && (stage.title.isNotEmpty || stage.text.isNotEmpty);
      // v54：number 字段带 min/max → 渲染为块 + 进度条（无需 stage 声明）；
      // 进度条颜色跟随阶段色（无阶段声明用默认紫）
      final isProgress =
          schema.isNumber && schema.max != null && schema.min != null;
      if (hasStage || isProgress) {
        final numValue = num.tryParse('$value');
        final pct =
            (numValue != null && schema.max != null && schema.min != null)
                ? (((numValue - schema.min!) /
                                (schema.max! - schema.min!)) *
                            100)
                        .clamp(0, 100)
                : null;
        final accent =
            (stage != null && stage.color.isNotEmpty) ? stage.color : '#b388ff';
        parts.add(
          '<div style="background:rgba(255,255,255,0.05);'
          'border-radius:8px;padding:6px 10px;margin:2px 0;width:100%;'
          'box-sizing:border-box;">'
          '<span style="font-size:12px;color:${_htmlEscape(accent)};'
          'font-weight:600;">$label：$display'
          '${stage != null && stage.title.isNotEmpty ? ' · ${_htmlEscape(stage.title)}' : ''}</span>'
          '${pct != null
              ? '<div style="height:4px;background:rgba(255,255,255,0.10);'
                  'border-radius:2px;margin-top:4px;overflow:hidden;">'
                  '<div style="height:100%;width:${pct}%;'
                  'background:${_htmlEscape(accent)};border-radius:2px;"></div></div>'
              : ''}'
          '${stage != null && stage.text.isNotEmpty
              ? '<div style="font-size:11px;color:rgba(255,255,255,0.55);'
                  'margin-top:2px;">${_htmlEscape(stage.text)}</div>'
              : ''}'
          '</div>',
        );
      } else {
        parts.add(
          '<span style="background:rgba(255,255,255,0.07);'
          'border:1px solid rgba(255,255,255,0.10);'
          'border-radius:999px;padding:2px 10px;font-size:12px;'
          'white-space:nowrap;">$label：$display</span>',
        );
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    return '<div class="status-panel" style="display:flex;flex-wrap:wrap;'
        'gap:6px 8px;align-items:center;padding:8px 10px;'
        'border-radius:10px;'
        'background:rgba(120,80,220,0.08);'
        'border:1px solid rgba(120,80,220,0.25);">'
        '<span style="font-size:12px;font-weight:600;color:#b388ff;">'
        '📊 状态</span>${parts.join('')}</div>';
  }

  /// v58：模板是否有效——非空且含至少一个展示变量
  /// （getvar/gettitle/gettext/getcolor/getpercent）。占位文本
  /// （如 "{label}：{value}"）或纯说明文字视为无效，跳过。
  static bool _isValidStatusTemplate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    return RegExp(
      r'\{\{\s*get(var|title|text|color|percent)::[^}]+\}\}',
      caseSensitive: false,
    ).hasMatch(value);
  }

  /// 面板文本统一清洗：去"状态栏未更新"前缀与 `{{match}}`。
  ///
  /// v49：`<summary>/<details>` **不再在此删除**——折叠标题（summary）与
  /// 折叠状态由显示层（message_bubble → SpecialStatusPanel）原生控制：
  /// 显示层先提取标题，再剥掉标签；服务层保留标签，保证标题信息不丢。
  /// HtmlWidget 对 details 渲染不可靠（v47 截图问题），因此折叠不用
  /// HTML 标签实现，而是 Flutter Stateful 折叠。
  static String _cleanStatusPanelText(String html) {
    return html
        .replaceAll('{{match}}', '')
        .replaceAll('状态栏未更新，当前：', '')
        .replaceAll('状态栏未更新，当前:', '')
        .replaceAll('状态栏未更新', '');
  }

  /// 从卡 `data.extensions.regex_scripts` 取 StatusFallback 的 replaceString
  /// 模板（各卡"状态栏样子"定义；含 `{{getvar::key}}` 占位）。
  ///
  /// 查找放宽（兼容真实卡数据变体）：
  /// - 统一读取器兼容运行时 map 类型（Map<dynamic, dynamic> 等）；
  /// - 脚本名大小写不敏感、允许首尾空格，兼容 `script_name`/`name` 键名；
  /// - 替换文本取 `replaceString`/`replace_string` 任一键。
  static String? statusFallbackTemplate(Map<String, dynamic>? cardJson) {
    final rawScripts = CharacterCardExtensionsReader.regexScripts(cardJson);
    if (rawScripts == null) {
      return null;
    }
    for (final value in rawScripts) {
      final script = CharacterCardExtensionsReader.asMap(value);
      if (script == null) {
        continue;
      }
      final name = (script['scriptName'] ??
              script['script_name'] ??
              script['name'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (name != 'statusfallback') {
        continue;
      }
      final replacement = (script['replaceString'] ??
              script['replace_string'] ??
              '')
          .toString();
      if (replacement.trim().isNotEmpty) {
        return replacement;
      }
    }
    return null;
  }

  /// 状态面板块解析：匹配 `<!--panel-->` 与 `<!--/panel-->` **独占整行**
  /// 的块（multiLine + 行首行尾锚点）。
  ///
  /// 角色卡说明句里可能"提到"字面 `<!--panel-->`（如"必须保留
  /// <!--panel--> 标记；数值用 {{getvar}} 引用…"）——若用非独占行的
  /// 非贪婪正则，会把这个假标记当面板起点，把说明尾巴一起截进模板。
  /// 独占整行要求让假标记（嵌在句中）不会被匹配为边界。
  static final RegExp _panelBlockPattern = RegExp(
    r'^[ \t]*<!--\s*panel\s*-->[ \t]*\r?\n'
    r'([\s\S]*?)'
    r'^[ \t]*<!--\s*/panel\s*-->[ \t]*$',
    caseSensitive: false,
    multiLine: true,
  );

  /// 从角色卡 `data.post_history_instructions` 提取 `<!--panel-->` 之间的
  /// **HTML 状态面板模板**（各卡真正定义的外观：`<details>/<summary>` +
  /// 深色 `<div style=...>` 卡片 + `{{getvar::key}}` 引用）。
  ///
  /// 只接受同时满足以下条件的块：
  /// - `<!--panel-->` 与 `<!--/panel-->` 各独占一整行；
  /// - 含 HTML 标签（div/span/details/summary）；
  /// - 含 `{{getvar::key}}` 占位。
  /// 不满足则返回 null（避免把 post_history_instructions 里的其他说明
  /// 文本当模板）。找不到时回退 StatusFallback 纯文本模板。
  static String? postHistoryPanelTemplate(Map<String, dynamic>? cardJson) {
    final data = CharacterCardExtensionsReader.cardData(cardJson);
    final source = data?['post_history_instructions']?.toString() ?? '';

    for (final match in _panelBlockPattern.allMatches(source)) {
      final candidate = match.group(1)?.trim() ?? '';
      final hasGetVar = RegExp(
        r'\{\{\s*getvar::[^}]+\}\}',
        caseSensitive: false,
      ).hasMatch(candidate);
      final hasHtml = RegExp(
        r'<(?:div|span|details|summary)\b',
        caseSensitive: false,
      ).hasMatch(candidate);
      if (candidate.isNotEmpty && hasGetVar && hasHtml) {
        return candidate;
      }
    }
    return null;
  }

  /// 从文本中剥离 `<!--panel-->...<!--/panel-->` 面板块（连同标记）。
  /// 与 [postHistoryPanelTemplate] 共用 [_panelBlockPattern]（独占整行
  /// 标记），保证提取与清理对面板边界的判定一致——说明句里嵌着的
  /// 字面 `<!--panel-->` 不会被误删。
  static String stripPanelTemplates(String text) {
    return text.replaceAll(_panelBlockPattern, '');
  }

  /// 用卡的 initialState 初始化状态（仅补缺失字段，不覆盖已有值）。
  static Map<String, dynamic> initState({
    required TrackerConfig config,
    Map<String, dynamic>? existing,
  }) {
    final result = Map<String, dynamic>.from(config.initialState);
    existing?.forEach((key, value) {
      result[key] = value; // 已有状态优先
    });
    return result;
  }

  /// 从模型输出的状态面板 HTML/文本解析 `label：值` 回写状态。
  /// 卡要求模型"输出面板"（而非 patch 协议）时，变量表也能随之更新。
  /// 容错：先转纯文本（`<br>`/块级标签→换行、剥标签、解 HTML 实体），
  /// 冒号可省略（`烙印值 35/100`）、label 前可有 emoji（`❤️ 烙印值`）、
  /// number 字段取数字部分、清洗尾部标点；
  /// 遍历 label 的**所有**出现位置，取第一个能解析出合法值的（避免
  /// `<span>烙印值：</span><b>35</b>` 这类结构因首次匹配失败而漏掉）。
  static Map<String, String> extractValuesFromPanelText(
    String panelHtml,
    TrackerConfig config,
  ) {
    final text = _htmlToPlainText(panelHtml);
    final out = <String, String>{};
    for (final entry in config.stateSchema.entries) {
      final key = entry.key;
      final schema = entry.value;
      final label = schema.label.isNotEmpty ? schema.label : key;
      final escaped = RegExp.escape(label);
      // 冒号可选；值到分隔符（· < | ， ； 换行）为止
      final re = RegExp('$escaped\\s*[:：]?\\s*([^·<|,，;；\\n]+)');
      String? resolved;
      for (final m in re.allMatches(text)) {
        var value = m.group(1)!.trim();
        // 去尾部标点（。！？！\u3001 等）与单位后缀前的斜杠
        value = value.replaceAll(RegExp(r'[。！？!？,，、\s]+$'), '');
        if (schema.type == 'number') {
          final num = RegExp(r'-?\d+(\.\d+)?').firstMatch(value);
          if (num == null) {
            continue;
          }
          value = num.group(0)!;
        }
        if (value.isEmpty) {
          continue;
        }
        resolved = value;
        break;
      }
      if (resolved != null) {
        out[key] = resolved;
      }
    }
    return out;
  }

  /// 解析旁白/用户消息里的确定性状态修改：
  /// `（烙印值+10）`、`（烙印值-5）`、`（烙印值=35）`、`（黑丝状态=破损）`、
  /// `(体力 +10)`、`（称呼阶段=本尊）`、自然语言 `烙印值提高40%` /
  /// `烙印值增加10` / `烙印值减少5`——label、字段 key 或卡声明 aliases
  /// 均匹配。v60：支持程度词（"好感提升一点"→ 按卡 updatePolicy 的
  /// qualitativeDeltas 确定性量化；**无卡声明不猜数字**）。
  /// 返回 key → (值, isAdd)；number 字段 +/- 视为增减，= 为赋值；
  /// string 字段仅 = 赋值（自然语言增减只支持 number 字段）。
  /// 括号格式优先：字段同时出现括号与自然语言时以括号为准。
  static Map<String, (String, bool)> parseNarrationStateChanges(
    String text,
    TrackerConfig config,
  ) {
    final out = <String, (String, bool)>{};
    for (final entry in config.stateSchema.entries) {
      final key = entry.key;
      final schema = entry.value;
      final label = schema.label.isNotEmpty ? schema.label : key;
      final names = <String>{label, key, ...schema.aliases};
      for (final name in names) {
        final escaped = RegExp.escape(name);
        final m = RegExp(
          '[（(]\\s*$escaped\\s*([+\\-]?=?|=)\\s*([^)）]+?)\\s*[）)]',
        ).firstMatch(text);
        if (m != null) {
          final op = m.group(1)!.trim();
          final rawValue = m.group(2)!.trim();
          if (rawValue.isNotEmpty) {
            if (schema.type == 'number') {
              final num = RegExp(r'-?\d+(\.\d+)?').firstMatch(rawValue);
              if (num != null) {
                if (op == '=') {
                  out[key] = (num.group(0)!, false);
                } else {
                  // +10 / -5 / 10（无符号视为增减）。负号可能被正则
                  // 捕获在 op 里而 rawValue 不含负号——必须合并，否则
                  // （烙印值-5）会被当成"增加 5"（v49 确认的 bug）。
                  final rawNum = num.group(0)!;
                  final signed = op == '-' && !rawNum.startsWith('-')
                      ? '-$rawNum'
                      : rawNum;
                  out[key] = (signed, true);
                }
                break;
              }
            } else {
              if (op == '=') {
                out[key] = (rawValue, false);
                break; // 字符串字段只接受赋值
              }
            }
          }
        }
        // 自然语言格式：仅 number 字段。语义——提高/增加/上升/加 = 增加，
        // 降低/减少/下降/减 = 减少；尾随 % 忽略（数值直接作为增量，
        // 与卡 schema 的 0-100 百分制一致）。
        if (schema.type == 'number') {
          final increase = RegExp(
            '$escaped\\s*(?:提高|增加|上升|加)\\s*([+-]?\\d+(?:\\.\\d+)?)\\s*%?',
          ).firstMatch(text);
          if (increase != null) {
            out[key] = (increase.group(1)!, true);
            break;
          }
          final decrease = RegExp(
            '$escaped\\s*(?:降低|减少|下降|减)\\s*(\\d+(?:\\.\\d+)?)\\s*%?',
          ).firstMatch(text);
          if (decrease != null) {
            out[key] = ('-${decrease.group(1)!}', true);
            break;
          }
          // v60：程度词量化——"好感提升一点"（无数字）按卡声明的
          // updatePolicy.qualitativeDeltas 确定性转换；无卡声明不猜。
          // 支持两种语序："好感明显提高"（程度词在前）与
          // "好感提高明显"（程度词在后）。
          final policy = schema.updatePolicy;
          if (policy != null && policy.qualitativeDeltas.isNotEmpty) {
            final words = policy.qualitativeDeltas.keys.toList()
              ..sort((a, b) => b.length.compareTo(a.length));
            final wordPattern = words.map(RegExp.escape).join('|');
            final increaseWord = RegExp(
              '$escaped\\s*(?:提高|提升|增加|上升|加)\\s*($wordPattern)',
            ).firstMatch(text);
            final increaseWord2 = RegExp(
              '$escaped\\s*($wordPattern)\\s*(?:提高|提升|增加|上升)',
            ).firstMatch(text);
            final wordMatch = increaseWord ?? increaseWord2;
            if (wordMatch != null) {
              final delta = policy.qualitativeDeltas[wordMatch.group(1)!]!;
              out[key] = ('${delta >= 0 ? delta : delta.abs()}', true);
              break;
            }
            final decreaseWord = RegExp(
              '$escaped\\s*(?:降低|减少|下降|减)\\s*($wordPattern)',
            ).firstMatch(text);
            final decreaseWord2 = RegExp(
              '$escaped\\s*($wordPattern)\\s*(?:降低|减少|下降)',
            ).firstMatch(text);
            final wordMatchDec = decreaseWord ?? decreaseWord2;
            if (wordMatchDec != null) {
              final delta = policy.qualitativeDeltas[wordMatchDec.group(1)!]!;
              out[key] = ('-${delta.abs()}', true);
              break;
            }
          }
        }
      }
    }
    return out;
  }

  /// HTML → 纯文本：`<br>`/块级结束标签转换行、剥标签、解常用实体。
  static String _htmlToPlainText(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(?:div|p|tr|li|summary|details|h[1-6])>',
              caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>', multiLine: true), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"');
  }

  /// v51：把旁白修改（（烙印值+10）等，已由 [parseNarrationStateChanges]
  /// 解析）应用到状态上——与 sendMessage 发送时旁白块同款逻辑：
  /// isAdd 走 addValues（reduce clamp），number 字段 = 赋值走 setValues
  /// （clamp），string 字段直接写入。返回更新后的状态副本。
  static Map<String, dynamic> applyNarrationChanges(
    Map<String, dynamic> state,
    Map<String, (String, bool)> narrationChanges,
    TrackerConfig config,
  ) {
    if (narrationChanges.isEmpty) {
      return Map<String, dynamic>.from(state);
    }
    var result = Map<String, dynamic>.from(state);
    for (final entry in narrationChanges.entries) {
      final key = entry.key;
      final (value, isAdd) = entry.value;
      if (isAdd) {
        final next = reduce(
          current: initState(config: config, existing: result),
          patch: StatePatch(addValues: {key: num.tryParse(value) ?? 0}),
          config: config,
        );
        result = next;
      } else {
        final schema = config.stateSchema[key];
        if (schema != null && schema.isNumber) {
          final next = reduce(
            current: initState(config: config, existing: result),
            patch: StatePatch(setValues: {key: num.tryParse(value) ?? 0}),
            config: config,
          );
          result = next;
        } else {
          result[key] = value;
        }
      }
    }
    return result;
  }

  /// v60：把 patch 应用到变量表（canonicalize + initState + reduce），
  /// 返回字符串化后的完整变量表——状态裁判（双阶段）合并 patch 用。
  static Map<String, String> applyPatchToVariables({
    required Map<String, String> variables,
    required StatePatch patch,
    required TrackerConfig config,
  }) {
    if (patch.isEmpty || !config.isEnabled) {
      return Map<String, String>.from(variables);
    }
    final (canonical, _) = canonicalizePatch(patch, config);
    final initialized = initState(config: config, existing: variables);
    final next = reduce(current: initialized, patch: canonical, config: config);
    return {
      for (final e in next.entries) e.key: '${e.value}',
    };
  }

  /// 把状态格式化为注入 prompt 的自然文本。
  static String formatStateText({
    required Map<String, dynamic> state,
    required TrackerConfig config,
  }) {
    if (state.isEmpty) {
      return '';
    }
    final order = config.displayOrder.isNotEmpty
        ? config.displayOrder
        : state.keys.toList(growable: false);
    final lines = <String>[];
    for (final key in order) {
      if (!state.containsKey(key)) {
        continue;
      }
      final value = state[key];
      if (value == null) {
        continue;
      }
      final schema = config.stateSchema[key];
      final label = (schema != null && schema.label.isNotEmpty)
          ? schema.label
          : key;
      lines.add('$label：$value');
    }
    // 未在 order 中但存在的字段追加
    for (final key in state.keys) {
      if (order.contains(key)) {
        continue;
      }
      final value = state[key];
      if (value == null) {
        continue;
      }
      final schema = config.stateSchema[key];
      final label = (schema != null && schema.label.isNotEmpty)
          ? schema.label
          : key;
      lines.add('$label：$value');
    }
    if (lines.isEmpty) {
      return '';
    }
    return '【当前状态】\n${lines.join('\n')}';
  }

  /// v50：模型注入专用状态指令——**显式列出真实 key 与 label 的映射**。
  ///
  /// v49 之前只注入中文 label（`烙印值：0`），模型即使按剧情输出了
  /// `{"add":{"烙印值":10}}` 也会被当成新变量保存、面板仍读 `yw_brand`
  /// （"剧情推进不更新"根因）。这里每行给出
  /// `key=yw_brand | label=烙印值 | type=number | range=0..100 | current=0`，
  /// 并强制模型在 patch 里只能使用 key。
  ///
  /// v60：追加 updatePolicy 定性规则（程度词 → 增量 / mode / 每轮上限）
  /// 与防膨胀约束——剧情明确表示上升/下降即使无数字也必须输出 patch，
  /// 不得因用户未给数字而返回空 patch。
  static String formatTrackerInstruction({
    required Map<String, dynamic> state,
    required TrackerConfig config,
  }) {
    if (state.isEmpty) {
      return '';
    }
    final order = config.displayOrder.isNotEmpty
        ? config.displayOrder
        : state.keys.toList(growable: false);
    final fields = <String>[];
    void addField(String key) {
      final value = state[key];
      if (value == null) {
        return;
      }
      final schema = config.stateSchema[key];
      final label = (schema != null && schema.label.isNotEmpty)
          ? schema.label
          : key;
      final range = (schema != null && schema.isNumber)
          ? ' | range=${schema.min ?? '-inf'}..${schema.max ?? '+inf'}'
          : '';
      final type = schema?.type ?? 'string';
      var line = '- key=$key | label=$label | type=$type$range | current=$value';
      // v60：注入定性规则（程度词量化 + 每轮上限）——"好感提升一点"
      // 模型据此确定性输出增量
      final policy = schema?.updatePolicy;
      if (policy != null && policy.qualitativeDeltas.isNotEmpty) {
        final deltas = policy.qualitativeDeltas.entries
            .map((e) => '${e.key}=${e.value}')
            .join('，');
        line += '\n  qualitative: $deltas';
      }
      if (policy != null && policy.maxAutoDeltaPerTurn != null) {
        line += '\n  maxAutoDeltaPerTurn=${policy.maxAutoDeltaPerTurn}';
      }
      if (policy != null) {
        line += '\n  mode=${policy.mode}';
      }
      fields.add(line);
    }

    for (final key in order) {
      addField(key);
    }
    for (final key in state.keys) {
      if (!order.contains(key)) {
        addField(key);
      }
    }
    if (fields.isEmpty) {
      return '';
    }
    return '【当前状态】（以下 key 是状态字段的唯一标识，'
        'JSON patch 中只能使用 key，禁止使用中文 label）\n'
        '${fields.join('\n')}\n'
        '（v60 状态判断规则：当剧情明确表示某字段上升或下降时，'
        '即使没有给出具体数字，也必须按 qualitative 中最匹配的程度词'
        '输出增量（下降用负数）；**不得因为用户没有提供精确数字而返回'
        '空 patch**。mode=explicit 时只处理明确状态描述；'
        'mode=conservative 时只从非常明确的剧情结果推断小幅变化，'
        '普通对话/心理描写/重复描述不更新；mode=active 时可根据整体'
        '剧情主动调整。同一事件每轮最多更新一次，每轮增量不超过'
        'maxAutoDeltaPerTurn（未声明则不限制）。）';
  }

  /// v50：patch 字段名规范化——模型可能输出中文 label（`烙印值`）而不是
  /// 真实 key（`yw_brand`）。label 精确匹配映射回 key；完全未知的字段
  /// 直接丢弃（避免被 reducer 当成新变量保存、污染变量表）。
  /// 返回 (规范化 patch, 被丢弃的字段列表)。
  /// 卡未启用 tracker（无 schema）时原样返回——自定义 patch 变量宽松保留。
  static (StatePatch, List<String>) canonicalizePatch(
    StatePatch patch,
    TrackerConfig config,
  ) {
    if (patch.isEmpty || !config.isEnabled) {
      return (patch, const []);
    }
    final dropped = <String>[];
    String? canonical(String raw) {
      final value = raw.trim();
      if (config.stateSchema.containsKey(value)) {
        return value;
      }
      for (final entry in config.stateSchema.entries) {
        if (entry.value.label.trim() == value) {
          return entry.key;
        }
      }
      return null;
    }

    final setValues = <String, dynamic>{};
    final addValues = <String, num>{};
    patch.setValues.forEach((k, v) {
      final key = canonical(k);
      if (key != null) {
        setValues[key] = v;
      } else {
        dropped.add(k);
      }
    });
    patch.addValues.forEach((k, v) {
      final key = canonical(k);
      if (key != null) {
        addValues[key] = v;
      } else {
        dropped.add(k);
      }
    });
    return (
      StatePatch(
        setValues: setValues,
        addValues: addValues,
        reply: patch.reply,
        protocolDetected: patch.protocolDetected,
      ),
      dropped,
    );
  }

  // ---- 内部 ----

  static dynamic _validate(String key, dynamic value, TrackerConfig config) {
    final schema = config.stateSchema[key];
    if (schema != null) {
      if (schema.isNumber) {
        final numValue = value is num ? value : num.tryParse('$value');
        if (numValue == null) {
          return value; // 非数字值保留（宽松）
        }
        if (!numValue.isFinite) {
          return null; // Infinity/NaN 拒绝写入
        }
        return _clamp(key, numValue, config);
      }
      return value is String ? value : '$value';
    }
    return value; // 未声明字段宽松保留
  }

  static num _clamp(String key, num value, TrackerConfig config) {
    if (!value.isFinite) {
      // Infinity/NaN 兜底：丢弃并钳到下限（有 schema 时）
      final schema = config.stateSchema[key];
      return schema?.min ?? 0;
    }
    final schema = config.stateSchema[key];
    if (schema == null) {
      return value;
    }
    var result = value;
    if (schema.min != null && result < schema.min!) {
      result = schema.min!;
    }
    if (schema.max != null && result > schema.max!) {
      result = schema.max!;
    }
    return result;
  }

  /// JSON patch 提取：找 ```json 块或裸 JSON 对象含 "patch"/"choices" 的。
  static StatePatch? _extractJsonPatch(String text) {
    final candidates = <String>[];
    final fenced = RegExp(
      r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
      caseSensitive: false,
    );
    for (final match in fenced.allMatches(text)) {
      candidates.add(match.group(1)!);
    }
    // 裸 JSON 对象（非代码块）
    if (candidates.isEmpty) {
      final markerIdx = text.indexOf('"patch"');
      var probe = markerIdx;
      if (probe < 0) {
        probe = text.indexOf('"choices"');
      }
      if (probe >= 0) {
        final start = _backtrackToOpenBrace(text, probe);
        final end = _findBalancedJsonEnd(text, start);
        if (end > start) {
          candidates.add(text.substring(start, end + 1));
        }
      }
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final patchRaw = decoded['patch'];
        final setValues = <String, dynamic>{};
        final addValues = <String, num>{};
        // v55：只要 JSON 含 "patch" 键即视为协议出现（空 patch 也算）——
        // 区分"模型输出了合法空 patch（判断无变化）"与"没输出协议"
        var protocolDetected = decoded.containsKey('patch');
        if (patchRaw is Map<String, dynamic>) {
          final set = patchRaw['set'];
          if (set is Map<String, dynamic>) {
            set.forEach((k, v) => setValues[k] = v);
          }
          final add = patchRaw['add'];
          if (add is Map<String, dynamic>) {
            add.forEach((k, v) {
              final numValue = v is num ? v : num.tryParse('$v');
              if (numValue != null && numValue.isFinite) {
                addValues[k] = numValue;
              }
            });
          }
        }
        if (protocolDetected || setValues.isNotEmpty || addValues.isNotEmpty) {
          // 协议正文：JSON 含 "reply" 字段时一并携带（防止正文丢失）
          final reply = decoded['reply'];
          return StatePatch(
            setValues: setValues,
            addValues: addValues,
            reply: reply is String && reply.isNotEmpty ? reply : null,
            protocolDetected: protocolDetected,
          );
        }
      } catch (_) {
        // JSON 解析失败继续下一个候选
      }
    }
    return null;
  }

  /// 从 [markerIdx]（指向某键名）向前回溯到所属 JSON 对象起始 '{'。
  /// 找不到返回 markerIdx（后续平衡扫描自然失败）。
  static int _backtrackToOpenBrace(String text, int markerIdx) {
    var depth = 0;
    for (var i = markerIdx - 1; i >= 0; i--) {
      final c = text[i];
      if (c == '}') {
        depth++;
      } else if (c == '{') {
        if (depth == 0) {
          return i;
        }
        depth--;
      }
    }
    return markerIdx;
  }

  /// 从 [start]（指向 '{'）扫描平衡 JSON 大括号的结束索引。
  /// 处理字符串转义与嵌套；找不到返回 start。
  static int _findBalancedJsonEnd(String text, int start) {
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    return start;
  }

  /// <STATE> key=value 兜底解析。纯数字绝对值；+n/-n 增量；其余字符串。
  static StatePatch _extractStateBlockPatch(String text) {
    final block = RegExp(
      r'<\s*STATE\s*>([\s\S]*?)<\s*/\s*STATE\s*>',
      caseSensitive: false,
    );
    final match = block.firstMatch(text);
    if (match == null) {
      return StatePatch();
    }
    final body = match.group(1) ?? '';
    final setValues = <String, dynamic>{};
    final addValues = <String, num>{};
    final pairs = RegExp(r'([A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*([^\s]+)');
    for (final pair in pairs.allMatches(body)) {
      final key = pair.group(1)!;
      final raw = pair.group(2)!;
      if (RegExp(r'^[+-]\d+(\.\d+)?$').hasMatch(raw)) {
        final parsed = num.tryParse(raw);
        if (parsed != null && parsed.isFinite) {
          addValues[key] = parsed;
        }
      } else if (RegExp(r'^\d+(\.\d+)?$').hasMatch(raw)) {
        final parsed = num.tryParse(raw);
        if (parsed != null && parsed.isFinite) {
          setValues[key] = parsed;
        } else {
          setValues[key] = raw;
        }
      } else {
        setValues[key] = raw;
      }
    }
    return StatePatch(
      setValues: setValues,
      addValues: addValues,
      // v55：STATE 块出现即视为协议
      protocolDetected: true,
    );
  }
}
