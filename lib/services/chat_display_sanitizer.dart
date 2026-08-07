import 'package:pocket_inn/services/chat_variable_service.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

/// 特别版：特殊状态栏 HTML 在会话变量表中的存储 key。
/// 模型输出 HTML 状态面板（ST 三件套）时由 [ChatDisplaySanitizer.extract]
/// 提取并持久化到这里，[TrackerStatusBar] 优先渲染它（无则回退变量 chips）。
const String kSpecialStatusHtmlKey = '__special_status_html__';

/// 特别版：清洗 + 提取结果——正文 + 可选的特殊状态栏 HTML。
class SanitizedAssistantDisplay {
  const SanitizedAssistantDisplay({
    required this.displayText,
    this.specialStatusHtml,
  });

  /// 聊天正文（已剥离协议块/宏副作用/状态面板）。
  final String displayText;

  /// 提取到的特殊状态栏 HTML（模型输出的 `<details>`/内联 background
  /// div/status 标签块）；无则 null。
  final String? specialStatusHtml;
}

/// 特别版：聊天显示清洗器——把"AI 输出"规整为"只含正文"，
/// 同时**提取**特殊状态栏 HTML 供状态栏组件单独渲染。
///
/// 角色卡的 tracker 三件套会让模型每次回复末尾强制输出状态面板
/// （HTML `<details>` / `<div style="background:...">` 形式）以及
/// `<STATE>` / JSON `{patch,...}` 协议块。这些是**系统副作用**：
/// 协议块应剥离丢弃，而 HTML 状态面板应提取出来交给
/// [TrackerStatusBar] 渲染（聊天气泡只显示正文）。
class ChatDisplaySanitizer {
  ChatDisplaySanitizer._();

  /// 状态面板 HTML：`<details>...</details>` 整体（卡模板常把面板包在
  /// details 折叠标签里，正文几乎不会用 details）。
  static final RegExp _detailsBlock = RegExp(
    r'<details[\s\S]*?</details>',
    caseSensitive: false,
  );

  /// 候选 div（attrs/body 是否状态栏由 extract 内判断，
  /// border 太常见不能单独作依据，避免误删正文排版框）。
  static final RegExp _candidateDivBlock = RegExp(
    r'<div\b([^>]*)>([\s\S]*?)</div>',
    caseSensitive: false,
  );

  /// `<status>` / `<status_bar>` / `<tracker>` / `<tracker_status>` 标签块。
  static final RegExp _statusTagBlock = RegExp(
    r'<\s*(?:status|status_bar|tracker|tracker_status)\b[^>]*>[\s\S]*?<\s*/\s*(?:status|status_bar|tracker|tracker_status)\s*>',
    caseSensitive: false,
  );

  /// 状态栏代码块：```html / ```xml 且内容含状态特征。
  static final RegExp _statusCodeBlock = RegExp(
    r'```(?:html|xml)?\s*([\s\S]*?)```',
    caseSensitive: false,
  );

  /// ST comment panel：`{{match}}` + `<!--panel-->...<!--/panel-->` 块。
  static final RegExp _panelCommentBlock = RegExp(
    r'(?:\{\{\s*match\s*\}\}\s*)?<!--\s*(?:panel|status|tracker|状态栏|面板)\s*-->([\s\S]*?)<!--\s*/\s*(?:panel|status|tracker|状态栏|面板)\s*-->(?:\s*\{\{\s*/\s*match\s*\}\})?',
    caseSensitive: false,
  );

  /// {{comment}}...{{/comment}} 整块（内容属于模板注释，可删）。
  static final RegExp _commentTemplateBlock = RegExp(
    r'\{\{\s*comment\s*\}\}[\s\S]*?\{\{\s*/\s*comment\s*\}\}',
    caseSensitive: false,
  );

  /// {{//...}} 行注释。
  static final RegExp _templateLineComment = RegExp(
    r'\{\{\s*//[^}]*\}\}',
    caseSensitive: false,
  );

  /// 普通 HTML 注释。
  static final RegExp _htmlComment = RegExp(
    r'<!--[\s\S]*?-->',
    caseSensitive: false,
  );

  /// 孤立的 {{match}} / {{/match}} / {{comment}} / {{/comment}} 单 token。
  static final RegExp _standaloneTemplateToken = RegExp(
    r'\{\{\s*/?\s*(?:match|comment)\s*\}\}',
    caseSensitive: false,
  );

