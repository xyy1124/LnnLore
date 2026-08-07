/// 特别版：正则脚本（ST extensions.regex_scripts 对齐）。
///
/// 用于对 AI 输出做显示前文本处理：状态栏兜底追加、格式清理、隐藏副作用
/// 文本等。字段语义对齐 SillyTavern Regex Scripts 面板：
/// - [findRegex]：查找正则（Dart RegExp 语法，兼容多数 ST 写法）
/// - [replaceString]：替换模板，支持 `${1}`/`$1` 捕获组
/// - [trimStrings]：替换前先按正则匹配结果修剪原文
/// - [placement]：ST 的 ai_output / user_input / chat_input / slider
/// - [markdownOnly]：仅 Markdown 渲染阶段执行
/// - [promptOnly]：仅组装 prompt 时执行（不显示）
/// - [runOnEdit]：编辑消息时也执行
/// - [disabled]：停用
class RegexScript {
  const RegexScript({
    required this.name,
    required this.findRegex,
    required this.replaceString,
    this.trimStrings = false,
    this.placement = 'ai_output',
    this.markdownOnly = false,
    this.promptOnly = false,
    this.runOnEdit = false,
    this.disabled = false,
    this.minMessagesMatched = 0,
    this.maxMessagesMatched = 0,
  });

  final String name;
  final String findRegex;
  final String replaceString;
  final bool trimStrings;
  final String placement;
  final bool markdownOnly;
  final bool promptOnly;
  final bool runOnEdit;
  final bool disabled;
  final int minMessagesMatched;
  final int maxMessagesMatched;

  /// 是否在 AI 输出显示阶段执行（ST ai_output 主阶段）。
  bool get appliesToOutput =>
      !disabled &&
      !promptOnly &&
      (placement == 'ai_output' || placement.isEmpty);

  bool get appliesToInput => !disabled && placement == 'user_input';

  factory RegexScript.fromJson(Map<String, dynamic> json) {
    final findRegex = json['findRegex'] is String
        ? json['findRegex'] as String
        : '';
    return RegexScript(
      name: json['scriptName'] is String
          ? json['scriptName'] as String
          : (findRegex.isNotEmpty ? findRegex : '未命名'),
      findRegex: findRegex,
      replaceString: json['replaceString'] is String
          ? json['replaceString'] as String
          : '',
      // ST 卡部分字段可能是数组/其他类型，全部安全读取（null/false 兜底）
      trimStrings: json['trimStrings'] is bool
          ? json['trimStrings'] as bool
          : false,
      placement: json['placement'] is String
          ? json['placement'] as String
          : 'ai_output',
      markdownOnly: json['markdownOnly'] is bool
          ? json['markdownOnly'] as bool
          : false,
      promptOnly: json['promptOnly'] is bool
          ? json['promptOnly'] as bool
          : false,
      runOnEdit: json['runOnEdit'] is bool ? json['runOnEdit'] as bool : false,
      disabled: json['disabled'] is bool ? json['disabled'] as bool : false,
      minMessagesMatched: json['minMessagesMatched'] is int
          ? json['minMessagesMatched'] as int
          : 0,
      maxMessagesMatched: json['maxMessagesMatched'] is int
          ? json['maxMessagesMatched'] as int
          : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'scriptName': name,
        'findRegex': findRegex,
        'replaceString': replaceString,
        'trimStrings': trimStrings,
        'placement': placement,
        'markdownOnly': markdownOnly,
        'promptOnly': promptOnly,
        'runOnEdit': runOnEdit,
        'disabled': disabled,
        'minMessagesMatched': minMessagesMatched,
        'maxMessagesMatched': maxMessagesMatched,
      };
}
