import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/deep_seek_balance.dart';

/// 特别版：DeepSeek 官方余额查询。
///
/// 仅当模型端点指向 DeepSeek 官方（api.deepseek.com）时可用；
/// 失败（网络/非 200/解析错误）返回 null，但会经 debugPrint 输出
/// 原因（状态码/错误信息），便于排查"卡片为什么不显示"。
class DeepSeekBalanceService {
  const DeepSeekBalanceService._();

  static const String _balanceEndpoint =
      'https://api.deepseek.com/user/balance';

  /// 是否为 DeepSeek 官方端点（host 精确匹配，避免子串误判）。
  static bool isDeepSeekEndpoint(String baseUrl) {
    try {
      final uri = Uri.parse(baseUrl);
      return uri.host.toLowerCase() == 'api.deepseek.com';
    } on FormatException {
      return false;
    }
  }

  /// 规整 apiKey：去首尾空白，并剥离已带的 "Bearer " 前缀。
  static String normalizeApiKey(String apiKey) {
    var key = apiKey.trim();
    const bearerPrefix = 'Bearer ';
    if (key.toLowerCase().startsWith(bearerPrefix.toLowerCase())) {
      key = key.substring(bearerPrefix.length).trim();
    }
    return key;
  }

  /// 查询余额；失败返回 null（原因经 debugPrint 输出，便于排查）。
  static Future<DeepSeekBalance?> fetch(String apiKey) async {
    final normalizedKey = normalizeApiKey(apiKey);
    if (normalizedKey.isEmpty) {
      debugPrint('[DEEPSEEK_BALANCE] apiKey 为空，跳过查询');
      return null;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(Uri.parse(_balanceEndpoint))
          .timeout(const Duration(seconds: 10));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $normalizedKey',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 10));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint(
          '[DEEPSEEK_BALANCE] HTTP ${response.statusCode}: '
          '${body.length > 200 ? body.substring(0, 200) : body}',
        );
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        debugPrint('[DEEPSEEK_BALANCE] 响应不是 JSON 对象');
        return null;
      }
      return DeepSeekBalance.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('[DEEPSEEK_BALANCE] 查询失败: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
