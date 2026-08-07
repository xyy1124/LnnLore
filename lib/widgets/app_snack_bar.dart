import 'package:flutter/material.dart';

/// 特别版：统一提示条——深色主题化、圆角胶囊、带类型图标与动作按钮。
///
/// 两种用法（等价）：
/// ```dart
/// // 方式一：直接弹出（内部自动 hideCurrentSnackBar 防堆叠）
/// AppSnackBar.show(context, '已删除角色');
/// AppSnackBar.show(context, '导入失败', type: AppSnackBarType.error);
///
/// // 方式二：配合现有 .showSnackBar() 链（返回 SnackBar widget）
/// ScaffoldMessenger.of(context)
///     .showSnackBar(AppSnackBar.build(context, '已导入角色'));
/// ```
///
/// 样式继承全局 [SnackBarThemeData]（floating 圆角/深色），此处补充图标与
/// 动作按钮；不破坏主题浅色模式（图标色随 colorScheme 自适应）。
enum AppSnackBarType {
  info,
  success,
  warning,
  error,
}

class AppSnackBar {
  AppSnackBar._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
    bool showCloseIcon = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar() // 连发时平滑替换，不堆叠
      ..showSnackBar(
        build(
          context,
          message,
          type: type,
          duration: duration,
          actionLabel: actionLabel,
          onAction: onAction,
          showCloseIcon: showCloseIcon,
        ),
      );
  }

  /// 构造一个深色主题化的 [SnackBar]（配合现有 ScaffoldMessenger 链使用）。
  static SnackBar build(
    BuildContext context,
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
    bool showCloseIcon = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, iconColor) = switch (type) {
      AppSnackBarType.success => (
          Icons.check_circle_outline,
          Colors.greenAccent,
        ),
      AppSnackBarType.warning => (
          Icons.warning_amber_rounded,
          Colors.orangeAccent,
        ),
      AppSnackBarType.error => (
          Icons.error_outline,
          colorScheme.error,
        ),
      AppSnackBarType.info => (
          Icons.info_outline,
          colorScheme.primary,
        ),
    };

    return SnackBar(
      duration: duration ??
          Duration(
            milliseconds: actionLabel != null ? 4000 : 2500,
          ),
      behavior: SnackBarBehavior.floating,
      content: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              onPressed: onAction,
            )
          : null,
      showCloseIcon: showCloseIcon,
      closeIconColor: colorScheme.onSurfaceVariant,
    );
  }
}
