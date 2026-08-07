import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/api_configs.dart';
import '../../models/deep_seek_balance.dart';
import '../../models/prompt_assembly.dart';
import '../../services/context_usage_breakdown.dart';
import '../../services/deepseek_balance_service.dart';
import '../../services/openai_compatible_api_service.dart';
import '../../services/thinking_chain_guard.dart';
import '../../services/thinking_chain_preset_service.dart';
import 'chat_view_model.dart';

/// 特别版：上下文用量详情页。
///
/// 展示最近一次请求的上下文使用情况：总令牌数（估算）、最大上下文、
/// 剩余空间与百分比，以及详细分解（预设各条 / 角色卡各字段 /
/// 世界书各本 / 用户消息 / 角色回复 / 思维链模板等）。
///
/// 令牌数按字符估算（CJK 字符 ≈ 1 token，其余按 4 字符 ≈ 1 token），
/// 与真实 tokenizer 存在偏差，仅作参考。
class ContextUsagePage extends StatefulWidget {
  const ContextUsagePage({
    super.key,
    required this.assembly,
    required this.contextWindow,
    this.modelName,
    /// 特别版：接口返回的真实 token 用量（发送后可用；null 隐藏真实用量区）。
    this.realUsage,
  });

  /// 最近一次发送的提示词组装结果；null 表示尚未发送过消息。
  final PromptAssemblyResult? assembly;

  /// 当前模型的上下文窗口大小（token）。
  final int contextWindow;

  final String? modelName;

  /// 特别版：接口真实用量（发送后可用；null 表示尚无/流式未返回）。
  final ChatCompletionUsage? realUsage;


  @override
  State<ContextUsagePage> createState() => _ContextUsagePageState();
}

class _ContextUsagePageState extends State<ContextUsagePage> {
  String? _thinkingChainTemplate;

  /// 余额加载状态：null=未查询/非 DeepSeek 端点，0=加载中，1=成功，2=失败/不可用。
  DeepSeekBalance? _deepSeekBalance;
  int _balanceState = 2; // 2=不可用（非 DeepSeek 端点或尚未查询）

  @override
  void initState() {
    super.initState();
    _loadTemplate();
    _loadBalance();
    // 特别版：API 配置/选中模型变化后重新查询余额
    apiConfigsNotifier.addListener(_onApiConfigChanged);
    selectedApiModelIdNotifier.addListener(_onApiConfigChanged);
  }

  @override
  void dispose() {
    apiConfigsNotifier.removeListener(_onApiConfigChanged);
    selectedApiModelIdNotifier.removeListener(_onApiConfigChanged);
    super.dispose();
  }

  void _onApiConfigChanged() {
    if (mounted) {
      _loadBalance();
    }
  }