  /// 提取入口：把 [text] 拆成"正文"+"特殊状态栏 HTML"。
  ///
  /// 依次从 ```html/xml 代码块、`<details>`、status/tracker 标签、
  /// 内联 background/class div 中提取状态面板（可多个，取**最后一个**——
  /// 模型一条回复输出多个时，最后一个通常是最新状态）；正文再走
  /// 协议块/宏副作用剥离。
  static SanitizedAssistantDisplay extract(String text) {
    if (text.trim().isEmpty) {
      return const SanitizedAssistantDisplay(displayText: '');
    }
    var result = _normalizeTemplateEscapes(text);
    final statusBlocks = <String>[];

    bool looksLikeStatus(String value) {
      final lower = value.toLowerCase();
      // 强特征词（弱词如"当前/阶段"太常见，不作为状态栏依据）
      return lower.contains('status') ||
          lower.contains('tracker') ||
          lower.contains('panel') ||
          lower.contains('状态栏') ||
          lower.contains('状态面板') ||
          lower.contains('面板') ||
          lower.contains('{{getvar') ||
          lower.contains('烙印值') ||
          lower.contains('服装状态') ||
          lower.contains('黑丝状态') ||
          lower.contains('background') ||
          lower.contains('background-color');
    }

    /// 代码块是否值得作为"特殊状态栏"提取：必须是**真实 HTML**（含
    /// 常见标签），且内容带状态特征。纯文本/Markdown 代码块（如角色卡
    /// first_mes 里的 ``` 状态栏）**不提取**，保留在正文原样显示——
    /// 避免把 Markdown 状态栏误判成 HTML 面板（曾导致正常卡变异常）。
    bool looksLikeHtmlStatusBlock(String value) {
      if (!value.contains('<')) {
        return false;
      }
      final hasHtmlTag = RegExp(
        r'<(?:\/)?(?:div|span|b|i|u|hr|details|summary|table|tr|td|th|style|font|center|br|p)\b',
        caseSensitive: false,
      ).hasMatch(value);
      return hasHtmlTag && looksLikeStatus(value);
    }

    bool attrsLookLikeStatus(String attrs) {
      final hasStatusClass = RegExp(
        "class\\s*=\\s*[\"'][^\"']*(?:status|tracker|panel|状态|面板)[^\"']*[\"']",
        caseSensitive: false,
      ).hasMatch(attrs);
      final hasStatusStyle = RegExp(
        "style\\s*=\\s*[\"'][^\"']*(?:background|background-color)[^\"']*[\"']",
        caseSensitive: false,
      ).hasMatch(attrs);
      return hasStatusClass || hasStatusStyle;
    }

    bool divLooksLikeStatus(String attrs, String body) {
      if (!attrsLookLikeStatus(attrs)) {
        return false;
      }
      // 有 status/panel class 或 background 样式可放宽；
      // 仅 border（attrsLookLikeStatus 已排除）不单独作数。
      return true;
    }

    void addStatus(String? value) {
      final html = value?.trim();
      if (html != null && html.isNotEmpty) {
        statusBlocks.add(html);
      }
    }

    // 0) ST comment panel: {{match}}\n<!--panel-->...<!--/panel-->
    result = result.replaceAllMapped(_panelCommentBlock, (match) {
      final body = match.group(1) ?? '';
      final html = _statusHtmlFromPanelBody(body);
      if (html.isNotEmpty) {
        addStatus(html);
      }
      return '';
    });

    // 1) 状态代码块（```html/xml 且内容为真实 HTML + 状态特征才提取）
    result = result.replaceAllMapped(_statusCodeBlock, (match) {
      final body = match.group(1) ?? '';
      if (looksLikeHtmlStatusBlock(body)) {
        addStatus(body);
        return '';
      }
      return match.group(0)!;
    });

    // 2) details 块——details 标签本身即状态栏特征（正文几乎不用），
    //    但需像状态栏才提取（避免误删正文折叠块）
    for (var i = 0; i < 8; i++) {
      final m = _detailsBlock.firstMatch(result);
      if (m == null) {
        break;
      }
      final block = m.group(0) ?? '';
      if (!looksLikeStatus(block)) {
        break;
      }
      addStatus(block);
      result = result.replaceRange(m.start, m.end, '');
    }

    // 3) status / tracker 标签块
    for (var i = 0; i < 8; i++) {
      final m = _statusTagBlock.firstMatch(result);
      if (m == null) {
        break;
      }
      addStatus(m.group(0));
      result = result.replaceRange(m.start, m.end, '');
    }

    // 4) div 状态栏候选——attrs 有 status/panel class 或 background 样式
    //    才提取；仅 border 不单独作数（避免误删正文排版框）
    for (var i = 0; i < 8; i++) {
      final m = _candidateDivBlock.firstMatch(result);
      if (m == null) {
        break;
      }
      final attrs = m.group(1) ?? '';
      final body = m.group(2) ?? '';
      final block = m.group(0) ?? '';
      if (!divLooksLikeStatus(attrs, body)) {
        break;
      }
      addStatus(block);
      result = result.replaceRange(m.start, m.end, '');
    }

    // 协议块与宏副作用
    result = ChatVariableService.stripSetVarCalls(result);
    result = TrackerRuntime.stripStateBlocks(result);

    // 只删除 comment 块（{{comment}}...{{/comment}}）；**不删除
    // {{match}}...{{/match}} 包住的正文**（很多角色卡用它包开场白）。
    result = result.replaceAll(_commentTemplateBlock, '');
    // 删除 {{//...}} 行注释
    result = result.replaceAll(_templateLineComment, '');
    // 删除普通 HTML 注释（panel 已在 0) 提取过）
    result = result.replaceAll(_htmlComment, '');
    // 只剥离孤立 token，保留 token 中间的正文
    result = result.replaceAll(_standaloneTemplateToken, '');

    // 孤立标签行清理
    result = result.replaceAll(
      RegExp(
        r'^\s*</?(?:div|span|b|i|u|hr|details|summary|table|tr|td|th)\s*>\s*$',
        multiLine: true,
      ),
      '',
    );

    // 压缩连续空行
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return SanitizedAssistantDisplay(
      displayText: result.trim(),
      // 用最后一个状态栏（多条时取最新）
      specialStatusHtml: statusBlocks.isEmpty ? null : statusBlocks.last.trim(),
    );
  }

