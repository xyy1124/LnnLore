import 'package:flutter/material.dart';

/// ThemeExtension for the chat-specific reading hierarchy.
///
/// Material's [ColorScheme] remains the source for dialogs, menus and generic
/// controls. This extension only assigns semantic surfaces used by the chat
/// reading experience, so message, composer and status UI do not each invent
/// their own combination of Material container colors.
@immutable
class ChatReadingTheme extends ThemeExtension<ChatReadingTheme> {
  const ChatReadingTheme({
    required this.canvas,
    required this.canvasScrim,
    required this.appBarSurface,
    required this.appBarForeground,
    required this.assistantText,
    required this.assistantInlineCode,
    required this.assistantCodeBlock,
    required this.userBubble,
    required this.onUserBubble,
    required this.userInlineCode,
    required this.userCodeBlock,
    required this.composerSurface,
    required this.composerGlassSurface,
    required this.composerBorder,
    required this.composerText,
    required this.composerHint,
    required this.composerToolSurface,
    required this.composerAccent,
    required this.composerSend,
    required this.composerStop,
    required this.sidebarSurface,
    required this.sidebarSelectedSurface,
    required this.sidebarPrimaryText,
    required this.sidebarSecondaryText,
    required this.sidebarTimestamp,
    required this.statusHeaderSurface,
    required this.statusHeaderText,
    required this.statusFallbackSurface,
    required this.statusBorder,
    required this.thinkingLabel,
    required this.thinkingText,
    required this.thinkingRail,
    required this.streamSurface,
    required this.streamText,
    required this.scrollControlSurface,
    required this.scrollControlForeground,
    required this.choiceSurface,
    required this.choiceForeground,
    required this.textShadow,
    required this.composerShadow,
  });

  final Color canvas;
  final Color canvasScrim;
  final Color appBarSurface;
  final Color appBarForeground;
  final Color assistantText;
  final Color assistantInlineCode;
  final Color assistantCodeBlock;
  final Color userBubble;
  final Color onUserBubble;
  final Color userInlineCode;
  final Color userCodeBlock;
  final Color composerSurface;
  final Color composerGlassSurface;
  final Color composerBorder;
  final Color composerText;
  final Color composerHint;
  final Color composerToolSurface;
  final Color composerAccent;
  final Color composerSend;
  final Color composerStop;
  final Color sidebarSurface;
  final Color sidebarSelectedSurface;
  final Color sidebarPrimaryText;
  final Color sidebarSecondaryText;
  final Color sidebarTimestamp;
  final Color statusHeaderSurface;
  final Color statusHeaderText;
  final Color statusFallbackSurface;
  final Color statusBorder;
  final Color thinkingLabel;
  final Color thinkingText;
  final Color thinkingRail;
  final Color streamSurface;
  final Color streamText;
  final Color scrollControlSurface;
  final Color scrollControlForeground;
  final Color choiceSurface;
  final Color choiceForeground;
  final Color textShadow;
  final Color composerShadow;

  static ChatReadingTheme fromColorScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final seed = scheme.primary;

