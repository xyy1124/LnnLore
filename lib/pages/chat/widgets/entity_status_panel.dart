import 'package:flutter/material.dart';

import '../../../services/tracker_runtime.dart';

/// v91：实体卡（群像卡）状态面板——Flutter 原生 Tab 渲染。
///
/// 与 v1 的 HTML 面板（SpecialStatusPanel）不同，实体卡面板按角色
/// 分区并以**可滚动 TabBar** 切换（沈昭华｜洛青鸾｜…），每个 Tab 下
/// 渲染该角色的字段卡。数据来自 [EntityPanelData]（结构化模型，
/// 由 [TrackerRuntime.buildEntityPanelData] 构建，同一套 presentation
/// 解析保证与 HTML 路径同值同文案）。
///
/// 行为：
/// - 0 个已出场角色且无全局字段 → 不显示（调用方过滤）
/// - 仅全局字段 → 只显示全局区
/// - 1 个角色 → 不显示 TabBar，直接显示角色名 + 字段
/// - 2+ 角色 → 可滚动 TabBar，选中状态存 entityId（新角色加入不抢焦点）
/// - 标题栏折叠整个面板（含全局区、TabBar、角色内容）
class EntityStatusPanel extends StatefulWidget {
  const EntityStatusPanel({
    super.key,
    required this.data,
    this.expanded = true,
    this.onExpandedChanged,
  });

  final EntityPanelData data;

  /// 初始展开状态。
  final bool expanded;

  /// 展开/收起切换后的回调（供外部持久化用户偏好）。
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<EntityStatusPanel> createState() => _EntityStatusPanelState();
}

class _EntityStatusPanelState extends State<EntityStatusPanel> {
  late bool _expanded;
  String? _selectedEntityId;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded;
    _selectedEntityId = widget.data.entities.isNotEmpty
        ? widget.data.entities.first.entityId
        : null;
  }

  @override
  void didUpdateWidget(EntityStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      _expanded = widget.expanded;
    }
    // 当前选中角色被过滤/移除时回退到第一个
    if (_selectedEntityId != null &&
        widget.data.entities.every((e) => e.entityId != _selectedEntityId)) {
      _selectedEntityId = widget.data.entities.isNotEmpty
          ? widget.data.entities.first.entityId
          : null;
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final data = widget.data;
    final hasGlobal = data.globalFields.isNotEmpty;
    final entities = data.entities;
    final hasEntities = entities.isNotEmpty;

    if (!hasGlobal && !hasEntities) {
      return const SizedBox.shrink();
    }
    if (data.title.trim().isEmpty && !hasGlobal && entities.length == 1) {
      // 单角色且无标题：直接渲染字段（无标题栏）
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: _EntityFieldCard(
          entity: entities.first,
          colorScheme: colorScheme,
          showName: true,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏（折叠整个面板）
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
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
                          data.title.trim().isEmpty ? '状态面板' : data.title.trim(),
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
            ),
            if (_expanded) ...[
              // 全局字段区（混合卡）
              if (hasGlobal)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _GlobalFieldsCard(
                    fields: data.globalFields,
                    colorScheme: colorScheme,
                  ),
                ),
              if (hasEntities) ...[
                // 角色 TabBar（2+ 角色才显示）
                if (entities.length >= 2)
                  SizedBox(
                    height: 40,
                    child: DefaultTabController(
                      length: entities.length,
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorColor: colorScheme.primary,
                        labelColor: colorScheme.primary,
                        unselectedLabelColor: colorScheme.onSurfaceVariant,
                        labelStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        dividerColor: Colors.transparent,
                        tabs: entities
                            .map(
                              (e) => Tab(
                                text: e.displayName,
                                height: 40,
                              ),
                            )
                            .toList(),
                        onTap: (index) {
                          setState(() {
                            _selectedEntityId = entities[index].entityId;
                          });
                        },
                      ),
                    ),
                  ),
                // 当前角色字段卡
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _EntityFieldCard(
                    entity: entities.firstWhere(
                      (e) => e.entityId == _selectedEntityId,
                      orElse: () => entities.first,
                    ),
                    colorScheme: colorScheme,
                    showName: entities.length < 2,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 全局字段区（混合卡根字段）。
class _GlobalFieldsCard extends StatelessWidget {
  const _GlobalFieldsCard({
    required this.fields,
    required this.colorScheme,
  });

  final List<EntityFieldModel> fields;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final field in fields) _buildRow(field),
        ],
      ),
    );
  }

  Widget _buildRow(EntityFieldModel field) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 2,
        children: [
          Text(
            '${field.label}：',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            field.value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          if (field.title.isNotEmpty)
            Text(
              '· ${field.title}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _parseColor(field.color, colorScheme),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个角色的字段卡。
class _EntityFieldCard extends StatelessWidget {
  const _EntityFieldCard({
    required this.entity,
    required this.colorScheme,
    required this.showName,
  });

  final EntityPanelModel entity;
  final ColorScheme colorScheme;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                entity.displayName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          for (final field in entity.fields) _buildField(field),
        ],
      ),
    );
  }

  Widget _buildField(EntityFieldModel field) {
    final titleColor = _parseColor(field.color, colorScheme);
    final narrative = field.narrative.isNotEmpty
        ? field.narrative
        : field.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(
                '${field.label}：',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                '【${field.value}${field.percent.isNotEmpty ? '/${field.percent}' : ''}】',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              if (field.title.isNotEmpty)
                Text(
                  '· ${field.title}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
            ],
          ),
          if (narrative.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                narrative,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 解析卡声明颜色（#RRGGBB），非法时回退主题色。
Color _parseColor(String raw, ColorScheme colorScheme) {
  if (raw.isEmpty) {
    return colorScheme.primary;
  }
  var hex = raw.trim();
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  }
  if (hex.length == 6) {
    final value = int.tryParse(hex, radix: 16);
    if (value != null) {
      return Color(0xFF000000 | value);
    }
  }
  return colorScheme.primary;
}
