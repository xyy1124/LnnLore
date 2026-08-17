import 'package:flutter/material.dart';

import '../../../theme/chat_reading_theme.dart';

/// 特别版：流式输出悬浮面板（列表外，固定高度）。
///
/// 显示在聊天列表上方的悬浮层（Stack Positioned），**不参与 ListView
/// 布局**——流式文本如何增长都不会改变列表高度，发消息后主界面
/// 彻底定住（无下移、无抖动、无跳顶）。输出结束后由正式消息
/// 一次性加入列表。固定高度 [panelHeight]（内部滚动跟随最新内容）。
class StreamingPanel extends StatelessWidget {
  const StreamingPanel({
    super.key,
    required this.text,
    this.thinking = '',
    this.isThinking = false,
    this.retryNotice = '',
    this.speakerName,
    this.panelHeight = 140,
  });

  /// 已流式输出的正文文本。
  final String text;

  /// 已流式输出的思考链文本（非空时显示"思考中"提示）。
  final String thinking;

  /// 是否正在思考（有 thinkingDelta 输出）。
  final bool isThinking;

  /// 思维链重试/服务端重试提示（非空时优先展示）。
  final String retryNotice;

  /// 群聊当前发言人名字（显示在面板头部）。
  final String? speakerName;

  /// 面板固定高度（完全固定，不随内容伸缩）。
  final double panelHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final readingTheme = context.chatReadingTheme;
    final hasThinking = thinking.isNotEmpty || isThinking;
    final showRetry = retryNotice.isNotEmpty;
    final displayText = showRetry ? retryNotice : text;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: readingTheme.streamSurface,
      child: SizedBox(
        height: panelHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (hasThinking || showRetry)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: showRetry
                            ? colorScheme.error
                            : colorScheme.primary,
                      ),
                    )
                  else
                    Icon(Icons.auto_awesome, size: 12, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      showRetry
                          ? '生成重试中…'
                          : (hasThinking
                              ? '思考中…'
                              : (speakerName != null
                                  ? '$speakerName 生成中…'
                                  : '生成中…')),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: showRetry
                            ? colorScheme.error
                            : readingTheme.thinkingLabel,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 固定高度文本区：reverse 滚动自动跟随最新内容
              Expanded(
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    displayText.isEmpty ? '…' : '$displayText ▌',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: showRetry
                          ? colorScheme.error
                          : readingTheme.streamText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
