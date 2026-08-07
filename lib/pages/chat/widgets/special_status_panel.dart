import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// 特别版：特殊状态栏面板——Flutter 原生 HTML 渲染（非 WebView）。
///
/// 模型输出（卡系统提示强制）的状态面板是 HTML/CSS（`<div style=...>`
/// 深色卡片、`<table>`、`<details>` 等）。用 [HtmlWidget] 原生解析渲染，
/// **不用 WebView**：Android 上 WebView 是 platform view，放在聊天
/// Stack/叠层里会压到 Flutter UI（标题栏/输入框）之上。
///
/// v49：支持折叠——传入 [title]（从面板 HTML 的 `<summary>` 提取）时，
/// 顶部渲染可点击标题栏（箭头指示展开/收起），点击切换内部折叠状态；
/// 不传 [title] 时行为与旧版完全一致（[expanded] 由外部控制 + [onTap]）。
/// HtmlWidget 对 `<details>/<summary>` 渲染不可靠（v47 截图问题），
/// 折叠由 Flutter 原生控制，不再依赖 HTML 标签。
///
/// 安全性：渲染前剥离 `<script>` / iframe / object / embed / on* 事件 /
/// `javascript:` 协议 / fixed|absolute 定位 / z-index。
class SpecialStatusPanel extends StatefulWidget {
  const SpecialStatusPanel({
    super.key,
    required this.html,
    this.title,
    this.expanded = true,
    this.onTap,
  });

  final String html;

  /// 折叠标题（从 `<summary>` 提取）；为 null 时不显示标题栏。
  final String? title;

  /// 初始展开状态（内部状态自此初始化；外部 [expanded] 变化会同步进来）。
  final bool expanded;

  /// 折叠切换时的外部回调（可选，兼容旧调用方）。
  final VoidCallback? onTap;

  @override
  State<SpecialStatusPanel> createState() => _SpecialStatusPanelState();
}

class _SpecialStatusPanelState extends State<SpecialStatusPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded;
  }

  @override
  void didUpdateWidget(SpecialStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（如 TrackerStatusBar）控制 expanded 变化时同步内部状态
    if (widget.expanded != oldWidget.expanded) {
      _expanded = widget.expanded;
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = _sanitizeHtml(widget.html);

    if (body.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final title = widget.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasTitle)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggleExpanded,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            if (!hasTitle || _expanded)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onTap,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: _expanded ? 520 : 180,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.zero,
                      physics: _expanded
                          ? const BouncingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      child: HtmlWidget(
                        body,
                        textStyle: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 13,
                          height: 1.35,
                        ),
                        customStylesBuilder: (element) {
                          final tag = element.localName;

                          if (tag == 'html' || tag == 'body') {
                            return {
                              'margin': '0',
                              'padding': '0',
                              'background': 'transparent',
                            };
                          }

                          if (tag == 'table') {
                            return {
                              'width': '100%',
                              'border-collapse': 'collapse',
                            };
                          }

                          if (tag == 'td' || tag == 'th') {
                            return {
                              'padding': '4px 6px',
                            };
                          }

                          return null;
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 去代码块围栏 + 剥脚本/危险标签/事件属性/fixed 定位。
  String _sanitizeHtml(String value) {
    var result = value.trim();

    result = result.replaceAll(
      RegExp(r'^```(?:html|xml)?\s*|\s*```$', caseSensitive: false),
      '',
    );

    result = result.replaceAll(
      RegExp(r'<script\b[\s\S]*?</script>', caseSensitive: false),
      '',
    );

    result = result.replaceAll(
      RegExp(
        r'<(?:iframe|object|embed)\b[\s\S]*?</(?:iframe|object|embed)>',
        caseSensitive: false,
      ),
      '',
    );

    result = result.replaceAll(
      RegExp(
        r"\son\w+\s*=\s*("".*?""|'.*?'|[^\s>]+)",
        caseSensitive: false,
      ),
      '',
    );

    result = result.replaceAll(
      RegExp(r'javascript:', caseSensitive: false),
      '',
    );

    // 防止状态栏 HTML 自带 fixed/absolute/z-index 抢占页面顶部。
    result = result.replaceAll(
      RegExp(r'position\s*:\s*(?:fixed|absolute)\s*;?', caseSensitive: false),
      '',
    );

    result = result.replaceAll(
      RegExp(r'z-index\s*:\s*[^;"'']+;?', caseSensitive: false),
      '',
    );

    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*?)</body>',
      caseSensitive: false,
    ).firstMatch(result);

    return bodyMatch?.group(1)?.trim() ?? result.trim();
  }
}
