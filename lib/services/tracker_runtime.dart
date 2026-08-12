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

  /// v70：<TRACKER_UPDATE> 标记块——快速模式正文与状态协议分离：
  /// 正文正常输出，末尾追加标记块（不把长篇正文塞进 JSON reply）。
  static const String kTrackerUpdateOpenTag = '<TRACKER_UPDATE>';
  static const String kTrackerUpdateCloseTag = '</TRACKER_UPDATE>';

  /// v82：标签匹配放宽——大小写不敏感、允许标签内空白（模型可能输出
  /// `<tracker_update>`/`<TRACKER_UPDATE >` 等变体），避免协议块残留正文。
  static final RegExp _trackerOpenRe =
      RegExp(r'<\s*TRACKER_UPDATE\s*>', caseSensitive: false);
  static final RegExp _trackerCloseRe =
      RegExp(r'<\s*/\s*TRACKER_UPDATE\s*>', caseSensitive: false);

  /// v70：从响应中提取裁判可选输出的最终状态 "state" 字段——
  /// `{"state":{"字段key":最终值}}`，App 检测到后按最终值一次性 set
  /// （不再增量叠加）。key 经 [canonicalizeNarrative] 规范化（label/
  /// 别名 → 真实 key）。无 state 字段返回空表。
  static Map<String, String> extractFinalState(
    String text,
    TrackerConfig config,
  ) {
    // 先扫候选 JSON 块（代码块/含协议键的裸对象）
    for (final body in _allJsonBlocks(text)) {
      final result = _finalStateFromBody(body, config);
      if (result.isNotEmpty) {
        return result;
      }
    }
    // 兜底：裸 "state" 键（裁判可能不包代码块、无其他协议键）
    final markerIdx = text.indexOf('"state"');
    if (markerIdx >= 0) {
      final start = _backtrackToOpenBrace(text, markerIdx);
      final end = _findBalancedJsonEnd(text, start);
      if (end > start) {
        final result = _finalStateFromBody(
          text.substring(start, end + 1),
          config,
        );
        if (result.isNotEmpty) {
          return result;
        }
      }
    }
    return const <String, String>{};
  }

  static Map<String, String> _finalStateFromBody(
    String body,
    TrackerConfig config,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const {};
      }
      final raw = decoded['state'];
      if (raw is! Map<String, dynamic>) {
        return const {};
      }
      final result = <String, String>{};
      raw.forEach((k, v) {
        final key = canonicalTrackerKey('$k', config);
        if (key != null && v != null) {
          result[key] = '$v';
        }
      });
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// v70：从文本中提取 <TRACKER_UPDATE>...</TRACKER_UPDATE> 标记块。
  /// 返回 (标记内 JSON 文本, 标记前正文)；无标记返回 (null, 原文本)。
  /// v82：标签匹配改为大小写不敏感 + 允许空白（<tracker_update>、
  /// <TRACKER_UPDATE > 等变体都能识别剥离），防止协议块残留正文。
  static (String?, String) extractTrackerUpdateBlock(String text) {
    final openMatches = _trackerOpenRe.allMatches(text).toList();
    if (openMatches.isEmpty) {
      return (null, text);
    }
    final openMatch = openMatches.last;
    final rest = text.substring(openMatch.end);
    final closeMatch = _trackerCloseRe.firstMatch(rest);
    if (closeMatch == null) {
      return (null, text);
    }
    final jsonText = rest.substring(0, closeMatch.start).trim();
    final displayText = text.substring(0, openMatch.start).trim();
    return (jsonText, displayText);
  }

  /// 从模型输出提取 patch。优先 <TRACKER_UPDATE> 标记（v70 快速模式
  /// 新协议），再 JSON 块（含 patch.set/add），失败回退 STATE 块。
  /// 找不到返回空 patch。
  /// v82：标记内 JSON 解析失败时，回退解析用**剥离后的正文**（displayText），
  /// 避免把坏标记块当 JSON 块捡到。
  static StatePatch extractPatch(String text) {
    final (markerJson, displayText) = extractTrackerUpdateBlock(text);
    if (markerJson != null) {
      try {
        final decoded = jsonDecode(markerJson);
        if (decoded is Map<String, dynamic>) {
          final patch = _patchFromDecoded(decoded);
          if (patch != null) {
            return patch;
          }
        }
      } catch (_) {
        // 标记内 JSON 解析失败 → 回退 JSON 块解析（兼容旧协议）
      }
    }
    final fallback = markerJson != null ? displayText : text;
    final jsonPatch = _extractJsonPatch(fallback);
    if (jsonPatch != null) {
      return jsonPatch;
    }
    return _extractStateBlockPatch(fallback);
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
      // v65：string 字段 allowCustomValues=false 时，只接受 presentation.states
      // 中声明的枚举值——模型自创未声明状态被拒绝（保持原值）。
      final schema = config.stateSchema[key];
      if (schema != null && !schema.isNumber && !schema.allowCustomValues) {
        final states = schema.presentation?.states;
        if (states != null && !states.containsKey('$value')) {
          return; // 拒绝写入，保留当前值
        }
      }
      final validated = _validate(key, value, config);
      if (validated != null) {
        next[key] = validated;
      }
    });
    // add：数值叠加（仅 number 字段；字符串字段忽略）。
    // 变量表值为 TEXT（SQLite），当前值可能是字符串数字，需 tryParse 后叠加。
    // v78：与 v73 裁判路径一致——同一字段 set 与 add 同时出现时忽略 add
    // （v73 只修了裁判 finalState 路径，快速模式主模型 marker 内
    // {"set":30,"add":5} 会双计成 35）。
    final setKeys = patch.setValues.keys.toSet();
    patch.addValues.forEach((key, delta) {
      if (setKeys.contains(key)) {
        return;
      }
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
      // v78：双向越界兜底——值低于所有区间下限取第一段（最低阶段），
      // 高于所有区间上限取最后一段（最高阶段）。此前无匹配一律取
      // 最后一段，数值低于首段 gte 时阶段标题/描述完全颠倒。
      // v79：按 gte 升序排序后再取首尾（gte null 视为负无穷）——
      // 卡声明 ranges 乱序时数组首尾可能不是最低/最高阶段。
      if (presentation.ranges.isNotEmpty) {
        final sorted = List<TrackerRangeDescription>.of(presentation.ranges)
          ..sort((a, b) {
            final ag = a.gte;
            final bg = b.gte;
            if (ag == null && bg == null) {
              return 0;
            }
            if (ag == null) {
              return -1;
            }
            if (bg == null) {
              return 1;
            }
            return ag.compareTo(bg);
          });
        final first = sorted.first;
        if (first.gte != null && numValue < first.gte!) {
          return TrackerStageInfo(
            title: first.title,
            color: first.color,
            text: first.text,
          );
        }
        final last = sorted.last;
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
    /// v63：本轮动态解读（消息快照 v4 携带，按字段）——`{{getnarrative::key}}`
    /// 优先用它；无则回退静态阶段描述（gettext）。
    Map<String, String>? narrative,
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
    // v77：兜底清洗——tracker.template 可能混入 PHI 指令文本残留
    // （"带 <!--panel--> 标记；数值用 {{getvar}} 引用，不得编造）：" 前缀
    // + <!--panel--> 块——9 张卡批量补 template 时把说明尾巴带进来了），
    // 直接整段渲染会把指令文本显示在状态栏里。清洗两步：
    // ① 有独占整行 <!--panel--> 块 → 提取块内 HTML（与
    //    postHistoryPanelTemplate 同边界，防说明句里的假标记）；
    // ② 剥离无 ::key 的裸 {{getvar}}/{{gettitle}} 等引用（渲染残留）。
    if (template != null) {
      final panelMatch = _panelBlockPattern.firstMatch(template);
      if (panelMatch != null) {
        final inner = panelMatch.group(1)?.trim() ?? '';
        if (_isValidStatusTemplate(inner)) {
          template = inner;
        }
      }
      // 无 panel 块时兜底提取 <details>…</details>（模板里的说明行
      // 与面板本体混在一起时只保留面板）。
      if (template.contains('<details>')) {
        final ds = template.indexOf('<details>');
        final de = template.lastIndexOf('</details>');
        if (de > ds) {
          final inner = template.substring(ds, de + '</details>'.length).trim();
          if (_isValidStatusTemplate(inner)) {
            template = inner;
          }
        }
      }
      template = template.replaceAll(
        RegExp(
          r'\{\{\s*get(var|title|text|color|percent|narrative)\s*\}\}',
          caseSensitive: false,
        ),
        '',
      );
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
          r'get(var|title|text|color|percent|narrative)',
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
          r'\{\{\s*(getvar|gettitle|gettext|getcolor|getpercent|getnarrative)::([^}]+)\}\}',
          caseSensitive: false,
        ),
        (m) {
          final kind = m.group(1)!.toLowerCase();
          final key = m.group(2)!.trim();
          switch (kind) {
            case 'gettitle':
              // v65：string 字段未匹配 presentation.states 时回退原始值
              // ——模型自创自由组合状态（"乳贴脱落、衣物凌乱"）也能显示
              // 标题，不再留下"· 空"。
              final stage = stageInfo(key, valueOf(key), config);
              if (stage?.title.trim().isNotEmpty == true) {
                return _htmlEscape(stage!.title.trim());
              }
              final schema = config.stateSchema[key];
              if (schema != null && !schema.isNumber) {
                return _htmlEscape(valueOf(key) ?? '');
              }
              return '';
            case 'gettext':
              return _htmlEscape(stageInfo(key, valueOf(key), config)?.text ?? '');
            case 'getcolor':
              return _htmlEscape(
                stageInfo(key, valueOf(key), config)?.color ?? '',
              );
            case 'getpercent':
              return _htmlEscape(_percentText(key, valueOf(key), config));
            case 'getnarrative':
              // v63：本轮动态解读优先，无则回退静态阶段描述。
              // v65：string 未匹配时回退原始值（不留下空解读）。
              final n = narrative?[key];
              if (n != null && n.trim().isNotEmpty) {
                return _htmlEscape(n.trim());
              }
              final stage = stageInfo(key, valueOf(key), config);
              if (stage?.text.trim().isNotEmpty == true) {
                return _htmlEscape(stage!.text.trim());
              }
              final schema = config.stateSchema[key];
              if (schema != null && !schema.isNumber) {
                return _htmlEscape(valueOf(key) ?? '');
              }
              return '';
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
      r'\{\{\s*get(var|title|text|color|percent|narrative)::[^}]+\}\}',
      caseSensitive: false,
    ).hasMatch(value);
  }

  /// v61：状态协议输出指令（固定尾部）——与状态字段列表拼装成完整
  /// 状态指令。抽为常量供上下文用量估算共用（避免估算漏算）。
  /// v66：协议增加 narrative（快速模式：主模型一次输出 reply+patch+
  /// narrative，不再需要第二次裁判请求）。
  /// v68：示例改为**合法 JSON**（不再用"字段key/数值变化"等无法解析的
  /// 中文占位值——模型照抄示例会导致 jsonDecode 失败、patch 提取不到）。
  /// v69：明确禁止在 reply 中输出 HTML/纯文本状态栏——面板由 App 按
  /// 最终状态自动渲染，模型只输出剧情 JSON。
  static const String kTrackerProtocolSuffix =
      '（本条回复末尾必须用 JSON 代码块输出结构化状态更新，格式：\n'
      '```json\n'
      '{\n'
      '  "reply": "剧情正文",\n'
      '  "patch": {\n'
      '    "set": {},\n'
      '    "add": {}\n'
      '  },\n'
      '  "narrative": {},\n'
      '  "consequence": {}\n'
      '}\n'
      '```\n'
      '【字段更新方式】number 字段增减写入 add（例如某好感字段增加 2 时写 '
      '"add":{"该字段key":2}）；string 字段变化写入 set（例如某状态字段变为'
      '新状态时写 "set":{"该字段key":"新状态"}）。JSON 中禁止使用'
      '"字段key""数值变化"等占位文字。\n'
      'reply 只写剧情正文；patch 只使用上方列出的 key。状态有变化就如实'
      '输出；没有变化也必须输出空 patch（"patch":{"set":{},"add":{}}）。\n'
      'narrative 中凡是 patch 修改过的字段都必须给出解读（一句话，结合本轮'
      '实际发生的事件；只能使用字段 key，禁止中文 label）。\n'
      'consequence 与 narrative 覆盖相同字段——说明该状态下一轮应如何'
      '影响角色行为（持续状态的保持要求/反转条件）。\n'
      '【v69 最高优先级规则】\n'
      '- reply 只写剧情正文。\n'
      '- 禁止在 reply 中输出任何状态栏。\n'
      '- 禁止输出 <details>、<summary>、<!--panel-->、状态栏 HTML。\n'
      '- 禁止输出"当前状态：""状态面板：""状态栏："等纯文本状态栏。\n'
      '- 状态栏由 App 根据最终状态自动渲染。\n'
      '- patch、narrative、consequence 必须放在同一个 JSON 对象中。）';

  /// v67：状态对剧情的约束指令（固定尾部）——让状态成为"下一轮剧情的
  /// 驱动器"而非"剧情后的记录器"：模型不只读到数值标签，还被要求把
  /// 当前状态作为已发生的剧情事实持续体现在正文中。
  static const String kTrackerStoryInfluenceSuffix =
      '[状态对剧情的约束]\n'
      '- 当前状态是已经发生的剧情事实，不是仅供展示的备注。\n'
      '- 正文必须通过动作、语言、身体反应、态度和环境结果自然体现相关状态。\n'
      '- 不要机械复述数值或状态栏文字。\n'
      '- 不得无视、重置或无理由逆转当前状态。\n'
      '- 状态发生变化时，正文必须包含足以支持该变化的实际事件。\n'
      '- 如果用户行为与当前状态冲突，应描写合理的抵抗、过渡或转变，'
      '并输出对应 patch。\n'
      '- 没有明确恢复事件时，服装、伤势、关系、位置等连续状态必须保持。';

  /// v70：后台/严格模式的主模型指令——只要求正文体现状态，**禁止输出
  /// 任何状态协议**（状态判断由独立裁判完成）。单一写入者：快速=主模型，
  /// 后台/严格=裁判。
  static const String kStoryOnlySuffix =
      '[状态输出规则]\n'
      '- 当前状态必须自然影响剧情。\n'
      '- 只输出剧情正文。\n'
      '- 禁止输出 JSON、STATE、HTML、状态栏或状态面板。\n'
      '- 状态判断由独立裁判完成，你不需要输出任何状态更新。';

  /// v70：快速模式的内联状态协议——正文正常输出，末尾追加标记块
  /// （不把长篇正文塞进 JSON reply——转义/截断导致整个对象无法解析，
  /// 快速模式 patch 随机失败的根因）。
  static const String kInlineTrackerProtocolSuffix =
      '（正文正常输出；正文结束后，在本条回复末尾用以下标记追加状态'
      '更新（不要包裹在正文里）：\n'
      '<TRACKER_UPDATE>\n'
      '{\n'
      '  "patch": {\n'
      '    "set": {},\n'
      '    "add": {}\n'
      '  },\n'
      '  "narrative": {},\n'
      '  "consequence": {}\n'
      '}\n'
      '</TRACKER_UPDATE>\n'
      '【字段更新方式】number 字段增减写入 add（例如某好感字段增加 2 时写 '
      '"add":{"该字段key":2}）；string 字段变化写入 set（例如某状态字段变为'
      '新状态时写 "set":{"该字段key":"新状态"}）。JSON 中禁止使用'
      '"字段key""数值变化"等占位文字。\n'
      'patch 只使用上方列出的 key。状态有变化就如实输出；没有变化也必须'
      '输出空 patch（"patch":{"set":{},"add":{}}）。\n'
      'narrative 中凡是 patch 修改过的字段都必须给出解读（一句话，结合本轮'
      '实际发生的事件；只能使用字段 key，禁止中文 label）。\n'
      'consequence 与 narrative 覆盖相同字段——说明该状态下一轮应如何'
      '影响角色行为（持续状态的保持要求/反转条件）。\n'
      '【v69 最高优先级规则】\n'
      '- 正文只写剧情。\n'
      '- 禁止在正文中输出任何状态栏。\n'
      '- 禁止输出 <details>、<summary>、<!--panel-->、状态栏 HTML。\n'
      '- 禁止输出"当前状态：""状态面板：""状态栏："等纯文本状态栏。\n'
      '- 状态栏由 App 根据最终状态自动渲染。）';

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
  /// v69：同时剥离面板外的"要求模型输出状态栏"指令句——这些句子
  /// 与 App 的"只输出 JSON patch、面板由 App 渲染"冲突（模型收到两套
  /// 互相矛盾的要求，会把面板/状态栏混进正文）。保留字段含义/变化
  /// 规则/行为约束等非输出指令。
  static String stripPanelTemplates(String text) {
    var result = text.replaceAll(_panelBlockPattern, '');
    // v69：剥离"输出状态栏/面板"指令句（行级匹配，中文标点容错）。
    // v70：放宽匹配——卡的写法多样（"每一次回复的末尾都必须输出状态
    // 面板""随后必须输出 HTML 状态面板"），只需同一行内同时出现
    // 输出类词 + 状态栏词 + 必须类词（任意顺序），不再要求固定前缀。
    result = result.replaceAll(
      RegExp(
        r'^[^\n]*(?:必须|需要|记得|要|请|得)[^\n]*(?:输出|附带|显示|渲染)[^\n]*(?:状态栏|状态面板|状态条|面板)[^\n]*$',
        multiLine: true,
      ),
      '',
    );
    result = result.replaceAll(
      RegExp(
        r'^[^\n]*(?:输出|附带|显示|渲染)[^\n]*(?:状态栏|状态面板|状态条|面板)[^\n]*(?:必须|需要|记得|要|请|得)[^\n]*$',
        multiLine: true,
      ),
      '',
    );
    // 独立命令句："输出状态栏/面板" 本身（无必须类词）
    result = result.replaceAll(
      RegExp(
        r'^[^\n]*(?:输出|附带|显示)[^\n]*(?:状态栏|状态面板|状态条|HTML 面板|HTML面板)[^\n]*$',
        multiLine: true,
      ),
      '',
    );
    // v70："XX状态面板（代码块格式，每次回复末尾必须输出）" 语序——
    // 状态面板词在前、必须输出在后（被括号/冒号包裹）
    result = result.replaceAll(
      RegExp(
        r'^[^\n]*(?:状态栏|状态面板|状态条)[^\n]*(?:每次回复|回复末尾|每轮回复)[^\n]*(?:必须|需要|记得)[^\n]*(?:输出|附带|显示)[^\n]*$',
        multiLine: true,
      ),
      '',
    );
    result = result.replaceAll(
      RegExp(
        r'^[^\n]*(?:状态栏|状态面板|状态条)[^\n]*[（(][^\n]*(?:必须|需要|记得)[^\n]*(?:输出|附带|显示)[^\n]*[）)][^\n]*$',
        multiLine: true,
      ),
      '',
    );
    // v70：剥离 ST 三件套指令（setvar 输出行）——App 模式下模型不需要
    // 输出 {{setvar::}} 宏（App 自己处理变量），ST 兼容由正则/QR 承担
    result = result.replaceAll(
      RegExp(r'^[^\n]*\{\{setvar::[^\n]*$', multiLine: true),
      '',
    );
    result = result.replaceAll(
      RegExp(
        r'^[^\n]*(?:输出|先输出|附带输出)[^\n]*变量更新行[^\n]*$',
        multiLine: true,
      ),
      '',
    );
    // v70：剥离【强制输出规则】段中引用面板模板的条款（"按下文模板"
    // "输出下方面板"）——面板模板已被剥，引用条款失去对象且会诱导模型
    result = result.replaceAll(
      RegExp(
        r'^[^\n]*(?:按下文模板|按此模板|输出下方面板|输出上方模板|输出该面板)[^\n]*$',
        multiLine: true,
      ),
      '',
    );
    // v70：剥离裸 <details> 旧面板（不在 <!--panel--> 块内）——模型看到
    // 会模仿输出 HTML 状态栏；以及代码块旧面板（``` 包裹的
    // "人物：/当前心理状态：/状态面板" 占位模板）
    result = result.replaceAll(
      RegExp(r'<details>[\s\S]*?</details>', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(
        r'```(?:html|xml)?\s*\n[\s\S]*?(?:人物：|当前心理状态：|状态面板|当前状态：)[\s\S]*?```',
        caseSensitive: false,
      ),
      '',
    );
    // v70：剥离【状态栏三件套】标题行（App 模式不需要 ST 宏指令段）
    result = result.replaceAll(
      RegExp(r'^[^\n]*状态栏三件套[^\n]*$', multiLine: true),
      '',
    );
    // v70：剥离【强制输出规则】孤儿标题行——其下"输出面板"条款已全部
    // 剥离，标题失去对象（保留"数值与剧情一致"等合理规则行）
    result = result.replaceAll(
      RegExp(r'^[^\n]*【强制输出规则[^\n]*$', multiLine: true),
      '',
    );
    // 清理剥离后产生的多余空行
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return result;
  }

  /// v69：识别并剥离正文末尾的**纯文本状态栏**——模型可能输出
  /// "状态栏：\n堕落进度：27/100\n当前状态：压制中" 这类无 HTML 的
  /// 状态栏（HTML 变体由显示层清洗器处理）。
  ///
  /// 识别规则（防误删剧情正文）：
  /// - 出现在文本末尾；
  /// - 至少 2 行命中 tracker label（"label：值"或"label: 值"格式）；
  /// - 每行含冒号（中文或英文）。
  ///
  /// 返回剥离后的正文（不带状态栏）；同时通过 [plainPanelValues] 回传
  /// 解析出的 label→值（调用方可作为兼容状态来源回写变量）。
  static String stripTrailingPlainTrackerPanel(
    String text,
    TrackerConfig config, {
    Map<String, String>? plainPanelValues,
  }) {
    final labels = config.stateSchema.values
        .map((schema) => schema.label.trim())
        .where((label) => label.isNotEmpty)
        .toSet();
    if (labels.isEmpty) {
      return text.trim();
    }
    final lines = text.split('\n');
    var matched = 0;
    var start = -1;
    final values = <String, String>{};

    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        continue;
      }
      final matchedLabel = labels
          .where((label) => line.startsWith('$label：') || line.startsWith('$label:'))
          .toList();
      if (matchedLabel.isNotEmpty) {
        matched++;
        start = i;
        // 解析值（label：值，值取冒号后）
        final value = line
            .substring(matchedLabel.first.length + 1)
            .trim();
        if (value.isNotEmpty) {
          values[matchedLabel.first] = value;
        }
        continue;
      }
      // 状态栏标题行（"状态栏"/"状态面板"/"📊"）——只有已匹配到
      // 状态行时才作为标题纳入剥离范围
      if (matched >= 2 &&
          (line.contains('状态栏') ||
              line.contains('状态面板') ||
              line.startsWith('📊'))) {
        start = i;
        continue;
      }
      break;
    }

    if (matched >= 2 && start >= 0) {
      if (plainPanelValues != null) {
        plainPanelValues.addAll(values);
      }
      return lines.take(start).join('\n').trim();
    }
    return text.trim();
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

  /// v63：从裁判响应中提取 narrative（每字段本轮动态解读）——
  /// 状态裁判除 patch 外返回 `{"narrative":{"字段key":"本轮解读文字"}}`，
  /// 数值没跨阶段时文字也能随剧情变化。
  static Map<String, String> extractNarrative(String text) {
    final result = <String, String>{};
    for (final body in _allJsonBlocks(text)) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final raw = decoded['narrative'];
        if (raw is Map<String, dynamic>) {
          raw.forEach((k, v) {
            if (k is String && v is String && v.trim().isNotEmpty) {
              result[k] = v.trim();
            }
          });
        }
        if (result.isNotEmpty) {
          return result;
        }
      } catch (_) {
        // 跳过解析失败的候选块
      }
    }
    return result;
  }

  /// v67：从响应中提取 consequence（每字段"下一轮剧情影响"指令）——
  /// 与 narrative 同构：narrative 解释"当前状态为什么形成"，consequence
  /// 说明"该状态下一轮应如何影响角色行为"。状态裁判与主模型都可输出
  /// `{"consequence":{"字段key":"下一轮剧情影响"}}`。
  static Map<String, String> extractConsequence(String text) {
    final result = <String, String>{};
    for (final body in _allJsonBlocks(text)) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final raw = decoded['consequence'];
        if (raw is Map<String, dynamic>) {
          raw.forEach((k, v) {
            if (k is String && v is String && v.trim().isNotEmpty) {
              result[k] = v.trim();
            }
          });
        }
        if (result.isNotEmpty) {
          return result;
        }
      } catch (_) {
        // 跳过解析失败的候选块
      }
    }
    return result;
  }

  /// v66：给状态裁判裁剪输入正文——裁判只需判断状态变化，不需要读整篇
  /// 长文。保留：开头、结尾、以及命中语义提示关键词（semanticHints /
  /// 字段 label / aliases / 程度词）的段落；总长不超过 [maxChars]。
  static String selectRelevantText(
    String text, {
    required TrackerConfig config,
    int maxChars = 3500,
  }) {
    if (text.length <= maxChars) {
      return text;
    }
    // 收集所有字段的提示关键词（semanticHints 三组 + label + aliases）
    final keywords = <String>{};
    for (final schema in config.stateSchema.values) {
      if (schema.label.isNotEmpty) {
        keywords.add(schema.label);
      }
      keywords.addAll(schema.aliases);
      final hints = schema.updatePolicy?.semanticHints;
      if (hints != null) {
        keywords
          ..addAll(hints.positiveSignals)
          ..addAll(hints.negativeSignals)
          ..addAll(hints.neutralSignals);
      }
    }
    // 程度词（qualitativeDeltas 的键）也视为关键词
    for (final schema in config.stateSchema.values) {
      final deltas = schema.updatePolicy?.qualitativeDeltas.keys;
      if (deltas != null) {
        keywords.addAll(deltas);
      }
    }

    // 按段落拆分，命中关键词的段落优先保留
    final paragraphs = text.split(RegExp(r'\n+'));
    final head = paragraphs.first;
    final tail = paragraphs.last;
    final hitParagraphs = paragraphs
        .where((p) => keywords.any((k) => k.isNotEmpty && p.contains(k)))
        .toList();
    // 开头 + 结尾保底——**无论有无关键词命中都保留首尾**（v82 修复：
    // 旧实现无命中时只保留首段，长正文中后段的状态事件被裁掉，裁判
    // 看不到证据返回空 patch——"首条成功后续失败"的直接原因）
    final result = StringBuffer();
    result.write('（开头）$head\n');
    if (head != tail && paragraphs.length > 1) {
      if (hitParagraphs.isNotEmpty) {
        // 命中段落按字符预算累积（v82：旧实现按 24 段上限再整体截断，
        // 结尾常被砍掉；改为预算内保留，保证结尾不被裁）
        final budget = maxChars - head.length - tail.length - 40;
        var used = 0;
        final kept = <String>[];
        for (final para in hitParagraphs) {
          if (used + para.length + 1 > budget) {
            break;
          }
          kept.add(para);
          used += para.length + 1;
        }
        if (kept.isNotEmpty) {
          result.write('（中间）${kept.join('\n')}\n');
        }
      }
      result.write('（结尾）$tail');
    }
    final trimmed = result.toString().trim();
    if (trimmed.length <= maxChars) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxChars - 3)}…';
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
      // v65：string 有限枚举字段（allowCustomValues=false）注入允许值
      // 列表——模型不得自创未声明状态
      if (schema != null &&
          !schema.isNumber &&
          !schema.allowCustomValues &&
          schema.presentation?.states != null &&
          schema.presentation!.states.isNotEmpty) {
        line += '\n  allowedValues=${schema.presentation!.states.keys.join('|')}';
      }
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
      // v63：注入语义提示（理解方向而非死规则）
      // v83：hints 对 string 字段同样注入（卡侧补了 updatePolicy 后
      // 裁判才能看到"何时 set 新值、新值自由概括"的规则）；加长度
      // 上限防卡内超长文本撑爆裁判 prompt（截断不是拒绝，保主语义）
      final hints = policy?.semanticHints;
      if (hints != null) {
        String clip(String s, [int max = 300]) =>
            s.length <= max ? s : '${s.substring(0, max)}…';
        final clipList = (List<String> items) => items
            .map((e) => clip(e, 80))
            .take(10)
            .toList();
        if (hints.meaning.isNotEmpty) {
          line += '\n  meaning=${clip(hints.meaning)}';
        }
        if (hints.positiveSignals.isNotEmpty) {
          line += '\n  positive=${clipList(hints.positiveSignals).join('，')}';
        }
        if (hints.negativeSignals.isNotEmpty) {
          line += '\n  negative=${clipList(hints.negativeSignals).join('，')}';
        }
        if (hints.neutralSignals.isNotEmpty) {
          line += '\n  neutral=${clipList(hints.neutralSignals).join('，')}';
        }
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
        '（状态判断规则：当剧情明确表示某字段上升或下降时，'
        '即使没有给出具体数字，也必须输出增量（下降用负数）；'
        'qualitative 程度词表仅作参考，词表未覆盖但剧情语义明确时，'
        '依据剧情实际推进幅度输出合理增量（通常 1-2，重大事件可更大）；'
        '不得因为用户没有提供精确数字而返回空 patch。'
        'mode=explicit 时只处理明确状态描述；'
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
  /// v65：把字段口语名/中文 label/别名规范化为真实 key——patch 与
  /// narrative 共用同一映射（模型输出中文 label 或别名作键时都能对上）。
  /// 匹配优先级：真实 key > label > aliases（含 trim 容错）。找不到返回 null。
  static String? canonicalTrackerKey(
    String raw,
    TrackerConfig config,
  ) {
    final value = raw.trim();
    if (value.isEmpty || !config.isEnabled) {
      return null;
    }
    if (config.stateSchema.containsKey(value)) {
      return value;
    }
    for (final entry in config.stateSchema.entries) {
      final schema = entry.value;
      if (schema.label.trim() == value ||
          schema.aliases.any((alias) => alias.trim() == value)) {
        return entry.key;
      }
    }
    return null;
  }

  /// v65：narrative key 规范化——模型可能用中文 label/别名作键，
  /// 统一映射回真实 key；空文本与无法识别的键丢弃。
  static Map<String, String> canonicalizeNarrative(
    Map<String, String> narrative,
    TrackerConfig config,
  ) {
    final result = <String, String>{};
    for (final entry in narrative.entries) {
      final key = canonicalTrackerKey(entry.key, config);
      final text = entry.value.trim();
      if (key != null && text.isNotEmpty) {
        result[key] = text;
      }
    }
    return result;
  }

  /// v65：比较前后变量表，返回本轮发生变化的字段 key 集合——
  /// number 按数值比较（"20" vs 20 视为相同），string 按文本比较。
  static Set<String> changedKeys({
    required Map<String, String> before,
    required Map<String, String> after,
    required TrackerConfig config,
  }) {
    final changed = <String>{};
    for (final key in config.stateSchema.keys) {
      final schema = config.stateSchema[key];
      final beforeValue = before[key];
      final afterValue = after[key];
      if (afterValue == null) {
        continue;
      }
      if (schema != null && schema.isNumber) {
        final beforeNum = num.tryParse(beforeValue ?? '');
        final afterNum = num.tryParse(afterValue);
        if (beforeNum != null && afterNum != null) {
          if (beforeNum != afterNum) {
            changed.add(key);
          }
          continue;
        }
      }
      if (beforeValue != afterValue) {
        changed.add(key);
      }
    }
    return changed;
  }

  /// v65：合并完整 narrative——规则（审查 v65 四层修复第 3 层）：
  /// - 未变化字段且裁判没有新解读：继承上一轮 narrative；
  /// - 已变化字段且裁判有新解读：使用新解读；
  /// - 已变化字段但裁判漏写：不得继承旧描述，先用新阶段静态描述；
  /// - 连静态描述也没有：生成确定性兜底，不允许空白。
  static Map<String, String> mergeNarrative({
    required Map<String, String> previousNarrative,
    required Map<String, String> judgeNarrative,
    required Map<String, String> beforeVariables,
    required Map<String, String> afterVariables,
    required TrackerConfig config,
  }) {
    final changed = changedKeys(
      before: beforeVariables,
      after: afterVariables,
      config: config,
    );
    final merged = Map<String, String>.from(previousNarrative)
      ..addAll(judgeNarrative);
    for (final key in changed) {
      if (judgeNarrative[key]?.trim().isNotEmpty == true) {
        continue; // 已变化字段裁判已给新解读
      }
      // 已变化字段但裁判漏写：移除旧解读（旧剧情说明不再适用），
      // 回退新阶段静态描述；连静态描述也没有则确定性兜底
      merged.remove(key);
      final stage = stageInfo(key, afterVariables[key], config);
      if (stage?.text.trim().isNotEmpty == true) {
        merged[key] = stage!.text.trim();
        continue;
      }
      final schema = config.stateSchema[key];
      final label = schema?.label.trim().isNotEmpty == true
          ? schema!.label.trim()
          : key;
      merged[key] =
          '$label已变为“${afterVariables[key]}”，具体表现以本轮剧情为准。';
    }
    return merged;
  }

  static (StatePatch, List<String>) canonicalizePatch(
    StatePatch patch,
    TrackerConfig config,
  ) {
    if (patch.isEmpty || !config.isEnabled) {
      return (patch, const []);
    }
    final dropped = <String>[];
    String? canonical(String raw) => canonicalTrackerKey(raw, config);

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
          // v78：number 字段拒绝非数字值（此前宽松保留会让"很多"等
          // 字符串写入变量表，后续 add/百分比/进度条全部失效且不自愈）
          return null;
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
        final patch = _patchFromDecoded(decoded);
        if (patch != null) {
          return patch;
        }
      } catch (_) {
        // JSON 解析失败继续下一个候选
      }
    }
    return null;
  }

  /// v70：从解码后的 JSON map 解析 patch（<TRACKER_UPDATE> 标记与
  /// JSON 块共用）。只要含 "patch" 键即视为协议出现（空 patch 也算）。
  static StatePatch? _patchFromDecoded(Map<String, dynamic> decoded) {
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