  /// 查询 DeepSeek 官方余额（仅当当前模型端点指向 api.deepseek.com）。
  Future<void> _loadBalance() async {
    try {
      String? apiKey;
      var isDeepSeek = false;
      // 优先用 configId + modelId 精确定位所属 apiConfig（避免仅靠
      // model.id 在不同配置间混淆）
      final selectedId = selectedApiModelIdNotifier.value;
      for (final config in apiConfigsNotifier.value) {
        for (final model in config.models) {
          if (model.id == selectedId) {
            isDeepSeek = DeepSeekBalanceService.isDeepSeekEndpoint(
              config.baseUrl,
            );
            apiKey = config.apiKey;
            break;
          }
        }
        if (isDeepSeek) break;
      }
      if (!isDeepSeek) {
        if (mounted) {
          setState(() {
            _balanceState = 2;
            _deepSeekBalance = null;
          });
        }
        return;
      }
      if (apiKey == null || apiKey.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _balanceState = 2;
            _deepSeekBalance = null;
          });
        }
        debugPrint('[DEEPSEEK_BALANCE] 选中模型无 apiKey，跳过');
        return;
      }
      if (mounted) {
        setState(() {
          _balanceState = 0; // 加载中
        });
      }
      final balance = await DeepSeekBalanceService.fetch(apiKey);
      if (mounted) {
        setState(() {
          _deepSeekBalance = balance;
          _balanceState = balance == null ? 2 : 1;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _balanceState = 2;
        });
      }
    }
  }

  Future<void> _loadTemplate() async {
    try {
      final template = await ThinkingChainPresetService.instance
          .resolveActiveTemplate();
      if (mounted) {
        setState(() {
          _thinkingChainTemplate = template;
        });
      }
    } catch (_) {
      // 服务未初始化等场景：模板行不显示，不影响其他统计
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final assembly = widget.assembly;
    final maxContext = widget.contextWindow > 0 ? widget.contextWindow : 128000;

    final breakdown = _buildBreakdown();
    final total = breakdown.sections.values.fold<int>(
            0, (sum, v) => sum + v) +
        breakdown.worldBookEntries.fold<int>(
            0, (sum, e) => sum + e.tokens) +
        breakdown.chatHistory.fold<int>(0, (sum, m) => sum + m.tokens);
    // v61：进度条分母用安全输入上限（窗口 - 输出预留 - 安全余量），
    // "剩余" 也是相对安全上限的剩余（剩余 10K 不意味着还能安全输入 10K）
    final safeLimit = max(
      0,
      maxContext - ChatViewModel.kReservedOutputTokens - ChatViewModel.kSafetyMarginTokens,
    );
    final usedPercent = safeLimit <= 0
        ? 0.0
        : (total / safeLimit).clamp(0.0, 1.0).toDouble();
    final remainingSafe = max(0, safeLimit - total);

    final sectionItems = [
      for (final entry in breakdown.sections.entries)
        _UsageItem(name: entry.key, tokens: entry.value),
    ]..sort((a, b) => b.tokens.compareTo(a.tokens));

    // 聊天历史统计（按 我的消息/角色回复 分组）
    final userMessages =
        breakdown.chatHistory.where((m) => m.isUser).toList();
    final assistantMessages =
        breakdown.chatHistory.where((m) => !m.isUser).toList();
    final userTokens =
        userMessages.fold<int>(0, (s, m) => s + m.tokens);
    final assistantTokens =
        assistantMessages.fold<int>(0, (s, m) => s + m.tokens);

    return Scaffold(
      appBar: AppBar(
        title: const Text('上下文用量'),
      ),
      body: assembly == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '发送一条消息后即可查看本次请求的上下文用量与详细分解。\n'
                  '（令牌数为估算值，仅供参考）',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 总览卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${(usedPercent * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: usedPercent > 0.9
                                    ? colorScheme.error
                                    : colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.modelName != null)
                                    Text(
                                      widget.modelName!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  const SizedBox(height: 4),
                                  // v61：三组分开——下轮预计（约）/
                                  // 上轮实际（实，API usage）/ 安全上限
                                  Text(
                                    '下轮预计输入：${_formatTokens(total)}（约）\n'
                                    '${widget.realUsage != null && widget.realUsage!.promptTokens > 0 ? '上轮实际输入：${_formatTokens(widget.realUsage!.promptTokens)} · 输出 ${_formatTokens(widget.realUsage!.completionTokens)}（实）\n' : ''}'
                                    '安全输入上限：${_formatTokens(safeLimit)}\n'
                                    '预计剩余：${_formatTokens(remainingSafe)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: usedPercent,
                            minHeight: 10,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '令牌数为字符估算值（中文≈1/字，英文≈4字符/token），'
                          '与实际 tokenizer 可能有偏差',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // 特别版：接口真实用量（发送后可用时展示）
                        if (widget.realUsage != null &&
                            widget.realUsage!.totalTokens > 0) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '接口实际用量（usage）',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'prompt ${_formatTokens(widget.realUsage!.promptTokens)}'
                                  ' · completion ${_formatTokens(widget.realUsage!.completionTokens)}'
                                  ' · total ${_formatTokens(widget.realUsage!.totalTokens)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // DeepSeek 余额卡片（含加载中 / 不可用提示）
                if (_deepSeekBalance != null) ...[
                  _BalanceCard(balance: _deepSeekBalance!),
                ] else if (_balanceState == 0) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('DeepSeek 余额查询中…'),
                      ],
                    ),
                  ),
                ] else if (_balanceState == 2) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'DeepSeek 余额：当前模型非 DeepSeek 官方端点'
                      '或查询不可用（详见 debug 日志 DEEPSEEK_BALANCE）',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '提示词构成（Prompt Sections）',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                // 提示词分组
                if (sectionItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '暂无提示词构成数据',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final item in sectionItems)
                    _BreakdownTile(item: item, totalTokens: total),
                // 世界信息（逐条目：明细展示；token 已并入"世界书"总量）
                if (breakdown.worldBookEntries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ExpandableSection(
                    title: '世界信息（${breakdown.worldBookEntries.length} 个条目）',
                    summary: 'token 已并入上方"世界书"总量',
                    children: [
                      for (final entry in breakdown.worldBookEntries)
                        _EntryTile(
                          leading: '世界书 · ${entry.bookName}',
                          title: entry.entryName,
                          tokens: null,
                        ),
                    ],
                  ),
                ],
                // 聊天历史（逐条）
                if (breakdown.chatHistory.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ExpandableSection(
                    title: '聊天历史',
                    summary:
                        '我的消息 ${userMessages.length} 条 · ${_formatTokens(userTokens)}；'
                        '角色回复 ${assistantMessages.length} 条 · ${_formatTokens(assistantTokens)}',
                    children: [
                      if (userMessages.isNotEmpty) ...[
                        _SectionLabel('我的消息'),
                        for (final m in userMessages)
                          _EntryTile(
                            leading: '第 ${m.index} 条',
                            title: m.preview,
                            tokens: m.tokens,
                          ),
                      ],
                      if (assistantMessages.isNotEmpty) ...[
                        _SectionLabel('角色回复'),
                        for (final m in assistantMessages)
                          _EntryTile(
                            leading: '第 ${m.index} 条',
                            title: m.preview,
                            tokens: m.tokens,
                          ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  /// 格式化 token 数（>1000 显示为 K）。
  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    }
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return '$tokens';
  }

  /// 构建详细分解（提示词构成 + 世界信息条目 + 聊天历史明细）。
  ContextUsageBreakdown _buildBreakdown() {
    final assembly = widget.assembly;
    if (assembly == null) {
      return const ContextUsageBreakdown(
        sections: {},
        worldBookEntries: [],
        chatHistory: [],
      );
    }
    return breakdownContextTokens(
      assembly,
      templateText: _thinkingChainTemplate,
      tailReminder: _tailReminder,
    );
  }

  static const String _tailReminder =
      ThinkingChainGuard.thinkingChainTailReminder;
}

class _UsageItem {
  const _UsageItem({required this.name, required this.tokens});

  final String name;
  final int tokens;
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile({required this.item, required this.totalTokens});

  final _UsageItem item;
  final int totalTokens;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = totalTokens <= 0
        ? 0.0
        : (item.tokens / totalTokens).clamp(0.0, 1.0).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 5,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(percent * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                Text(
                  '${item.tokens} token',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 可展开分组（世界信息 / 聊天历史）。
class _ExpandableSection extends StatelessWidget {
  const _ExpandableSection({
    required this.title,
    required this.summary,
    required this.children,
  });

  final String title;
  final String summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          summary,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// 展开块内的小节标题（如 我的消息 / 角色回复）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

/// 明细条目（世界书条目 / 聊天消息单条）。
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.leading,
    required this.title,
    this.tokens,
  });

  final String leading;
  final String title;

  /// 可空：null 表示该行不展示 token（明细行，token 已并入总量）。
  final int? tokens;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              leading,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tokens == null ? '—' : '$tokens',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// DeepSeek 余额卡片。
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final DeepSeekBalance balance;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final low = !balance.isUnlimited &&
        (balance.totalBalance > 0 &&
            balance.totalBalance < 1.0); // 余额不足 1 元警示
    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'DeepSeek 余额',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (balance.isUnlimited)
                  Text(
                    '无限',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    '¥${balance.totalBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: low ? colorScheme.error : colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              balance.isUnlimited
                  ? '当前账号为无限额度（免费/企业账户）'
                  : '可用 ¥${balance.grantedBalance.toStringAsFixed(2)}'
                      '${balance.toppedUpBalance > 0 ? ' · 充值 ¥${balance.toppedUpBalance.toStringAsFixed(2)}' : ''}'
                      '${balance.expiresAt != null ? ' · 到期 ${balance.expiresAt!.substring(0, 10)}' : ''}'
                      '${low ? ' · 余额偏低，请及时充值' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
