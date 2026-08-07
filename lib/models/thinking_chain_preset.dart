import 'package:freezed_annotation/freezed_annotation.dart';

part 'thinking_chain_preset.freezed.dart';
part 'thinking_chain_preset.g.dart';

/// 思维链约束方案（特别版）。
///
/// 一套完整的【强制思维模式】模板，用户可创建多套并选择一套生效。
/// 模板必须保留 12 步步骤标题（第 1 步与第 12 步为校验必备锚点）。
@freezed
abstract class ThinkingChainPreset with _$ThinkingChainPreset {
  const ThinkingChainPreset._();

  const factory ThinkingChainPreset({
    required String id,
    required String name,
    required String template,
    required DateTime updatedAt,
  }) = _ThinkingChainPreset;

  factory ThinkingChainPreset.fromJson(Map<String, dynamic> json) =>
      _$ThinkingChainPresetFromJson(json);
}