    if (isDark) {
      // The seed may tint a reading surface, but never dominate it. This keeps
      // different presets identifiable without turning the chat into a wall
      // of purple, blue or orange.
      final canvas = Color.alphaBlend(
        seed.withValues(alpha: 0.055),
        const Color(0xFF101416),
      );
      final raised = Color.alphaBlend(
        seed.withValues(alpha: 0.075),
        const Color(0xFF171D20),
      );
      final muted = Color.alphaBlend(
        seed.withValues(alpha: 0.09),
        const Color(0xFF20282C),
      );
      final accentSurface = Color.alphaBlend(
        seed.withValues(alpha: 0.18),
        muted,
      );
      final userBubble = Color.alphaBlend(
        seed.withValues(alpha: 0.34),
        const Color(0xFF243034),
      );
      return ChatReadingTheme(
        canvas: canvas,
        canvasScrim: const Color(0xFF0B0F11),
        appBarSurface: const Color(0xEE12181B),
        appBarForeground: const Color(0xFFF0F4F2),
        assistantText: const Color(0xFFE8EEEB),
        assistantInlineCode: const Color(0xFF243136),
        assistantCodeBlock: const Color(0xFF192125),
        userBubble: userBubble,
        onUserBubble: const Color(0xFFF7FBF8),
        userInlineCode: const Color(0x2EFFFFFF),
        userCodeBlock: const Color(0x24FFFFFF),
        composerSurface: raised,
        composerGlassSurface: const Color(0xD9161D20),
        composerBorder: const Color(0xFF3A4649),
        composerText: const Color(0xFFF0F4F2),
        composerHint: const Color(0xFF9DAAA6),
        composerToolSurface: const Color(0xFF222B2E),
        composerAccent: scheme.primary,
        composerSend: scheme.primary,
        composerStop: scheme.error,
        sidebarSurface: const Color(0xFF13191C),
        sidebarSelectedSurface: accentSurface,
        sidebarPrimaryText: const Color(0xFFF0F4F2),
        sidebarSecondaryText: const Color(0xFFAAB6B2),
        sidebarTimestamp: const Color(0xFF87938F),
        statusHeaderSurface: const Color(0xFF1B2326),
        statusHeaderText: const Color(0xFFEAF0EC),
        statusFallbackSurface: muted,
        statusBorder: const Color(0xFF364246),
        thinkingLabel: const Color(0xFF9CAAA5),
        thinkingText: const Color(0xFFB8C3BF),
        thinkingRail: const Color(0xFF61716D),
        streamSurface: const Color(0xF0182023),
        streamText: const Color(0xFFEAF0EC),
        scrollControlSurface: const Color(0xE61D2628),
        scrollControlForeground: const Color(0xFFE8EEEB),
        choiceSurface: accentSurface,
        choiceForeground: const Color(0xFFEAF0EC),
        textShadow: const Color(0x8A000000),
        composerShadow: const Color(0x66000000),
      );
    }

