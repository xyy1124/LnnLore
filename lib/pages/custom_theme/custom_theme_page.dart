import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../theme/chat_reading_theme.dart';
import '../../widgets/chat_markdown_body.dart';
import 'widgets/theme_font_family_tile.dart';
import 'widgets/theme_palette_picker.dart';

class CustomThemePage extends StatelessWidget {
  const CustomThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: appSettingsNotifier,
      builder: (context, settings, _) {
        final themeConfig = resolveThemeConfig(settings);
        final chatTextTheme = themeConfig.chatTextTheme;

        return Scaffold(
          appBar: AppBar(title: const Text('高级调整')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                title: '主题颜色',
                child: Column(
                  children: [
                    ThemeFontFamilyConfigTile(
                      fontFamily: themeConfig.customFontFamily,
                      onChanged: (value) =>
                          updateThemeConfig(customFontFamily: value),
                    ),
                    const SizedBox(height: 12),
                    _ThemeColorPaletteTile(
                      selectedIndex: resolveThemeColorPaletteIndex(settings),
                      onChanged: (index) =>
                          updateThemeConfig(themeColorIndex: index),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '引号与阴影',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _QuoteStyleDropdownTile(
                      value: chatTextTheme.quoteStyle,
                      onChanged: (style) =>
                          updateChatTextThemeSettings(quoteStyle: style),
                    ),
                    const SizedBox(height: 12),
                    _SwitchTile(
                      title: '聊天消息字体阴影',
                      value: chatTextTheme.enableMessageTextShadow,
                      onChanged: (value) => updateChatTextThemeSettings(
                        enableMessageTextShadow: value,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '文本样式',
                child: Column(
                  children: [
                    _TextThemePresetBar(
                      settings: settings,
                      onApply: (presetId) =>
                          _applyTextThemePreset(settings, presetId),
                    ),
                    const SizedBox(height: 12),
                    _BodyTextColorConfigTile(
                      settings: settings,
                      lightValue: chatTextTheme.bodyTextColorPaletteIndex,
                      darkValue: chatTextTheme.bodyTextColorDarkPaletteIndex,
                      onChanged: (light, dark) => updateChatTextThemeSettings(
                        bodyTextColorPaletteIndex: light,
                        bodyTextColorDarkPaletteIndex: dark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TextStyleConfigTile(
                      settings: settings,
                      title: '引号内容',
                      value: chatTextTheme.quotedTextStyle,
                      onChanged: (value) =>
                          updateChatTextThemeSettings(quotedTextStyle: value),
                    ),
                    const SizedBox(height: 12),
                    _TextStyleConfigTile(
                      settings: settings,
                      title: '括号内容',
                      value: chatTextTheme.bracketTextStyle,
                      onChanged: (value) =>
                          updateChatTextThemeSettings(bracketTextStyle: value),
                    ),
                    const SizedBox(height: 12),
                    _TextStyleConfigTile(
                      settings: settings,
                      title: 'Markdown 斜体',
                      value: chatTextTheme.italicTextStyle,
                      onChanged: (value) =>
                          updateChatTextThemeSettings(italicTextStyle: value),
                    ),
                    const SizedBox(height: 12),
                    _TextStyleConfigTile(
                      settings: settings,
                      title: 'Markdown 加粗',
                      value: chatTextTheme.boldTextStyle,
                      onChanged: (value) =>
                          updateChatTextThemeSettings(boldTextStyle: value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '效果预览',
                child: _ThemePreviewCard(settings: settings),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 特别版：一键应用的文本样式预设。
///
/// 每套预设同时配置浅色（light）与深色（dark）两套配色：
/// 深色主题使用高亮色系（淡紫/亮橙/浅灰/白），保证在深色背景上清晰可读。
/// - 自动优化：浅色跟随当前主题色；深色使用高亮中性搭配
/// - 高对比经典 / 暖色柔和 / 冷色清新：三套手写配色方案
void _applyTextThemePreset(AppSettings settings, String presetId) {
  final themeConfig = resolveThemeConfig(settings);
  final seedIndex = themeConfig.themeColorIndex;

  switch (presetId) {
    case 'auto':
      // 自动优化：浅色以主题色为引用色、柔和色系中与主题色最接近的
      // 为括号色；深色使用高亮柔和色（柔和色系中与主题色最近的
      // 两个相邻色），斜体灰、加粗黑白，正文跟随主题。
      final softStart = 32;
      final softEnd = customThemePalette.length - 1;
      final softQuotedDark = _nearestPaletteIndex(
        customThemePalette[seedIndex],
        start: softStart,
        end: softEnd,
      );
      final softBracketDark = _nextSoftColor(softQuotedDark);
      updateChatTextThemeSettings(
        bodyTextColorPaletteIndex: null,
        bodyTextColorDarkPaletteIndex: null,
        enableMessageTextShadow: false,
        quotedTextStyle: ChatTextStyleConfig(
          paletteIndex: seedIndex,
          darkPaletteIndex: softQuotedDark,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
        bracketTextStyle: ChatTextStyleConfig(
          paletteIndex: _nearestPaletteIndex(
            customThemePalette[seedIndex],
            start: softStart,
            end: softEnd,
          ),
          darkPaletteIndex: softBracketDark,
          fontStyleMode: ChatTextFontStyleMode.platform,
          opacity: 0.85,
        ),
        italicTextStyle: ChatTextStyleConfig(
          paletteIndex: 30,
          darkPaletteIndex: 29,
          fontStyleMode: ChatTextFontStyleMode.italic,
          opacity: 0.7,
        ),
        boldTextStyle: ChatTextStyleConfig(
          paletteIndex: 31,
          darkPaletteIndex: 28,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
      );
    case 'high-contrast':
      // 高对比经典：浅色深蓝引用；深色亮黄引用 + 亮橙括号，开启阴影提升层级
      updateChatTextThemeSettings(
        bodyTextColorPaletteIndex: null,
        bodyTextColorDarkPaletteIndex: null,
        enableMessageTextShadow: true,
        quotedTextStyle: ChatTextStyleConfig(
          paletteIndex: 25,
          darkPaletteIndex: 14,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
        bracketTextStyle: ChatTextStyleConfig(
          paletteIndex: 7,
          darkPaletteIndex: 13,
          fontStyleMode: ChatTextFontStyleMode.platform,
          opacity: 0.9,
        ),
        italicTextStyle: ChatTextStyleConfig(
          paletteIndex: 30,
          darkPaletteIndex: 29,
          fontStyleMode: ChatTextFontStyleMode.italic,
          opacity: 0.75,
        ),
        boldTextStyle: ChatTextStyleConfig(
          paletteIndex: 31,
          darkPaletteIndex: 28,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
      );
    case 'warm':
      // 暖色柔和：浅色橙引用；深色亮橙引用 + 亮黄括号
      updateChatTextThemeSettings(
        bodyTextColorPaletteIndex: null,
        bodyTextColorDarkPaletteIndex: null,
        enableMessageTextShadow: false,
        quotedTextStyle: ChatTextStyleConfig(
          paletteIndex: 0,
          darkPaletteIndex: 13,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
        bracketTextStyle: ChatTextStyleConfig(
          paletteIndex: 13,
          darkPaletteIndex: 14,
          fontStyleMode: ChatTextFontStyleMode.platform,
          opacity: 0.85,
        ),
        italicTextStyle: ChatTextStyleConfig(
          paletteIndex: 30,
          darkPaletteIndex: 29,
          fontStyleMode: ChatTextFontStyleMode.italic,
          opacity: 0.7,
        ),
        boldTextStyle: ChatTextStyleConfig(
          paletteIndex: 31,
          darkPaletteIndex: 28,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
      );
    case 'cool':
      // 冷色清新：浅色蓝引用；深色淡紫引用 + 亮绿括号
      updateChatTextThemeSettings(
        bodyTextColorPaletteIndex: null,
        bodyTextColorDarkPaletteIndex: null,
        enableMessageTextShadow: false,
        quotedTextStyle: ChatTextStyleConfig(
          paletteIndex: 1,
          darkPaletteIndex: 21,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
        bracketTextStyle: ChatTextStyleConfig(
          paletteIndex: 6,
          darkPaletteIndex: 16,
          fontStyleMode: ChatTextFontStyleMode.platform,
          opacity: 0.85,
        ),
        italicTextStyle: ChatTextStyleConfig(
          paletteIndex: 30,
          darkPaletteIndex: 29,
          fontStyleMode: ChatTextFontStyleMode.italic,
          opacity: 0.7,
        ),
        boldTextStyle: ChatTextStyleConfig(
          paletteIndex: 31,
          darkPaletteIndex: 28,
          fontStyleMode: ChatTextFontStyleMode.bold,
          opacity: 1.0,
        ),
      );
  }
}

/// 在调色板 [start..end] 区间内查找与 [target] 色距最近的索引（RGB 欧氏距离）。
int _nearestPaletteIndex(
  Color target, {
  required int start,
  required int end,
}) {
  var best = start;
  var bestDistance = double.infinity;
  for (var i = start; i <= end; i++) {
    final color = customThemePalette[i];
    final dr = color.r - target.r;
    final dg = color.g - target.g;
    final db = color.b - target.b;
    final distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return best;
}

/// 返回柔和色系（32 起）中当前索引的下一个相邻色（循环），
/// 用于深色模式下引用/括号的成对搭配。
int _nextSoftColor(int index) {
  final softEnd = customThemePalette.length - 1;
  final next = index + 1;
  return next <= softEnd ? next : 32;
}

/// 文本样式预设选择栏（一键应用，可继续微调下方各项）。
class _TextThemePresetBar extends StatelessWidget {
  const _TextThemePresetBar({required this.settings, required this.onApply});

  final AppSettings settings;
  final ValueChanged<String> onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '预设方案（一键应用，可继续微调下方各项）',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('自动优化'),
              onPressed: () => onApply('auto'),
            ),
            ActionChip(
              label: const Text('高对比经典'),
              onPressed: () => onApply('high-contrast'),
            ),
            ActionChip(
              label: const Text('暖色柔和'),
              onPressed: () => onApply('warm'),
            ),
            ActionChip(
              label: const Text('冷色清新'),
              onPressed: () => onApply('cool'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({required this.settings});

  final AppSettings settings;

  static const String _userPreviewText =
      '请把“旅馆回声”写得更轻一些，把（动作描写）收住，再让 *尾音* 和 **关键词** 更有层次。';
  static const String _characterPreviewText =
      '她答道：「我会把月色留下。」然后略过（脚步声），只把 *语气* 放慢，再把 **结论** 说稳。';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final readingTheme = context.chatReadingTheme;
    final themeConfig = resolveThemeConfig(settings);
    final chatTextTheme = resolveActiveChatTextTheme(settings);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: readingTheme.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: readingTheme.statusBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: readingTheme.appBarSurface,
            child: Row(
              children: [
                Icon(
                  Icons.menu_rounded,
                  size: 18,
                  color: readingTheme.appBarForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '夜间对话',
                    style: TextStyle(
                      color: readingTheme.appBarForeground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: readingTheme.appBarForeground,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _PreviewChip(
                  label:
                      '${chatTextTheme.quoteStyle.leading}${chatTextTheme.quoteStyle.trailing}',
                  color: colorScheme.secondary,
                ),
                _PreviewChip(
                  label: chatTextTheme.enableMessageTextShadow
                      ? '文字阴影'
                      : '清晰正文',
                  color: readingTheme.composerAccent,
                ),
                _PreviewChip(
                  label: themeConfig.customFontFamily ?? '系统字体',
                  color: readingTheme.thinkingRail,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (settings.showAvatar) ...[
                  _PreviewAvatar(
                    backgroundColor: readingTheme.composerToolSurface,
                    foregroundColor: readingTheme.assistantText,
                    label: '角',
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ChatMarkdownBody(
                    text: _characterPreviewText,
                    settings: settings,
                    textColor: readingTheme.assistantText,
                    inlineCodeColor: readingTheme.assistantInlineCode,
                    codeBlockColor: readingTheme.assistantCodeBlock,
                    applyBodyTextColor: false,
                    selectable: false,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: readingTheme.statusHeaderSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: readingTheme.statusBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_graph_rounded,
                    size: 14,
                    color: readingTheme.composerAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '状态 · 氛围稳定',
                    style: TextStyle(
                      color: readingTheme.statusHeaderText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: readingTheme.userBubble,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                    child: ChatMarkdownBody(
                      text: _userPreviewText,
                      settings: settings,
                      textColor: readingTheme.onUserBubble,
                      inlineCodeColor: readingTheme.userInlineCode,
                      codeBlockColor: readingTheme.userCodeBlock,
                      applyBodyTextColor: false,
                      selectable: false,
                    ),
                  ),
                ),
                if (settings.showAvatar) ...[
                  const SizedBox(width: 8),
                  _PreviewAvatar(
                    backgroundColor: readingTheme.composerAccent,
                    foregroundColor: colorScheme.onPrimary,
                    label: '我',
                  ),
                ],
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: readingTheme.composerSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: readingTheme.composerBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '输入消息',
                    style: TextStyle(
                      color: readingTheme.composerHint,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: readingTheme.composerSend,
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 16,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _QuoteStyleDropdownTile extends StatelessWidget {
  const _QuoteStyleDropdownTile({required this.value, required this.onChanged});

  final AppQuoteStyle value;
  final ValueChanged<AppQuoteStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '引号',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '选择显示样式',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 50, maxWidth: 60),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<AppQuoteStyle>(
                  alignment: AlignmentDirectional.center,
                  value: value,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  focusColor: Colors.transparent,
                  dropdownColor: colorScheme.surface,
                  iconEnabledColor: colorScheme.onSurfaceVariant,
                  items: AppQuoteStyle.selectableValues.map((style) {
                    return DropdownMenuItem<AppQuoteStyle>(
                      value: style,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          '${style.leading}${style.trailing}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (style) {
                    if (style != null) {
                      onChanged(style);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeColorPaletteTile extends StatelessWidget {
  const _ThemeColorPaletteTile({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前颜色',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '仅显示已选颜色，点击右侧展开完整色板',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            PalettePickerButton(
              selectedIndex: selectedIndex,
              onChanged: onChanged,
              swatchSize: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyTextColorConfigTile extends StatelessWidget {
  const _BodyTextColorConfigTile({
    required this.settings,
    required this.lightValue,
    required this.darkValue,
    required this.onChanged,
  });

  final AppSettings settings;
  final int? lightValue;
  final int? darkValue;
  final void Function(int? light, int? dark) onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chatTextTheme = resolveActiveChatTextTheme(settings);
    final seedColor = resolveThemeColor(settings);
    final lightColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    final lightBackground = lightColorScheme.surfaceContainerLow;
    final darkBackground = darkColorScheme.surfaceContainerLow;
    final customEnabled = lightValue != null || darkValue != null;
    final effectiveLightIndex =
        lightValue ?? defaultBodyTextColorPaletteIndex(Brightness.light);
    final effectiveDarkIndex =
        darkValue ?? defaultBodyTextColorPaletteIndex(Brightness.dark);
    final effectiveTextColor = customEnabled
        ? (colorScheme.brightness == Brightness.dark
            ? paletteColorAt(effectiveDarkIndex)
            : paletteColorAt(effectiveLightIndex))
        : colorScheme.onSurface;
    final previewStyle = buildBaseMessageTextStyle(
      textColor: effectiveTextColor,
      brightness: colorScheme.brightness,
      enableShadow: chatTextTheme.enableMessageTextShadow,
    );

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '正文颜色',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        customEnabled ? '使用自定义正文颜色' : '跟随当前主题正文色',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: customEnabled,
                  onChanged: (enabled) {
                    if (enabled) {
                      onChanged(
                        defaultBodyTextColorPaletteIndex(Brightness.light),
                        defaultBodyTextColorPaletteIndex(Brightness.dark),
                      );
                    } else {
                      onChanged(null, null);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text('示例正文', style: previewStyle)),
                if (customEnabled) ...[
                  const SizedBox(width: 12),
                  DualPalettePickerButton(
                    lightIndex: effectiveLightIndex,
                    darkIndex: effectiveDarkIndex,
                    onChanged: (light, dark) =>
                        onChanged(light, dark),
                    swatchSize: 20,
                    lightBackground: lightBackground,
                    darkBackground: darkBackground,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TextStyleConfigTile extends StatelessWidget {
  const _TextStyleConfigTile({
    required this.settings,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final AppSettings settings;
  final String title;
  final ChatTextStyleConfig value;
  final ValueChanged<ChatTextStyleConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chatTextTheme = resolveActiveChatTextTheme(settings);
    final seedColor = resolveThemeColor(settings);
    final lightColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    final lightBackground = lightColorScheme.surfaceContainerLow;
    final darkBackground = darkColorScheme.surfaceContainerLow;
    final previewBaseStyle = buildBaseMessageTextStyle(
      textColor: colorScheme.onSurface,
      brightness: colorScheme.brightness,
      enableShadow: chatTextTheme.enableMessageTextShadow,
    );
    final previewStyle = buildDecoratedChatTextStyle(
      baseStyle: previewBaseStyle,
      config: value,
      brightness: colorScheme.brightness,
    );

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text('示例文本', style: previewStyle)),
                const SizedBox(width: 12),
                DualPalettePickerButton(
                  lightIndex: value.paletteIndex,
                  darkIndex: value.darkPaletteIndex ?? value.paletteIndex,
                  onChanged: (light, dark) =>
                      onChanged(value.copyWith(
                        paletteIndex: light,
                        darkPaletteIndex: dark,
                      )),
                  swatchSize: 20,
                  lightBackground: lightBackground,
                  darkBackground: darkBackground,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '样式',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ChatTextFontStyleMode>(
              initialValue: value.fontStyleMode,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: ChatTextFontStyleMode.values.map((mode) {
                return DropdownMenuItem<ChatTextFontStyleMode>(
                  value: mode,
                  child: Text(mode.label),
                );
              }).toList(),
              onChanged: (next) {
                if (next != null) {
                  onChanged(value.copyWith(fontStyleMode: next));
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '透明度',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${(value.opacity * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Slider(
              value: value.opacity,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              onChanged: (next) => onChanged(value.copyWith(opacity: next)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PreviewAvatar extends StatelessWidget {
  const _PreviewAvatar({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.label,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