  /// 判断 [text] 是否**纯面板**：原文的可见文本与面板可见文本一致
  /// （即原文内容就是面板本身，没有正文）。用于 extract 误判时决定
  /// 是否兜底恢复正文。
  static bool isPurePanelText(String text, String? panelHtml) {
    final panelVisible = _visibleComparable(panelHtml ?? '');
    if (panelVisible.isEmpty) {
      return false;
    }
    final textVisible = _visibleComparable(text);
    if (textVisible.isEmpty) {
      return false;
    }
    return textVisible == panelVisible;
  }

  /// 可见文本归一化（比较用）：剥 token/注释/代码围栏/标签/HTML 实体。
  static String _visibleComparable(String value) {
    var result = _normalizeTemplateEscapes(value);

    result = result.replaceAll(_standaloneTemplateToken, '');
    result = result.replaceAll(_templateLineComment, '');
    result = result.replaceAll(
      RegExp(
        r'<!--\s*/?\s*(?:panel|status|tracker|状态栏|面板)\s*-->',
        caseSensitive: false,
      ),
      '',
    );

    result = result.replaceAll(
      RegExp(r'```(?:html|xml)?\s*|\s*```', caseSensitive: false),
      '',
    );

    result = result.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );

    result = result.replaceAll(RegExp(r'<[^>]+>'), ' ');

    result = result
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 入库 fallback：从原文中精确移除面板 HTML 后，再走轻量显示清洗
  /// ——用于 extract 把"正文+面板"混合输出误判（正文被删、面板保留）
  /// 时恢复正文。
  static String recoverDisplayTextAfterExtraction(
    String text, {
    String? specialStatusHtml,
  }) {
    var result = _normalizeTemplateEscapes(text);

    final panel = _normalizeTemplateEscapes(specialStatusHtml ?? '').trim();
    if (panel.isNotEmpty) {
      final index = result.indexOf(panel);
      if (index >= 0) {
        result = result.replaceRange(index, index + panel.length, '');
      }
    }

    return stripStoredMessageForDisplay(result);
  }