    final canvas = Color.alphaBlend(
      seed.withValues(alpha: 0.035),
      const Color(0xFFF9F7F4),
    );
    final raised = Color.alphaBlend(
      seed.withValues(alpha: 0.025),
      const Color(0xFFFFFDFC),
    );
    final accentSurface = Color.alphaBlend(
      seed.withValues(alpha: 0.12),
      const Color(0xFFF0EEEA),
    );
    final userBubble = Color.alphaBlend(
      seed.withValues(alpha: 0.18),
      const Color(0xFFF5F2EE),
    );
    return ChatReadingTheme(
      canvas: canvas,
      canvasScrim: const Color(0xFFF6F3EF),
      appBarSurface: const Color(0xFDFBF9F6),
      appBarForeground: const Color(0xFF202421),
      assistantText: const Color(0xFF252A27),
      assistantInlineCode: const Color(0xFFECE9E4),
      assistantCodeBlock: const Color(0xFFF0EDE8),
      userBubble: userBubble,
      onUserBubble: const Color(0xFF202622),
      userInlineCode: const Color(0x17000000),
      userCodeBlock: const Color(0x11000000),
      composerSurface: raised,
      composerGlassSurface: const Color(0xEFFFFFFC),
      composerBorder: const Color(0xFFD8D5CF),
      composerText: const Color(0xFF252A27),
      composerHint: const Color(0xFF747A75),
      composerToolSurface: const Color(0xFFF0EDE8),
      composerAccent: scheme.primary,
      composerSend: scheme.primary,
      composerStop: scheme.error,
      sidebarSurface: const Color(0xFFFDFBF8),
      sidebarSelectedSurface: accentSurface,
      sidebarPrimaryText: const Color(0xFF202421),
      sidebarSecondaryText: const Color(0xFF656B66),
      sidebarTimestamp: const Color(0xFF7D837E),
      statusHeaderSurface: const Color(0xFFF0EDE8),
      statusHeaderText: const Color(0xFF2B302D),
      statusFallbackSurface: const Color(0xFFF2EFEB),
      statusBorder: const Color(0xFFD8D5CF),
      thinkingLabel: const Color(0xFF6E7670),
      thinkingText: const Color(0xFF59615B),
      thinkingRail: const Color(0xFFA4ABA6),
      streamSurface: const Color(0xFCFFFCF8),
      streamText: const Color(0xFF252A27),
      scrollControlSurface: const Color(0xF8FFFCF8),
      scrollControlForeground: const Color(0xFF303733),
      choiceSurface: accentSurface,
      choiceForeground: const Color(0xFF28302C),
      textShadow: const Color(0x26000000),
      composerShadow: const Color(0x1A000000),
    );
  }

  @override
  ChatReadingTheme copyWith({
    Color? canvas,
    Color? canvasScrim,
    Color? appBarSurface,
    Color? appBarForeground,
    Color? assistantText,
    Color? assistantInlineCode,
    Color? assistantCodeBlock,
    Color? userBubble,
    Color? onUserBubble,
    Color? userInlineCode,
    Color? userCodeBlock,
    Color? composerSurface,
    Color? composerGlassSurface,
    Color? composerBorder,
    Color? composerText,
    Color? composerHint,
    Color? composerToolSurface,
    Color? composerAccent,
    Color? composerSend,
    Color? composerStop,
    Color? sidebarSurface,
    Color? sidebarSelectedSurface,
    Color? sidebarPrimaryText,
    Color? sidebarSecondaryText,
    Color? sidebarTimestamp,
    Color? statusHeaderSurface,
    Color? statusHeaderText,
    Color? statusFallbackSurface,
    Color? statusBorder,
    Color? thinkingLabel,
    Color? thinkingText,
    Color? thinkingRail,
    Color? streamSurface,
    Color? streamText,
    Color? scrollControlSurface,
    Color? scrollControlForeground,
    Color? choiceSurface,
    Color? choiceForeground,
    Color? textShadow,
    Color? composerShadow,
  }) {
    return ChatReadingTheme(
      canvas: canvas ?? this.canvas,
      canvasScrim: canvasScrim ?? this.canvasScrim,
      appBarSurface: appBarSurface ?? this.appBarSurface,
      appBarForeground: appBarForeground ?? this.appBarForeground,
      assistantText: assistantText ?? this.assistantText,
      assistantInlineCode: assistantInlineCode ?? this.assistantInlineCode,
      assistantCodeBlock: assistantCodeBlock ?? this.assistantCodeBlock,
      userBubble: userBubble ?? this.userBubble,
      onUserBubble: onUserBubble ?? this.onUserBubble,
      userInlineCode: userInlineCode ?? this.userInlineCode,
      userCodeBlock: userCodeBlock ?? this.userCodeBlock,
      composerSurface: composerSurface ?? this.composerSurface,
      composerGlassSurface: composerGlassSurface ?? this.composerGlassSurface,
      composerBorder: composerBorder ?? this.composerBorder,
      composerText: composerText ?? this.composerText,
      composerHint: composerHint ?? this.composerHint,
      composerToolSurface: composerToolSurface ?? this.composerToolSurface,
      composerAccent: composerAccent ?? this.composerAccent,
      composerSend: composerSend ?? this.composerSend,
      composerStop: composerStop ?? this.composerStop,
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      sidebarSelectedSurface:
          sidebarSelectedSurface ?? this.sidebarSelectedSurface,
      sidebarPrimaryText: sidebarPrimaryText ?? this.sidebarPrimaryText,
      sidebarSecondaryText: sidebarSecondaryText ?? this.sidebarSecondaryText,
      sidebarTimestamp: sidebarTimestamp ?? this.sidebarTimestamp,
      statusHeaderSurface: statusHeaderSurface ?? this.statusHeaderSurface,
      statusHeaderText: statusHeaderText ?? this.statusHeaderText,
      statusFallbackSurface: statusFallbackSurface ?? this.statusFallbackSurface,
      statusBorder: statusBorder ?? this.statusBorder,
      thinkingLabel: thinkingLabel ?? this.thinkingLabel,
      thinkingText: thinkingText ?? this.thinkingText,
      thinkingRail: thinkingRail ?? this.thinkingRail,
      streamSurface: streamSurface ?? this.streamSurface,
      streamText: streamText ?? this.streamText,
      scrollControlSurface: scrollControlSurface ?? this.scrollControlSurface,
      scrollControlForeground:
          scrollControlForeground ?? this.scrollControlForeground,
      choiceSurface: choiceSurface ?? this.choiceSurface,
      choiceForeground: choiceForeground ?? this.choiceForeground,
      textShadow: textShadow ?? this.textShadow,
      composerShadow: composerShadow ?? this.composerShadow,
    );
  }

  @override
  ChatReadingTheme lerp(covariant ChatReadingTheme? other, double t) {
    if (other == null) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChatReadingTheme(
      canvas: lerpColor(canvas, other.canvas),
      canvasScrim: lerpColor(canvasScrim, other.canvasScrim),
      appBarSurface: lerpColor(appBarSurface, other.appBarSurface),
      appBarForeground: lerpColor(appBarForeground, other.appBarForeground),
      assistantText: lerpColor(assistantText, other.assistantText),
      assistantInlineCode: lerpColor(assistantInlineCode, other.assistantInlineCode),
      assistantCodeBlock: lerpColor(assistantCodeBlock, other.assistantCodeBlock),
      userBubble: lerpColor(userBubble, other.userBubble),
      onUserBubble: lerpColor(onUserBubble, other.onUserBubble),
      userInlineCode: lerpColor(userInlineCode, other.userInlineCode),
      userCodeBlock: lerpColor(userCodeBlock, other.userCodeBlock),
      composerSurface: lerpColor(composerSurface, other.composerSurface),
      composerGlassSurface: lerpColor(composerGlassSurface, other.composerGlassSurface),
      composerBorder: lerpColor(composerBorder, other.composerBorder),
      composerText: lerpColor(composerText, other.composerText),
      composerHint: lerpColor(composerHint, other.composerHint),
      composerToolSurface: lerpColor(composerToolSurface, other.composerToolSurface),
      composerAccent: lerpColor(composerAccent, other.composerAccent),
      composerSend: lerpColor(composerSend, other.composerSend),
      composerStop: lerpColor(composerStop, other.composerStop),
      sidebarSurface: lerpColor(sidebarSurface, other.sidebarSurface),
      sidebarSelectedSurface:
          lerpColor(sidebarSelectedSurface, other.sidebarSelectedSurface),
      sidebarPrimaryText: lerpColor(sidebarPrimaryText, other.sidebarPrimaryText),
      sidebarSecondaryText:
          lerpColor(sidebarSecondaryText, other.sidebarSecondaryText),
      sidebarTimestamp: lerpColor(sidebarTimestamp, other.sidebarTimestamp),
      statusHeaderSurface:
          lerpColor(statusHeaderSurface, other.statusHeaderSurface),
      statusHeaderText: lerpColor(statusHeaderText, other.statusHeaderText),
      statusFallbackSurface:
          lerpColor(statusFallbackSurface, other.statusFallbackSurface),
      statusBorder: lerpColor(statusBorder, other.statusBorder),
      thinkingLabel: lerpColor(thinkingLabel, other.thinkingLabel),
      thinkingText: lerpColor(thinkingText, other.thinkingText),
      thinkingRail: lerpColor(thinkingRail, other.thinkingRail),
      streamSurface: lerpColor(streamSurface, other.streamSurface),
      streamText: lerpColor(streamText, other.streamText),
      scrollControlSurface:
          lerpColor(scrollControlSurface, other.scrollControlSurface),
      scrollControlForeground:
          lerpColor(scrollControlForeground, other.scrollControlForeground),
      choiceSurface: lerpColor(choiceSurface, other.choiceSurface),
      choiceForeground: lerpColor(choiceForeground, other.choiceForeground),
      textShadow: lerpColor(textShadow, other.textShadow),
      composerShadow: lerpColor(composerShadow, other.composerShadow),
    );
  }
}

extension ChatReadingThemeContext on BuildContext {
  ChatReadingTheme get chatReadingTheme {
    final theme = Theme.of(this);
    return theme.extension<ChatReadingTheme>() ??
        ChatReadingTheme.fromColorScheme(theme.colorScheme);
  }
}
