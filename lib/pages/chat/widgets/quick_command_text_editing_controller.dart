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
