import 'dart:async';

import 'package:flutter/material.dart';

/// v51：顶部滑入通知（OverlayEntry 实现，不依赖 Scaffold/SnackBar）——
/// 角色导入/删除等操作反馈从屏幕顶部出现，避免底部 SnackBar 在键盘
/// 弹出、横屏与不同屏幕高度下错位或被遮挡。
///
/// 用法：
/// ```dart
/// AppTopNotice.show(context, '已导入角色：夜无央');
/// AppTopNotice.show(context, '导入失败', type: AppNoticeType.error);
/// ```
enum AppNoticeType { info, success, warning, error }

class AppTopNotice {
  AppTopNotice._();

  static void show(
    BuildContext context,
    String message, {
    AppNoticeType type = AppNoticeType.info,
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AppTopNoticeView(
        message: message,
        type: type,
        duration: duration,
        onDismissed: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _AppTopNoticeView extends StatefulWidget {
  const _AppTopNoticeView({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final AppNoticeType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppTopNoticeView> createState() => _AppTopNoticeViewState();
}

class _AppTopNoticeViewState extends State<_AppTopNoticeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    // 进入动画完成后停留 duration，再反向滑出并移除
    _controller.forward().whenComplete(() {
      _timer = Timer(widget.duration, _dismiss);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().whenComplete(widget.onDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, iconColor) = switch (widget.type) {
      AppNoticeType.success => (Icons.check_circle_outline, Colors.greenAccent),
      AppNoticeType.warning => (
          Icons.warning_amber_rounded,
          Colors.orangeAccent,
        ),
      AppNoticeType.error => (Icons.error_outline, colorScheme.error),
      AppNoticeType.info => (Icons.info_outline, colorScheme.primary),
    };

    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slide,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
