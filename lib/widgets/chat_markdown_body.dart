import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../data/app_settings.dart';
import '../pages/chat/widgets/quick_command_marks.dart';
import '../theme/chat_reading_theme.dart';

const String _quoteTokenTag = 'pinn_quote';
const String _singleQuoteTokenTag = 'pinn_single_quote';
const String _bracketTokenTag = 'pinn_bracket';
const String _underlineTag = 'u';

class ChatMarkdownBody extends StatelessWidget {
  const ChatMarkdownBody({
    super.key,
    required this.text,
    required this.settings,
    required this.textColor,
    required this.inlineCodeColor,
    required this.codeBlockColor,
    this.applyBodyTextColor = true,
    this.selectable = true,
  });

  final String text;
  final AppSettings settings;
  final Color textColor;
  final Color inlineCodeColor;
  final Color codeBlockColor;
  final bool applyBodyTextColor;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chatTextTheme = resolveActiveChatTextTheme(settings);
    final effectiveTextColor = applyBodyTextColor
        ? resolveBodyMessageTextColor(
            chatTextTheme,
            fallback: textColor,
            brightness: colorScheme.brightness,
          )
        : textColor;

    final body = MarkdownBody(
      key: ValueKey<String>(_buildChatMarkdownThemeKey(settings)),
      // 特别版：先还原快捷指令占位标记（【快捷指令：名】），再走 HTML 归一
      data: normalizeSimpleHtmlBlocks(restoreQuickCommandMarks(text)),
      // SelectArea can select across Markdown's multiple text widgets.
      selectable: false,
      inlineSyntaxes: buildChatMarkdownInlineSyntaxes(),
      builders: buildChatMarkdownBuilders(
        chatTextTheme: chatTextTheme,
        colorScheme: colorScheme,
        textColor: effectiveTextColor,
      ),
      // 特别版：Markdown 图片固定宽度 + 加载期占位高度，
      // 避免图片解码完成瞬间高度突变导致 maxScrollExtent 抖动（白空白）。
      imageBuilder: (uri, title, alt) {
        ImageProvider provider;
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          provider = NetworkImage(uri.toString());
        } else if (uri.scheme == 'asset' || uri.path.startsWith('assets/')) {
          provider = AssetImage(uri.path);
        } else if (uri.scheme == 'file') {
          provider = FileImage(File(uri.toFilePath()));
        } else {
          // 未知来源：本地相对路径按文件处理
          provider = FileImage(File(uri.path));
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              // 加载中：固定占位高度（120），图片完成后由解码尺寸接管
              return const SizedBox(
                height: 120,
                width: double.infinity,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              // 加载失败：占位图标而非异常/空洞
              return Container(
                height: 80,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
        );
      },
      styleSheet: buildChatMarkdownStyleSheet(
        chatTextTheme: chatTextTheme,
        colorScheme: colorScheme,
        textColor: effectiveTextColor,
        inlineCodeColor: inlineCodeColor,
        codeBlockColor: codeBlockColor,
        shadowColor: context.chatReadingTheme.textShadow,
      ),
    );

    if (!selectable) {
      return body;
    }

    return SelectionArea(child: body);
  }
}

String normalizeSimpleHtmlBlocks(String input) {
  if (input.isEmpty || !input.contains('<')) {
    return input;
  }

  // 先保护代码块（fenced ``` 与 inline `），其中的 HTML 必须保持字面量，
  // 避免被下方的标签归一化改写（如代码里的 <li> 不应变成列表项）。
  final codePlaceholders = <String>[];
  final protected = input
      .replaceAllMapped(
        RegExp(r'```[\s\S]*?```|`[^`\n]*`'),
        (match) {
          codePlaceholders.add(match.group(0)!);
          return '\uE000${codePlaceholders.length - 1}\uE001';
        },
      )
      .replaceAll(RegExp(r'<(?:p|div)(?:\s+[^>]*)?>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</(?:p|div)\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n\n---\n\n')
      // 状态栏常见 HTML：无序/有序列表转 markdown 列表
      .replaceAll(RegExp(r'<(?:ul|ol)(?:\s+[^>]*)?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:ul|ol)\s*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<li(?:\s+[^>]*)?>', caseSensitive: false), '\n- ')
      .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '')
      // 表格降级为纯文本（| 分隔），避免整段丢失
      .replaceAll(RegExp(r'<(?:table|thead|tbody|tfoot)(?:\s+[^>]*)?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:table|thead|tbody|tfoot)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<tr(?:\s+[^>]*)?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</tr\s*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<t[dh](?:\s+[^>]*)?>', caseSensitive: false), ' | ')
      .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), '')
      // 剥掉不渲染但携带文本的标签（保留内容；颜色/对齐等样式不在此渲染）
      .replaceAll(
        RegExp(r'<(?:span|font|center|small|big|sup|sub)(?:\s+[^>]*)?>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'</(?:span|font|center|small|big|sup|sub)\s*>', caseSensitive: false),
        '',
      )
      // 换行标签统一转 \n（inline <br> 也兜底）
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  // 还原被保护的代码块（校验索引，用户文本恰含占位符序列时原样保留）
  final result = protected.replaceAllMapped(
    RegExp('\uE000(\\d+)\uE001'),
    (match) {
      final index = int.tryParse(match.group(1)!);
      if (index == null ||
          index < 0 ||
          index >= codePlaceholders.length) {
        return match.group(0)!;
      }
      return codePlaceholders[index];
    },
  );
  return result;
}

