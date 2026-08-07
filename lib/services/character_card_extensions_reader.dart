/// 特别版：角色卡 extensions 统一读取器。
///
/// 手机导入/持久化链路中卡 JSON 的实际形状可能与测试构造的标准结构
/// 不完全一致（嵌套 map 的运行时类型、顶层是否已展开 data 等）。所有
/// 读取 extensions/tracker/regex_scripts 的地方统一走这里，避免各自
/// 手写深层路径 + 严格 `is Map<String, dynamic>` 检查导致某张卡静默
/// 降级为内置面板（"每张卡样式都一样"）。
class CharacterCardExtensionsReader {
  CharacterCardExtensionsReader._();

  /// 任意 Map（含 `Map<dynamic, dynamic>` / `Map<String, Object?>` 等
  /// 运行时类型）转成 `Map<String, dynamic>`；非 Map 返回 null。
  static Map<String, dynamic>? asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return null;
  }

  /// 取卡 JSON 的 data 段：标准 `{spec, data}` 结构取 `cardJson['data']`；
  /// 兼容调用方已经传入展开后的 data 对象（顶层即 data 字段）。
  static Map<String, dynamic>? cardData(Map<String, dynamic>? cardJson) {
    if (cardJson == null) {
      return null;
    }
    final nested = asMap(cardJson['data']);
    if (nested != null) {
      return nested;
    }
    // 兼容已展开的 data 对象（顶层就是 description/personality/extensions）
    return asMap(cardJson);
  }

  /// 取 data.extensions（兼容顶层展开后的直接 extensions）。
  static Map<String, dynamic>? extensions(Map<String, dynamic>? cardJson) {
    return asMap(cardData(cardJson)?['extensions']);
  }

  /// 取 extensions.tracker 声明。
  static Map<String, dynamic>? tracker(Map<String, dynamic>? cardJson) {
    return asMap(extensions(cardJson)?['tracker']);
  }

  /// 取 extensions.regex_scripts 列表（兼容 regexScripts 键名）。
  static List<dynamic>? regexScripts(Map<String, dynamic>? cardJson) {
    final ext = extensions(cardJson);
    if (ext == null) {
      return null;
    }
    final raw = ext['regex_scripts'] ?? ext['regexScripts'];
    return raw is List ? raw : null;
  }
}
