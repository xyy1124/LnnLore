import 'package:pocket_inn/models/regex_script.dart';

import 'character_card_extensions_reader.dart';

/// 特别版：正则脚本执行服务（ST extensions.regex_scripts 对齐）。
class RegexScriptService {
  RegexScriptService._();

  /// 从角色卡 cardJson 读取 ST 正则脚本列表。
  /// ST 卡结构：data.extensions.regex_scripts（数组）。
  /// 统一读取器兼容真实手机导入链路的运行时 map 类型
  /// （Map<dynamic, dynamic> / 顶层已展开 data 等），避免某张卡
  /// 因类型检查过严而静默丢失脚本。
  static List<RegexScript> scriptsFromCharacterCard(
    Map<String, dynamic>? cardJson,
  ) {
    final raw = CharacterCardExtensionsReader.regexScripts(cardJson);
    if (raw == null) {
      return const [];
    }
    return [
      for (final item in raw)
        if (CharacterCardExtensionsReader.asMap(item) != null)
          RegexScript.fromJson(CharacterCardExtensionsReader.asMap(item)!),
    ];
  }

  /// 对文本按顺序执行 AI 输出阶段的正则脚本。
  ///
  /// - 按列表顺序逐条应用（ST 语义）
  /// - 替换模板支持 `${1}` 捕获组（Dart RegExp）
  /// - 空 findRegex / 非法正则跳过（不崩溃）
  /// - [markdownOnly] 脚本仅当 [forMarkdown] 时执行
  /// - **replaceString 含 `{{`（ST 宏模板）的脚本跳过**：ST 的兜底
  ///   脚本（如 StatusFallback）把整条回复替换成 `{{match}}/<!--panel-->/
  ///   {{getvar}}` 模板——PocketInn 无 ST 宏运行时，执行会导致正文被
  ///   整块替换后在显示清洗时剥成空（"合入后什么都没有"根因）。
  ///   PocketInn 的状态面板由 tracker 运行时从模型输出提取，无需 ST
  ///   兜底正则。
  static String applyToOutput(
    String text,
    List<RegexScript> scripts, {
    bool forMarkdown = false,
  }) {
    var result = text;
    for (final script in scripts) {
      if (!script.appliesToOutput) {
        continue;
      }
      if (script.markdownOnly && !forMarkdown) {
        continue;
      }
      if (!script.markdownOnly && forMarkdown) {
        // 非 markdownOnly 脚本在普通显示阶段已执行，Markdown 阶段不重复
        continue;
      }
      // 特别版：ST 宏模板脚本（{{match}}/{{getvar}}/{{setvar}} 等）
      // 依赖 ST 宏运行时，PocketInn 不执行——防止整块替换正文
      if (script.replaceString.contains('{{')) {
        continue;
      }
      result = _applyOne(result, script);
    }
    return result;
  }

  /// 危险正则启发式：嵌套量词（如 `(a+)+`、`(a*)*`、`(a+)*`）在
  /// 不匹配文本上可灾难性回溯（ReDoS）。检测到且文本较长时跳过。
  static final RegExp _nestedQuantifier = RegExp(r'\([^()]*[+*][^()]*\)[+*]');

  static String _applyOne(String text, RegexScript script) {
    final pattern = script.findRegex;
    if (pattern.isEmpty) {
      return text;
    }
    // 特别版：ReDoS 防护——超长正则 / 危险嵌套量词+长文本 / 超长文本
    // 直接跳过，避免角色卡自带正则在主 isolate 灾难性回溯冻结 UI。
    if (pattern.length > 500) {
      return text;
    }
    if (text.length > 20000) {
      return text;
    }
    if (text.length > 5000 && _nestedQuantifier.hasMatch(pattern)) {
      return text;
    }
    final RegExp regex;
    try {
      regex = RegExp(pattern);
    } catch (_) {
      return text; // 非法正则静默跳过
    }
    var result = text;
    if (script.trimStrings) {
      result = result.trim();
    }
    final replacement = script.replaceString;
    if (replacement.isEmpty) {
      // 空替换 = 删除匹配
      result = result.replaceAll(regex, '');
    } else {
      result = result.replaceAllMapped(regex, (match) {
        var out = replacement;
        // 支持 $1 / ${1} 捕获组（倒序替换，避免 $10 被 $1 截胡）
        for (var i = match.groupCount; i >= 1; i--) {
          final value = match.group(i) ?? '';
          out = out.replaceAll('\${$i}', value);
          out = out.replaceAll('\$$i', value);
        }
        return out;
      });
    }
    return result;
  }
}
