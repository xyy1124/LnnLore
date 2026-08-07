import 'package:flutter/material.dart';

import 'quick_command_marks.dart';

/// 快捷指令富文本输入控制器。
///
/// 把文本中的快捷指令占位标记（`\uE000指令名\uE001`）渲染为
/// 斜体 + 主题色 + 加粗，与普通文本明显区分，避免把提示词原文
/// 暴露在输入框里；占位标记仍是普通文本（发送时可还原/展开）。
class QuickCommandTextEditingController extends TextEditingController {
  QuickCommandTextEditingController({super.text});

  /// 标记段样式：斜体 + 主题色。
  TextStyle _markStyle(BuildContext context, TextStyle base) {
    final primary = Theme.of(context).colorScheme.primary;
    return base.copyWith(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      color: primary,
    );
  }

  /// v53：删除拦截——Backspace / Delete 删到占位标记（`\uE000指令名\uE001`）
  /// 的**任意一个字符**时，一次性删除整个标记：
  /// - 之前按一次只删一个码元，先删 `\uE001` 留下 `\uE000指令名`（半截
  ///   标记渲染异常），还要再删很多下才能删完（用户反馈）；
  /// - 现在光标在标记后按 Backspace / 在标记前按 Delete / 在标记中间
  ///   删除，都会整体移除标记，光标停在标记原起点。
  @override
  set value(TextEditingValue newValue) {
    final old = value;
    final oldText = old.text;
    final newText = newValue.text;

    // 仅拦截"单字符删除"（无选择的 Backspace/Delete 会让文本恰好少 1）。
    // 选择删除/输入法组合输入/其他多字符变化保持默认行为。
    if (newText.length == oldText.length - 1) {
      // 定位被删字符：oldText 与 newText 的第一个差异位置
      var diff = 0;
      while (diff < newText.length &&
          diff < oldText.length &&
          oldText[diff] == newText[diff]) {
        diff++;
      }
      // 被删字符属于某个占位标记 → 删除整个标记
      for (final match in kQuickCommandMarkPattern.allMatches(oldText)) {
        if (diff >= match.start && diff < match.end) {
          final removed = oldText.substring(0, match.start) +
              oldText.substring(match.end);
          super.value = TextEditingValue(
            text: removed,
            selection: TextSelection.collapsed(offset: match.start),
          );
          return;
        }
      }
    }
    super.value = newValue;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final segments = splitQuickCommandMarks(text);
    final spans = <InlineSpan>[
      for (final (isMark, segment) in segments)
        TextSpan(
          text: isMark ? '【$segment】' : segment,
          style: isMark ? _markStyle(context, base) : base,
        ),
    ];
    return TextSpan(style: base, children: spans);
  }
}
