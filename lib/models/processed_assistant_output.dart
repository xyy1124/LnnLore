import 'package:pocket_inn/services/tracker_runtime.dart';

/// 特别版：AI 回复处理结果——正文 + 状态 patch + 可选动作 + 特殊状态栏。
///
/// [_persistSetVarAndStrip] 重构后的返回载体（不再只返回 String）：
/// - [displayText]：入库/显示的正文（已剥离协议块与 setvar 宏）
/// - [patch]：状态更新（调用方已持久化到会话变量）
/// - [choices]：模型动态给出的可选动作（挂到消息下渲染按钮）
/// - [specialStatusHtml]：提取到的特殊状态栏 HTML（ST 三件套面板，
///   由 TrackerStatusBar 优先渲染；无则 null）
class ProcessedAssistantOutput {
  const ProcessedAssistantOutput({
    required this.displayText,
    required this.patch,
    this.choices = const [],
    this.specialStatusHtml,
  });

  final String displayText;
  final StatePatch patch;
  final List<DecisionChoice> choices;
  final String? specialStatusHtml;

  bool get hasChoices => choices.isNotEmpty;
}
