import 'package:flutter/material.dart';

import '../../../models/tracker_config.dart';
import '../../../services/chat_database_service.dart';
import '../../../services/chat_display_sanitizer.dart';
import '../../../services/chat_variable_service.dart';
import 'special_status_panel.dart';

/// 特别版：Tracker 状态栏（App 渲染，非模型输出 HTML）。
///
/// 数据源为会话变量表（chat_variables）：
/// - 有特殊状态栏 HTML（`__special_status_html__`，ST 三件套面板，
///   由 [ChatDisplaySanitizer.extract] 从回复/开场提取）→ 优先渲染
///   [SpecialStatusPanel]（带样式的 HTML 面板）；
/// - 无 → 回退渲染状态变量 chips（按卡 uiHints/schema 顺序、中文标签）。
/// 可折叠：默认展开全部，点标题区收起为一行。
class TrackerStatusBar extends StatefulWidget {
  const TrackerStatusBar({
    super.key,
    required this.sessionId,
    required this.cardJson,
    /// 父级变化时刷新（如消息数增加/回复完成）
    required this.refreshTrigger,
    /// 草稿阶段直接传入的开场状态栏 HTML（优先于变量表）
    this.specialStatusHtmlOverride,
  });

  final String sessionId;
  final Map<String, dynamic>? cardJson;
  final int refreshTrigger;
  final String? specialStatusHtmlOverride;

  @override
  State<TrackerStatusBar> createState() => _TrackerStatusBarState();
}

class _TrackerStatusBarState extends State<TrackerStatusBar> {
  Map<String, String> _variables = const {};
  TrackerConfig _config = const TrackerConfig();
  bool _expanded = true;
  bool _loading = true;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _config = TrackerConfig.fromCardJson(widget.cardJson);
    _load();
  }

  @override
  void didUpdateWidget(TrackerStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.refreshTrigger != widget.refreshTrigger ||
        oldWidget.cardJson != widget.cardJson ||
        oldWidget.specialStatusHtmlOverride != widget.specialStatusHtmlOverride) {
      _config = TrackerConfig.fromCardJson(widget.cardJson);
      // 会话切换瞬间先清空，避免短暂显示上一个会话的旧数据
      if (oldWidget.sessionId != widget.sessionId) {
        _variables = const {};
        _loading = true;
      }
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final initialVariables = _initialVariablesFromConfig();

    if (widget.sessionId.isEmpty) {
      // draft 阶段：会话尚未落库，用卡的 initialState 渲染（不卡 _loading）
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _variables = initialVariables;
        _loading = false;
      });
      debugPrint('[状态栏渲染] draft sessionId 为空，使用 initialState');
      return;
    }

    try {
      final storedVariables =
          await ChatDatabaseService.instance.getSessionVariables(
        widget.sessionId,
      );

      if (!mounted || token != _loadToken) {
        return;
      }

      final variables = <String, String>{
        ...initialVariables,
        ...storedVariables,
      };

      final html = _cleanup(variables[kSpecialStatusHtmlKey]);
      debugPrint(
        '[状态栏渲染] 会话 ${widget.sessionId} 变量 ${variables.length} 项，面板 '
        '${html == null ? "无" : "${html.length}字: ${html.length > 120 ? html.substring(0, 120) : html}"}',
      );

      setState(() {
        _variables = variables;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('[状态栏渲染] 变量读取失败: $error\n$stackTrace');

      if (!mounted || token != _loadToken) {
        return;
      }

      setState(() {
        _variables = initialVariables;
        _loading = false;
      });
    }
  }

  /// 卡的 initialState 转成变量表格式（draft 阶段/读库失败兜底）。
  Map<String, String> _initialVariablesFromConfig() {
    final result = <String, String>{};
    _config.initialState.forEach((key, value) {
      if (value != null) {
        result[key] = '$value';
      }
    });
    return result;
  }

  /// 去空白/代码块围栏：HTML 面板可能带 ```html 包裹。
  static String? _cleanup(String? value) {
    final html = value?.trim();
    if (html == null || html.isEmpty) {
      return null;
    }
    return html;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    /// 清洗 + 解析 getvar；变量未加载完且面板含 getvar 时不渲染
    /// （避免把 {{getvar}} 解析成空/显示模板原文）。
    String? resolvePanelHtml(String? rawHtml) {
      final raw = _cleanup(rawHtml ?? '');
      if (raw == null) {
        return null;
      }
      if (_loading &&
          _variables.isEmpty &&
          ChatVariableService.hasGetVars(raw)) {
        return null;
      }
      return _cleanup(ChatVariableService.resolveGetVars(raw, _variables));
    }

    if (!_loading) {
      // DB 里的最新特殊状态栏优先（避免 draft override 一直压住新状态）
      final specialHtml = resolvePanelHtml(_variables[kSpecialStatusHtmlKey]);
      if (specialHtml != null) {
        return SpecialStatusPanel(
          html: specialHtml,
          expanded: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
        );
      }
    }

    // draft 阶段兜底：仅当 DB 未加载/无值时使用开场 override
    final overrideHtml = resolvePanelHtml(widget.specialStatusHtmlOverride);
    if (overrideHtml != null) {
      return SpecialStatusPanel(
        html: overrideHtml,
        expanded: _expanded,
        onTap: () => setState(() => _expanded = !_expanded),
      );
    }

    if (_loading) {
      return const SizedBox.shrink();
    }

    final displayItems = _displayItems();
    if (displayItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _expanded
                    ? Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (final item in displayItems)
                            _StatusChip(
                              label: item.$1,
                              value: item.$2,
                              colorScheme: colorScheme,
                            ),
                        ],
                      )
                    : Text(
                        '${displayItems.length} 项状态',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(width: 4),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按 displayOrder 输出 (label, value) 列表。
  List<(String, String)> _displayItems() {
    final config = _config;
    if (_variables.isEmpty) {
      return const [];
    }
    final result = <(String, String)>[];
    final order = config.displayOrder.isNotEmpty
        ? config.displayOrder
        : _variables.keys
            .where((k) => k != kSpecialStatusHtmlKey)
            .toList(growable: false);
    final seen = <String>{};
    for (final key in order) {
      if (key == kSpecialStatusHtmlKey ||
          seen.contains(key) ||
          !_variables.containsKey(key)) {
        continue;
      }
      seen.add(key);
      final value = _variables[key];
      if (value == null || value.isEmpty) {
        continue;
      }
      final schema = config.stateSchema[key];
      final label = (schema != null && schema.label.isNotEmpty) ? schema.label : key;
      result.add((label, value));
    }
    // 未在 order 的字段追加
    for (final key in _variables.keys) {
      if (key == kSpecialStatusHtmlKey || seen.contains(key)) {
        continue;
      }
      final value = _variables[key];
      if (value == null || value.isEmpty) {
        continue;
      }
      final schema = config.stateSchema[key];
      final label = (schema != null && schema.label.isNotEmpty) ? schema.label : key;
      result.add((label, value));
    }
    return result;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label：$value',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
