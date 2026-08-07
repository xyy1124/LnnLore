import 'package:freezed_annotation/freezed_annotation.dart';

part 'quick_command.freezed.dart';
part 'quick_command.g.dart';

/// 快捷指令的发送类型。
enum QuickCommandType {
  /// 直接发送：点击后立即以提示词发送（如：继续、下一场景）。
  direct,

  /// 询问后发送：点击后先弹出输入框补充内容，再把
  /// 提示词 + 补充内容一起发送（如：时间流逝、旁白、详细描写）。
  prompt,

  /// 特别版：插入型——点击后把提示词直接插入输入框当前光标位置，
  /// 不发送；可连续点击多个，累计插入，插入后继续编辑。
  insert;

  static QuickCommandType fromValue(String? value) {
    for (final type in QuickCommandType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return QuickCommandType.direct;
  }
}

/// 快捷指令类型的中文标签与图标（菜单/管理页共用）。
extension QuickCommandTypeUi on QuickCommandType {
  String get label => switch (this) {
    QuickCommandType.direct => '直接发送',
    QuickCommandType.prompt => '询问后发送',
    QuickCommandType.insert => '插入输入框',
  };

  String get description => switch (this) {
    QuickCommandType.direct => '点击后立即发送',
    QuickCommandType.prompt => '点击后先输入补充内容再发送',
    QuickCommandType.insert => '点击后插入输入框光标处，可多次',
  };
}

/// 快捷指令：聊天时一键发送的预设指令。
///
/// 点击快捷指令后，聊天消息以 [name] 显示（输入框与消息列表均不显示
/// [prompt]），但实际发送给模型的内容为 [prompt]（提示词）。
@freezed
abstract class QuickCommand with _$QuickCommand {
  const QuickCommand._();

  const factory QuickCommand({
    required String id,
    required String name,
    required String prompt,
    @Default(0) int order,
    /// 特别版：发送类型（直接发送 / 询问后发送），默认直接发送。
    @Default(QuickCommandType.direct) QuickCommandType type,
  }) = _QuickCommand;

  factory QuickCommand.fromJson(Map<String, dynamic> json) =>
      _$QuickCommandFromJson(json);
}