List<md.InlineSyntax> buildChatMarkdownInlineSyntaxes() {
  return <md.InlineSyntax>[
    _SimpleHtmlBreakSyntax(),
    _SimpleHtmlInlineSyntax(htmlTagPattern: 'b|strong', markdownTag: 'strong'),
    _SimpleHtmlInlineSyntax(htmlTagPattern: 'i|em', markdownTag: 'em'),
    _SimpleHtmlInlineSyntax(htmlTagPattern: 'u', markdownTag: _underlineTag),
    _SimpleHtmlInlineSyntax(htmlTagPattern: 's|strike|del', markdownTag: 'del'),
    _SimpleHtmlInlineSyntax(
      htmlTagPattern: 'code',
      markdownTag: 'code',
      parseChildren: false,
    ),
    _QuoteSyntax(),
    _SingleQuoteSyntax(),
    _BracketSyntax(),
  ];
}

Map<String, MarkdownElementBuilder> buildChatMarkdownBuilders({
  required ChatTextThemeSettings chatTextTheme,
  required ColorScheme colorScheme,
  required Color textColor,
}) {
  return <String, MarkdownElementBuilder>{
    _underlineTag: _UnderlineBuilder(),
    _quoteTokenTag: _QuoteTokenBuilder(
      chatTextTheme: chatTextTheme,
      colorScheme: colorScheme,
      textColor: textColor,
    ),
    _singleQuoteTokenTag: _SingleQuoteTokenBuilder(
      chatTextTheme: chatTextTheme,
      colorScheme: colorScheme,
      textColor: textColor,
    ),
    _bracketTokenTag: _BracketTokenBuilder(
      chatTextTheme: chatTextTheme,
      colorScheme: colorScheme,
      textColor: textColor,
    ),
  };
}

MarkdownStyleSheet buildChatMarkdownStyleSheet({
  required ChatTextThemeSettings chatTextTheme,
  required ColorScheme colorScheme,
  required Color textColor,
  required Color inlineCodeColor,
  required Color codeBlockColor,
  Color? shadowColor,
}) {
  final baseTextStyle = buildBaseMessageTextStyle(
    textColor: textColor,
    brightness: colorScheme.brightness,
    enableShadow: chatTextTheme.enableMessageTextShadow,
    shadowColor: shadowColor,
  );

  return MarkdownStyleSheet(
    p: baseTextStyle,
    em: buildDecoratedChatTextStyle(
      baseStyle: baseTextStyle,
      config: chatTextTheme.italicTextStyle,
      brightness: colorScheme.brightness,
    ),
    strong: buildDecoratedChatTextStyle(
      baseStyle: baseTextStyle,
      config: chatTextTheme.boldTextStyle,
      brightness: colorScheme.brightness,
    ),
    del: baseTextStyle.copyWith(decoration: TextDecoration.lineThrough),
    code: TextStyle(
      fontSize: 14,
      height: 1.45,
      color: textColor,
      backgroundColor: inlineCodeColor,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: codeBlockColor,
      borderRadius: BorderRadius.circular(8),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: textColor.withValues(alpha: 0.25), width: 0.3),
      ),
    ),
  );
}

String _buildChatMarkdownThemeKey(AppSettings settings) {
  final themeConfig = resolveThemeConfig(settings);
  final chatTextTheme = themeConfig.chatTextTheme;

  return <String>[
    settings.themePreset.name,
    themeConfig.customFontFamily ?? 'system',
    chatTextTheme.quoteStyle.name,
    chatTextTheme.enableMessageTextShadow ? 'shadow' : 'plain',
    chatTextTheme.bodyTextColorPaletteIndex?.toString() ?? 'body-auto',
    chatTextTheme.bodyTextColorDarkPaletteIndex?.toString() ?? 'body-dark-auto',
    _buildTextStyleConfigKey(chatTextTheme.quotedTextStyle),
    _buildTextStyleConfigKey(chatTextTheme.bracketTextStyle),
    _buildTextStyleConfigKey(chatTextTheme.italicTextStyle),
    _buildTextStyleConfigKey(chatTextTheme.boldTextStyle),
  ].join('|');
}

