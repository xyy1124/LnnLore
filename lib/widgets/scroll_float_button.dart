import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/chat_reading_theme.dart';

class ScrollFloatButton extends StatefulWidget {
  const ScrollFloatButton({
    super.key,
    required this.scrollController,
    this.isReversed = false,
    /// 特别版：外部统一跳底（bottom anchor 对齐真实底部）。
    /// 非空时到底按钮改走本回调，不再自行 animateTo(maxScrollExtent)。
    this.onScrollToBottom,
  });

  final ScrollController scrollController;
  final bool isReversed;
  final VoidCallback? onScrollToBottom;

  @override
  State<ScrollFloatButton> createState() => _ScrollFloatButtonState();
}

class _ScrollFloatButtonState extends State<ScrollFloatButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  Timer? _hideTimer;
  bool _atTop = false;
  bool _atBottom = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _opacityAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    widget.scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _hideTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = widget.scrollController.position;
    final maxExtent = pos.maxScrollExtent;
    final minExtent = pos.minScrollExtent;
    final offset = pos.pixels;
    final canScroll = maxExtent - minExtent > 0;

    setState(() {
      if (widget.isReversed) {
        _atTop = offset >= maxExtent - 1;
        _atBottom = offset <= minExtent + 1;
      } else {
        _atTop = offset <= minExtent + 1;
        _atBottom = offset >= maxExtent - 1;
      }
    });

    _hideTimer?.cancel();
    if (canScroll) {
      _animationController.forward();
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _animationController.reverse();
      });
    } else {
      _animationController.reverse();
    }
  }

  void _scrollToVisualTop() {
    final target = widget.isReversed
        ? widget.scrollController.position.maxScrollExtent
        : widget.scrollController.position.minScrollExtent;
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 到底（视觉底部）：优先走外部 [widget.onScrollToBottom]（父级 bottom
  /// anchor + ensureVisible 对齐真实底部，能处理假 maxScrollExtent 白空白）；
  /// 无外部回调时回退到旧的 maxScrollExtent 循环校准。
  Future<void> _scrollToVisualBottom() async {
    final external = widget.onScrollToBottom;
    if (external != null) {
      external();
      return;
    }
    for (var i = 0; i < 6; i++) {
      if (!mounted || !widget.scrollController.hasClients) {
        return;
      }

      final position = widget.scrollController.position;
      final target = widget.isReversed
          ? position.minScrollExtent
          : position.maxScrollExtent;

      await widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );

      await WidgetsBinding.instance.endOfFrame;

      if (!widget.scrollController.hasClients) {
        return;
      }

      final pos = widget.scrollController.position;
      final atVisualBottom = widget.isReversed
          ? pos.pixels <= pos.minScrollExtent + 1
          : pos.extentAfter <= 1;

      if (atVisualBottom) {
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final readingTheme = context.chatReadingTheme;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.bottomRight,
            child: child,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            icon: Icons.arrow_upward,
            tooltip: '到顶',
            onTap: _atTop ? null : _scrollToVisualTop,
            colorScheme: colorScheme,
            readingTheme: readingTheme,
          ),
          const SizedBox(height: 8),
          _buildButton(
            icon: Icons.arrow_downward,
            tooltip: '到底',
            onTap: _atBottom ? null : _scrollToVisualBottom,
            colorScheme: colorScheme,
            readingTheme: readingTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required ColorScheme colorScheme,
    required ChatReadingTheme readingTheme,
  }) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.3,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(24),
        color: readingTheme.scrollControlSurface,
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 15,
              color: readingTheme.scrollControlForeground,
            ),
          ),
        ),
      ),
    );
  }
}
