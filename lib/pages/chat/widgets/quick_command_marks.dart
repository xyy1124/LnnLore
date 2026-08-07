import 'package:pocket_inn/models/quick_command.dart';

/// 快捷指令占位标记工具。
///
/// 插入型/询问后发送型快捷指令在输入框与消息界面中以「占位标记」显示
/// （不暴露提示词原文），发送给模型时才展开为完整提示词：
/// - 输入框内使用私有区字符包裹的标记 `\uE000指令名\uE001`，
///   由 [QuickCommandTextEditingController] 渲染为斜体彩色；
/// - 发送前用 [expandQuickCommandMarks] 展开为提示词（存入 modelText）；
/// - 消息渲染时用 [restoreQuickCommandMarks] 还原为可读占位。
const String kQuickCommandMarkStart = '\uE000';
const String kQuickCommandMarkEnd = '\uE001';

final RegExp _markPattern = RegExp(
  // [\s\S] 匹配换行（指令名可能含换行）
  '$kQuickCommandMarkStart([\\s\\S]*?)$kQuickCommandMarkEnd',
);

/// 公开正则：占位标记（v53——输入控制器删除拦截需要）。
final RegExp kQuickCommandMarkPattern = _markPattern;

/// 包裹指令名为占位标记。
String wrapQuickCommandMark(String name) =>
    '$kQuickCommandMarkStart$name$kQuickCommandMarkEnd';

/// 是否包含快捷指令占位标记。
bool hasQuickCommandMark(String text) => _markPattern.hasMatch(text);

/// 提取第一个占位标记中的指令名；无标记返回 null。
String? extractQuickCommandName(String text) {
  final match = _markPattern.firstMatch(text);
  return match?.group(1);
}

/// 展开：把文本中的占位标记替换为对应提示词（发送给模型前调用）。
/// 未匹配到的标记（指令已删除）还原为可读占位，不泄露私有区字符。
String expandQuickCommandMarks(String text, List<QuickCommand> commands) {
  var result = text;
  for (final command in commands) {
    final name = command.name.trim();
    if (name.isEmpty) {
      continue;
    }
    result = result.replaceAll(
      wrapQuickCommandMark(name),
      command.prompt.trim(),
    );
  }
  // 剩余未匹配标记还原为可读占位，并剥离未配对的私有区字符
  return restoreQuickCommandMarks(result)
      .replaceAll(kQuickCommandMarkStart, '')
      .replaceAll(kQuickCommandMarkEnd, '');
}

/// 还原：把占位标记还原为可读形式（消息界面渲染 / 编辑预填）。
String restoreQuickCommandMarks(String text) => text.replaceAllMapped(
  _markPattern,
  (match) => '【快捷指令：${match.group(1)}】',
);

/// 编辑还原：把展开文本中匹配的提示词逐个替换回占位标记。
///
/// [markNames] 按出现顺序给出需要还原的指令名（原消息标记 + 编辑新插入
/// 标记合并后的顺序）；提示词出现在开头时用前缀替换（保留其后内容），
/// 否则用 replaceFirst。匹配不到的提示词（用户已改写）原样保留。
String restorePromptsToMarks(
  String expanded,
  List<QuickCommand> commands,
  List<String> markNames,
) {
  var rebuilt = expanded;
  for (final name in markNames) {
    if (name.isEmpty) {
      continue;
    }
    QuickCommand? command;
    for (final c in commands) {
      if (c.name.trim() == name) {
        command = c;
        break;
      }
    }
    if (command == null) {
      continue;
    }
    final prompt = command.prompt.trim();
    if (prompt.isEmpty) {
      continue;
    }
    rebuilt = rebuilt.startsWith(prompt)
        ? wrapQuickCommandMark(name) + rebuilt.substring(prompt.length)
        : rebuilt.replaceFirst(prompt, wrapQuickCommandMark(name));
  }
  return rebuilt;
}

/// 把文本按占位标记切分（供富文本渲染用）。
/// 返回 [(是否标记段, 文本)] 列表。
List<(bool, String)> splitQuickCommandMarks(String text) {
  final result = <(bool, String)>[];
  var cursor = 0;
  for (final match in _markPattern.allMatches(text)) {
    if (match.start > cursor) {
      result.add((false, text.substring(cursor, match.start)));
    }
    result.add((true, match.group(1) ?? ''));
    cursor = match.end;
  }
  if (cursor < text.length) {
    result.add((false, text.substring(cursor)));
  }
  return result;
}