String _buildTextStyleConfigKey(ChatTextStyleConfig config) {
  return <String>[
    config.paletteIndex.toString(),
    config.darkPaletteIndex?.toString() ?? 'same',
    config.fontStyleMode.name,
    config.opacity.toStringAsFixed(3),
  ].join(':');
}

TextStyle buildBaseMessageTextStyle({
  required Color textColor,
  required Brightness brightness,
  required bool enableShadow,
  Color? shadowColor,
}) {
  return TextStyle(
    fontSize: 15,
    height: 1.5,
    color: textColor,
    shadows: enableShadow
        ? _buildMessageTextShadows(brightness, shadowColor: shadowColor)
        : null,
  );
}

Color resolveBodyMessageTextColor(
  ChatTextThemeSettings chatTextTheme, {
  required Color fallback,
  Brightness brightness = Brightness.light,
}) {
  final paletteIndex = chatTextTheme.resolveBodyTextColorPaletteIndex(brightness);
  if (paletteIndex == null ||
      paletteIndex < 0 ||
      paletteIndex >= customThemePalette.length) {
    return fallback;
  }
  return customThemePalette[paletteIndex];
}

TextStyle buildDecoratedChatTextStyle({
  required TextStyle baseStyle,
  required ChatTextStyleConfig config,
  Brightness brightness = Brightness.light,
}) {
  final paletteIndex = config.resolvePaletteIndex(brightness).clamp(
    0,
    customThemePalette.length - 1,
  );
  var textStyle = baseStyle.copyWith(
    color: customThemePalette[paletteIndex].withValues(alpha: config.opacity),
  );

  switch (config.fontStyleMode) {
    case ChatTextFontStyleMode.platform:
      return textStyle.copyWith(
        fontStyle: FontStyle.normal,
        fontWeight: FontWeight.normal,
        letterSpacing: 0,
      );
    case ChatTextFontStyleMode.italic:
      return textStyle.copyWith(
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.normal,
      );
    case ChatTextFontStyleMode.bold:
      return textStyle.copyWith(
        fontStyle: FontStyle.normal,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      );
  }
}

List<Shadow> _buildMessageTextShadows(
  Brightness brightness, {
  Color? shadowColor,
}) {
  final resolvedShadowColor = shadowColor ??
      (brightness == Brightness.dark
          ? Colors.black.withValues(alpha: 0.34)
          : Colors.black.withValues(alpha: 0.16));

  return <Shadow>[
    Shadow(
      color: resolvedShadowColor,
      blurRadius: 2.5,
      offset: const Offset(0, 1),
    ),
  ];
}

class _QuoteSyntax extends md.InlineSyntax {
  _QuoteSyntax()
    : super(
        '“([^”\n]+)”'
        r'|'
        '「([^」\n]+)」'
        r'|'
        '『([^』\n]+)』'
        r'|'
        r'(?<!\w)"([^"\n]+)"(?!\w)',
      );


  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = (match.group(1) ??
            match.group(2) ??
            match.group(3) ??
            match.group(4))
        ?.trim();
    if (content == null || content.isEmpty) {
      return false;
    }

    parser.addNode(md.Element.text(_quoteTokenTag, content));
    return true;
  }
}

class _SingleQuoteSyntax extends md.InlineSyntax {
  _SingleQuoteSyntax()
    : super(
        '‘([^’\n]+)’'
        r'|'
        "(?<!\\w)'([^'\\n]+)'(?!\\w)",
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content =
        (match.group(1) ?? match.group(2))?.trim();
    if (content == null || content.isEmpty) {
      return false;
    }

    parser.addNode(md.Element.text(_singleQuoteTokenTag, content));
    return true;
  }
}

class _BracketSyntax extends md.InlineSyntax {
  _BracketSyntax()
    : super(
        r'[（(]([^()（）\n]+)[)）]'
        r'|'
        r'[【\[]([^\[\]【】\n]+)[】\]]',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = (match.group(1) ?? match.group(2))?.trim();
    if (content == null || content.isEmpty) {
      return false;
    }

    parser.addNode(md.Element.text(_bracketTokenTag, content));
    return true;
  }
}

class _SimpleHtmlBreakSyntax extends md.InlineSyntax {
  _SimpleHtmlBreakSyntax()
    : super(r'<br\s*/?>', caseSensitive: false, startCharacter: _lessThanCode);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

class _SimpleHtmlInlineSyntax extends md.InlineSyntax {
  _SimpleHtmlInlineSyntax({
    required String htmlTagPattern,
    required this.markdownTag,
    this.parseChildren = true,
  }) : super(
         '<($htmlTagPattern)(?:\\s+[^>]*)?>([\\s\\S]*?)</\\1\\s*>',
         caseSensitive: false,
         startCharacter: _lessThanCode,
       );

