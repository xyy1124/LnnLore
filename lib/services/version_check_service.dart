import 'dart:convert';
import 'dart:io';

import 'storage_service.dart';

/// 特别版：GitHub 新版本检查服务。
///
/// 通过 GitHub API 查询指定仓库的最新 release tag，与本地版本比较。
/// 发布仓库（owner/repo）可在设置中配置（默认上游 adoretes/PocketInn，
/// 差异化发布时可改为自己的仓库）。
class VersionCheckService {
  VersionCheckService._();

  static final VersionCheckService instance = VersionCheckService._();

  /// SharedPreferences 键名。
  static const String _keyEnabled = 'version_check_enabled';
  static const String _keyOwner = 'version_check_owner';
  static const String _keyRepo = 'version_check_repo';
  static const String _keyLastChecked = 'version_check_last_checked';

  /// 默认发布仓库。
  static const String defaultOwner = 'adoretes';
  static const String defaultRepo = 'PocketInn';

  /// 上游锚点版本：本项目 fork 时的上游版本（特别版基于该版本改版）。
  /// 上游发布的新版本只要高于此锚点即提示更新（不比较本地特别版号，
  /// 因为特别版号与上游版本号体系独立）。
  static const String baselineUpstreamVersion = '1.3.2';

  /// 判断上游最新 release 是否为可提示的新版本（> 锚点版本）。
  static bool isUpstreamUpdateAvailable(String latestTag) {
    return compareVersions(baselineUpstreamVersion, latestTag) > 0;
  }

  Future<bool> isEnabled() async {
    final saved = StorageService.instance.getBool(_keyEnabled);
    return saved ?? true;
  }

  Future<void> setEnabled(bool value) async {
    await StorageService.instance.setBool(_keyEnabled, value);
  }

  Future<String> getOwner() async {
    final saved = StorageService.instance.getString(_keyOwner);
    return saved?.isNotEmpty == true ? saved! : defaultOwner;
  }

  Future<void> setOwner(String value) async {
    await StorageService.instance.setString(_keyOwner, value.trim());
  }

  Future<String> getRepo() async {
    final saved = StorageService.instance.getString(_keyRepo);
    return saved?.isNotEmpty == true ? saved! : defaultRepo;
  }

  Future<void> setRepo(String value) async {
    await StorageService.instance.setString(_keyRepo, value.trim());
  }

  Future<DateTime?> getLastChecked() async {
    final saved = StorageService.instance.getString(_keyLastChecked);
    if (saved == null || saved.isEmpty) {
      return null;
    }
    return DateTime.tryParse(saved);
  }

  Future<void> _setLastChecked(DateTime time) async {
    await StorageService.instance.setString(_keyLastChecked, time.toIso8601String());
  }

  /// 查询最新 release 的 tag（如 "v1.4.0-special.2"）。
  Future<String?> fetchLatestTag() async {
    final owner = await getOwner();
    final repo = await getRepo();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'PocketInn-Special');
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final tag = decoded['tag_name'] as String?;
      if (tag == null || tag.isEmpty) {
        return null;
      }
      await _setLastChecked(DateTime.now());
      return tag;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 比较两个版本字符串（支持 "v1.2.3" / "1.2.3-special.1" 形式）。
  /// 遵循 semver：pre-release < 正式版（同主版本时）。
  /// 返回 1 表示 [remote] 更新，-1 表示 [local] 更新，0 表示相同。
  static int compareVersions(String local, String remote) {
    final a = _parseVersion(local);
    final b = _parseVersion(remote);
    if (a == null || b == null) {
      // 无法解析时按字符串比较兜底
      return remote.compareTo(local) > 0 ? 1 : (remote == local ? 0 : -1);
    }
    for (var i = 0; i < 3; i++) {
      if (a.numbers[i] != b.numbers[i]) {
        return b.numbers[i] > a.numbers[i] ? 1 : -1;
      }
    }
    // 主版本相同：比较 pre-release（semver：有 pre 的版本 < 正式版）
    final aPre = a.preRelease;
    final bPre = b.preRelease;
    if (aPre == null && bPre == null) {
      return 0;
    }
    if (aPre == null) {
      return -1; // 本地正式版 > 远端 pre-release
    }
    if (bPre == null) {
      return 1; // 远端正式版 > 本地 pre-release
    }
    final aNumber = int.tryParse(aPre);
    final bNumber = int.tryParse(bPre);
    if (aNumber != null && bNumber != null) {
      if (aNumber != bNumber) {
        return bNumber > aNumber ? 1 : -1;
      }
      return 0;
    }
    if (aNumber != null) {
      return -1; // 本地数字 pre（special.N）> 远端标识符 pre（alpha/beta）
    }
    if (bNumber != null) {
      return 1; // 远端数字 pre > 本地标识符 pre
    }
    final comparison = bPre.compareTo(aPre);
    return comparison > 0 ? 1 : (comparison < 0 ? -1 : 0);
  }

  static _ParsedVersion? _parseVersion(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    // 去掉 +build 段
    final plusIndex = text.indexOf('+');
    if (plusIndex >= 0) {
      text = text.substring(0, plusIndex);
    }
    final parts = text.split('-');
    final core = parts.first.split('.');
    if (core.length < 3) {
      return null;
    }
    final numbers = <int>[];
    for (final part in core.take(3)) {
      final parsed = int.tryParse(part.trim());
      if (parsed == null) {
        return null;
      }
      numbers.add(parsed);
    }
    String? preRelease;
    if (parts.length > 1) {
      // 形如 "special.2" → 取最后一段（数字或标识符）
      preRelease = parts[1].split('.').last;
    }
    return _ParsedVersion(numbers, preRelease);
  }
}

class _ParsedVersion {
  const _ParsedVersion(this.numbers, this.preRelease);

  final List<int> numbers;

  /// pre-release 标识：数字时如 "2"、标识符时如 "alpha"；null 表示正式版。
  final String? preRelease;
}
