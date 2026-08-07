import 'dart:convert';

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

/// 解析出的结构化 patch。
class StatePatch {
  StatePatch({
    this.setValues = const {},
    this.addValues = const {},
    /// 协议正文：JSON 输出含 "reply" 字段时，用它作为消息正文（
    /// 防止 {reply, patch} 结构正文丢失）。
    this.reply,
  });

  final Map<String, dynamic> setValues;
  final Map<String, num> addValues;
  final String? reply;

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
    );
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
    final template = config.template ??
        postHistoryPanelTemplate(cardJson) ??
        statusFallbackTemplate(cardJson);
    if (template != null &&
        RegExp(r'getvar', caseSensitive: false).hasMatch(template)) {
      var rendered = template
          .replaceAll('{{match}}', '')
          .replaceAll(r'\n', '\n');
      rendered = rendered.replaceAllMapped(
        RegExp(r'\{\{\s*getvar::([^}]+)\}\}', caseSensitive: false),
        (m) => valueOf(m.group(1)!.trim()) ?? '',
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
    final chips = <String>[];
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
      chips.add(
        '<span style="background:rgba(255,255,255,0.07);'
        'border:1px solid rgba(255,255,255,0.10);'
        'border-radius:999px;padding:2px 10px;font-size:12px;'
        'white-space:nowrap;">$label：$display</span>',
      );
    }
    if (chips.isEmpty) {
      return null;
    }
    return '<div class="status-panel" style="display:flex;flex-wrap:wrap;'
        'gap:6px 8px;align-items:center;padding:8px 10px;'
        'border-radius:10px;'
        'background:rgba(120,80,220,0.08);'
        'border:1px solid rgba(120,80,220,0.25);">'
        '<span style="font-size:12px;font-weight:600;color:#b388ff;">'
        '📊 状态</span>${chips.join('')}</div>';
  }

  /// 面板文本统一清洗：去"状态栏未更新"前缀与 `{{match}}`。
  ///
  /// `<details>/<summary>` 折叠处理：只删标签会留下 summary 标题文字
  /// 变成普通正文显示在面板外（v47 截图问题）——这里**删除整个
  /// summary 元素（含标题内容）**，并把 details 标签剥掉让面板内容
  /// 直接展开。若后续要支持真实折叠，可保留 details/summary 让
  /// HtmlWidget 原生渲染（0.17.2 支持），但需在显示层同步调整。
  static String _cleanStatusPanelText(String html) {
    return html
        .replaceAll('{{match}}', '')
        .replaceAll('状态栏未更新，当前：', '')
        .replaceAll('状态栏未更新，当前:', '')
        .replaceAll('状态栏未更新', '')
        .replaceAll(
          RegExp(
            r'<summary\b[^>]*>[\s\S]*?</summary>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'</?details\b[^>]*>', caseSensitive: false),
          '',
        );
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
  /// `(体力 +10)`、`（称呼阶段=本尊）`——label 或字段 key 均匹配。
  /// 返回 key → (值, isAdd)；number 字段 +/- 视为增减，= 为赋值；
  /// string 字段仅 = 赋值。
  static Map<String, (String, bool)> parseNarrationStateChanges(
    String text,
    TrackerConfig config,
  ) {
    final out = <String, (String, bool)>{};
    for (final entry in config.stateSchema.entries) {
      final key = entry.key;
      final schema = entry.value;
      final label = schema.label.isNotEmpty ? schema.label : key;
      for (final name in {label, key}) {
        final escaped = RegExp.escape(name);
        final m = RegExp(
          '[（(]\\s*$escaped\\s*([+\\-]?=?|=)\\s*([^)）]+?)\\s*[）)]',
        ).firstMatch(text);
        if (m == null) {
          continue;
        }
        final op = m.group(1)!.trim();
        final rawValue = m.group(2)!.trim();
        if (rawValue.isEmpty) {
          continue;
        }
        if (schema.type == 'number') {
          final num = RegExp(r'-?\d+(\.\d+)?').firstMatch(rawValue);
          if (num == null) {
            continue;
          }
          if (op == '=') {
            out[key] = (num.group(0)!, false);
          } else {
            // +10 / -5 / 10（无符号视为增减）
            out[key] = (num.group(0)!, true);
          }
        } else {
          if (op != '=') {
            continue; // 字符串字段只接受赋值
          }
          out[key] = (rawValue, false);
        }
        break;
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
        if (setValues.isNotEmpty || addValues.isNotEmpty) {
          // 协议正文：JSON 含 "reply" 字段时一并携带（防止正文丢失）
          final reply = decoded['reply'];
          return StatePatch(
            setValues: setValues,
            addValues: addValues,
            reply: reply is String && reply.isNotEmpty ? reply : null,
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
    return StatePatch(setValues: setValues, addValues: addValues);
  }
}