  final String markdownTag;
  final bool parseChildren;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(2) ?? '';
    final children = parseChildren
        ? parser.document.parseInline(content)
        : <md.Node>[md.Text(content)];

    parser.addNode(md.Element(markdownTag, children));
    return true;
  }
}

const int _lessThanCode = 60;

class _UnderlineBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = (parentStyle ?? preferredStyle ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
    );

    return Text.rich(TextSpan(text: element.textContent, style: style));
  }
}

class _QuoteTokenBuilder extends MarkdownElementBuilder {
  _QuoteTokenBuilder({
    required this.chatTextTheme,
    required this.colorScheme,
    required this.textColor,
  });

  final ChatTextThemeSettings chatTextTheme;
  final ColorScheme colorScheme;
  final Color textColor;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final baseStyle =
        parentStyle ??
        preferredStyle ??
        buildBaseMessageTextStyle(
          textColor: textColor,
          brightness: colorScheme.brightness,
          enableShadow: chatTextTheme.enableMessageTextShadow,
        );
    final contentStyle = buildDecoratedChatTextStyle(
      baseStyle: baseStyle,
      config: chatTextTheme.quotedTextStyle,
      brightness: colorScheme.brightness,
    );
    final quoteStyle = baseStyle.copyWith(
      color: contentStyle.color,
      fontWeight: contentStyle.fontWeight,
      fontStyle: contentStyle.fontStyle,
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: chatTextTheme.quoteStyle.leading, style: quoteStyle),
          TextSpan(
            text: _unifySingleQuotes(
              element.textContent,
              chatTextTheme.quoteStyle,
            ),
            style: contentStyle,
          ),
          TextSpan(text: chatTextTheme.quoteStyle.trailing, style: quoteStyle),
        ],
      ),
    );
  }
}

String _unifySingleQuotes(String content, AppQuoteStyle style) {
  final result = content
      .replaceAll('「', style.leadingSingle)
      .replaceAll('」', style.trailingSingle)
      .replaceAll('『', style.leadingSingle)
      .replaceAll('』', style.trailingSingle)
      .replaceAll('‘', style.leadingSingle)
      .replaceAll('’', style.trailingSingle);
  return result.replaceAllMapped(
    RegExp(r"(?<!\w)'([^'\n]+)'(?!\w)"),
    (m) => '${style.leadingSingle}${m.group(1)}${style.trailingSingle}',
  );
}

class _SingleQuoteTokenBuilder extends MarkdownElementBuilder {
  _SingleQuoteTokenBuilder({
    required this.chatTextTheme,
    required this.colorScheme,
    required this.textColor,
  });

  final ChatTextThemeSettings chatTextTheme;
  final ColorScheme colorScheme;
  final Color textColor;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final baseStyle =
        parentStyle ??
        preferredStyle ??
        buildBaseMessageTextStyle(
          textColor: textColor,
          brightness: colorScheme.brightness,
          enableShadow: chatTextTheme.enableMessageTextShadow,
        );
    final contentStyle = buildDecoratedChatTextStyle(
      baseStyle: baseStyle,
      config: chatTextTheme.quotedTextStyle,
      brightness: colorScheme.brightness,
    );
    final quoteStyle = baseStyle.copyWith(
      color: contentStyle.color,
      fontWeight: contentStyle.fontWeight,
      fontStyle: contentStyle.fontStyle,
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: chatTextTheme.quoteStyle.leadingSingle,
            style: quoteStyle,
          ),
          TextSpan(text: element.textContent, style: contentStyle),
          TextSpan(
            text: chatTextTheme.quoteStyle.trailingSingle,
            style: quoteStyle,
          ),
        ],
      ),
    );
  }
}

class _BracketTokenBuilder extends MarkdownElementBuilder {
  _BracketTokenBuilder({
    required this.chatTextTheme,
    required this.colorScheme,
    required this.textColor,
  });

  final ChatTextThemeSettings chatTextTheme;
  final ColorScheme colorScheme;
  final Color textColor;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final baseStyle =
        parentStyle ??
        preferredStyle ??
        buildBaseMessageTextStyle(
          textColor: textColor,
          brightness: colorScheme.brightness,
          enableShadow: chatTextTheme.enableMessageTextShadow,
        );
    final contentStyle = buildDecoratedChatTextStyle(
      baseStyle: baseStyle,
      config: chatTextTheme.bracketTextStyle,
      brightness: colorScheme.brightness,
    );

    return Text.rich(TextSpan(text: element.textContent, style: contentStyle));
  }
}
