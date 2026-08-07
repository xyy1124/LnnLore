import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// 特别版：特殊状态栏面板——Flutter 原生 HTML 渲染（非 WebView）。
///
/// 模型输出（卡系统提示强制）的状态面板是 HTML/CSS（`<div style=...>`
/// 深色卡片、`<table>`、`<details>` 等）。用 [HtmlWidget] 原生解析渲染，
/// **不用 WebView**：Android 上 WebView 是 platform view，放在聊天
/// Stack/叠层里会压到 Flutter UI（标题栏/输入框）之上。
///
/// 安全性：渲染前剥离 `<script>` / iframe / object / embed / on* 事件 /
/// `javascript:` 协议 / fixed|absolute 定位 / z-index。
class SpecialStatusPanel extends StatelessWidget {
  const SpecialStatusPanel({
    super.key,
    required this.html,
    this.expanded = true,
    this.onTap,
  });

  final String html;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = _sanitizeHtml(html);

    if (body.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: expanded ? 520 : 180,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                physics: expanded
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
