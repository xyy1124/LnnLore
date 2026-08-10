/// v81：App 更新信息——GitHub release 中的 .apk asset 摘要。
///
/// 由 [VersionCheckService.fetchLatestUpdate] 从 GitHub
/// `releases/latest` 响应构造，供应用内自更新（下载 + 安装）使用。
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.tagName,
    required this.downloadUrl,
    this.sizeBytes = 0,
    this.body = '',
    this.publishedAt,
  });

  /// 最新 release 的 tag（如 "v1.4.0-special.80"）。
  final String tagName;

  /// .apk asset 的浏览器直链（GitHub 域名，下载时可走镜像前缀）。
  final String downloadUrl;

  /// .apk 文件大小（字节）。
  final int sizeBytes;

  /// release 更新说明（Markdown 正文）。
  final String body;

  /// release 发布时间。
  final DateTime? publishedAt;

  /// 从 GitHub `releases/latest` 响应构造；无 tag 或找不到 .apk asset
  /// 时返回 null。
  static AppUpdateInfo? fromLatestReleaseJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) {
      return null;
    }
    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) {
          continue;
        }
        final name = asset['name'] as String? ?? '';
        if (!name.toLowerCase().endsWith('.apk')) {
          continue;
        }
        final url = asset['browser_download_url'] as String?;
        if (url == null || url.isEmpty) {
          continue;
        }
        final size = asset['size'];
        return AppUpdateInfo(
          tagName: tagName,
          downloadUrl: url,
          sizeBytes: size is num ? size.toInt() : 0,
          body: json['body'] as String? ?? '',
          publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
        );
      }
    }
    return null; // release 存在但无 .apk asset
  }

  /// 人类可读的文件大小（如 "72.5 MB"）。
  String get sizeText {
    if (sizeBytes <= 0) {
      return '';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$sizeBytes B';
  }
}
