/// DeepSeek 账号余额（来自官网 balance 接口）。
class DeepSeekBalance {
  const DeepSeekBalance({
    required this.isUnlimited,
    required this.totalBalance,
    required this.grantedBalance,
    required this.toppedUpBalance,
    this.expiresAt,
  });

  final bool isUnlimited;
  final double totalBalance;
  final double grantedBalance;
  final double toppedUpBalance;

  /// 赠送余额到期时间（ISO 字符串，可空）。
  final String? expiresAt;

  factory DeepSeekBalance.fromJson(Map<String, dynamic> json) {
    final balanceInfo = json['balance_infos'] as List<dynamic>? ?? const [];
    var total = 0.0;
    var granted = 0.0;
    var toppedUp = 0.0;
    String? expiresAt;
    for (final raw in balanceInfo) {
      if (raw is! Map) continue;
      final info = Map<String, dynamic>.from(raw);
      // 金额字段可能是字符串（如 "1.23"），统一 tryParse 兜底
      final totalAmount = _parseAmount(info['total_balance']);
      total += totalAmount;
      granted += _parseAmount(info['granted_balance']);
      toppedUp += _parseAmount(info['topped_up_balance']);
      final exp = info['expires_at'] as String?;
      if (exp != null && exp.isNotEmpty && !exp.startsWith('9999')) {
        expiresAt = exp;
      }
    }
    final isUnlimited = json['is_available'] == true && balanceInfo.isEmpty;
    return DeepSeekBalance(
      isUnlimited: isUnlimited,
      totalBalance: total,
      grantedBalance: granted,
      toppedUpBalance: toppedUp,
      expiresAt: expiresAt,
    );
  }

  /// 金额字段解析：数字直接取，字符串 tryParse，其他回退 0。
  static double _parseAmount(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }
}