  /// 开场消息批量提取：正文列表 + 特殊状态栏 HTML（取最后一个）。
  /// 空白/重复消息过滤（避免空白开场进翻页）。
  static SanitizedOpeningMessages extractOpeningMessages(
    Iterable<String> raw,
  ) {
    final messages = <String>[];
    final seen = <String>{};
    String? specialStatusHtml;
    for (final text in raw) {
      final extracted = extract(text);

      var displayText = _cleanVisibleText(extracted.displayText);
      // extract 是破坏性提取器。若误判导致正文为空，用轻量显示清洗兜底；
      // 但**纯面板消息**（原文内容就是面板本身，无正文）不兜底，
      // 避免面板文本混进开场正文列表。
      if (displayText.isEmpty) {
        if (!isPurePanelText(text, extracted.specialStatusHtml)) {
          displayText = stripStoredMessageForDisplay(text);
        }
      }

      if (displayText.isNotEmpty && seen.add(displayText)) {
        messages.add(displayText);
      }
      final html = extracted.specialStatusHtml?.trim();
      if (html != null && html.isNotEmpty) {
        specialStatusHtml = html;
      }
    }
    return SanitizedOpeningMessages(
      messages: messages,
      specialStatusHtml: specialStatusHtml,
    );
  }

  /// 兼容旧用法：只返回正文（= [extract] 的 displayText）。
  static String stripNonDialogue(String text) => extract(text).displayText;

  /// **显示层专用轻量清洗**：只剥协议块/宏副作用/注释/孤立 token，
  /// **不提取/删除任何 div/details/html 内容**（extract 是入库前破坏性
  /// 拆解，不能在气泡显示层再用，否则正文会被误判成状态栏剥空）。
  ///
  /// 安全兜底：清洗后为空但原文有可见内容时，返回原文的轻量清理
  /// （绝不把一条非空消息清洗成空）。
  static String stripStoredMessageForDisplay(String text) {
    if (text.trim().isEmpty) {
      return '';
    }
    final original = _normalizeTemplateEscapes(text);
    var result = original;

    // 只移除明确的 panel comment 块，不碰普通 div/details/html
    result = result.replaceAllMapped(_panelCommentBlock, (match) => '');

    // 只移除副作用宏和协议块
    result = ChatVariableService.stripSetVarCalls(result);
    result = TrackerRuntime.stripStateBlocks(result);

    // 删除 comment 块，但不要删除 match 块正文
    result = result.replaceAll(_commentTemplateBlock, '');
    result = result.replaceAll(_templateLineComment, '');
    result = result.replaceAll(_htmlComment, '');

    // 只剥 token，保留 token 中间正文
    result = result.replaceAll(_standaloneTemplateToken, '');

    result = _cleanVisibleText(result);

    // 清洗后为空就返回空——纯 panel/comment/系统文本不兜回正文
    // （兜底恢复只由 recoverDisplayTextAfterExtraction 在入库层负责）
    return result;
  }

  /// 清理不可见字符（零宽空格等）、压缩连续空行、trim。
  static String _cleanVisibleText(String value) {
    return value
        .replaceAll(RegExp(r'[\u200B-\u200D\u2060\uFEFF]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  // ---- comment panel 辅助 ----

  /// 规整模板转义（\r\n/\t 统一为 \n）。
  static String _normalizeTemplateEscapes(String value) {
    return value
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', '\t');
  }

  /// 是否为真实 HTML（含常见标签）。
  static bool _containsHtmlTag(String value) {
    return RegExp(
      r'<(?:/?)(?:div|span|b|i|u|hr|details|summary|table|tr|td|th|style|font|center|br|p)\b',
      caseSensitive: false,
    ).hasMatch(value);
  }

  /// HTML 转义（纯文本面板包成 div 时用）。
  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// comment panel 正文 → 可渲染的状态栏 HTML。
  /// 正文本身是 HTML 直接用；纯文本则包一层 status-panel div（换行转 br）。
  static String _statusHtmlFromPanelBody(String value) {
    final body = _normalizeTemplateEscapes(value).trim();
    if (body.isEmpty) {
      return '';
    }
    if (_containsHtmlTag(body)) {
      return body;
    }
    return '<div class="status-panel">${_escapeHtml(body).replaceAll('\n', '<br>')}</div>';
  }
}

/// 特别版：开场消息批量提取结果。
class SanitizedOpeningMessages {
  const SanitizedOpeningMessages({
    required this.messages,
    this.specialStatusHtml,
  });

  /// 开场正文列表（已剥离协议块/状态面板/空消息）。
  final List<String> messages;

  /// 开场里提取到的特殊状态栏 HTML（无则 null）。
  final String? specialStatusHtml;
}
