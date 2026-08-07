import 'package:flutter/material.dart';

/// 键盘安全的编辑面板（底部弹出式）。
///
/// 解决 AlertDialog 在输入法弹出时整体上移、取消/保存按钮跳动的问题：
/// - 使用 showModalBottomSheet，内容随键盘高度（viewInsets）自动垫高；
/// - 标题与取消/保存按钮固定在底部、输入区可滚动，按钮位置稳定不跳动。
///
/// [buildResult] 在点击保存时调用：返回非 null 则关闭并带回结果；
/// 返回 null 表示校验未通过，面板保持打开。
/// [validateError] 可选：在保存前返回错误文本（非 null 时显示在面板内，
/// 不会像 SnackBar 那样被面板遮挡），返回 null 表示通过校验。
Future<T?> showKeyboardSafeEditSheet<T>({
  required BuildContext context,
  required String title,
  required List<Widget> fields,
  required T? Function() buildResult,
  String? Function()? validateError,
  String saveLabel = '保存',
  List<Widget> leadingActions = const [],
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _KeyboardSafeEditSheet<T>(
        title: title,
        fields: fields,
        buildResult: buildResult,
        validateError: validateError,
        saveLabel: saveLabel,
        leadingActions: leadingActions,
      );
    },
  );
}

class _KeyboardSafeEditSheet<T> extends StatefulWidget {
  const _KeyboardSafeEditSheet({
    required this.title,
    required this.fields,
    required this.buildResult,
    required this.validateError,
    required this.saveLabel,
    required this.leadingActions,
  });

  final String title;
  final List<Widget> fields;
  final T? Function() buildResult;
  final String? Function()? validateError;
  final String saveLabel;
  final List<Widget> leadingActions;

  @override
  State<_KeyboardSafeEditSheet<T>> createState() =>
      _KeyboardSafeEditSheetState<T>();
}

class _KeyboardSafeEditSheetState<T> extends State<_KeyboardSafeEditSheet<T>> {
  String? _errorText;

  void _finish() {
    final errorText = widget.validateError?.call();
    if (errorText != null && errorText.isNotEmpty) {
      setState(() {
        _errorText = errorText;
      });
      return;
    }
    final result = widget.buildResult();
    if (result == null) {
      return;
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘弹出时把面板垫到键盘上方
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...widget.fields,
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  ...widget.leadingActions,
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _finish,
                    child: Text(widget.saveLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
