import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/errors.dart';

/// v81：下载被用户取消。
class UpdateDownloadCancelledException implements Exception {
  const UpdateDownloadCancelledException();
}

/// v81：应用更新下载服务——从 GitHub Release 下载 APK，带国内镜像
/// 回退链（GitHub 直连在国内不稳定，逐个尝试加速镜像直到成功）。
class UpdateDownloadService {
  UpdateDownloadService._();

  static final UpdateDownloadService instance = UpdateDownloadService._();

  /// 下载镜像回退链：原 URL 直连失败后依次尝试镜像前缀。
  /// 镜像地址格式：{mirror}/{原 URL}（保留协议与路径）。
  static const List<String> mirrorPrefixes = [
    'https://ghfast.top',
    'https://ghproxy.net',
    'https://gh-proxy.com',
  ];

  /// 构造候选下载地址列表：[原 URL, 镜像1/URL, 镜像2/URL, ...]。
  /// 纯函数，便于测试。
  static List<String> candidateUrls(String originalUrl) {
    return [
      originalUrl,
      for (final mirror in mirrorPrefixes) '$mirror/$originalUrl',
    ];
  }

  /// 下载 APK 到应用支持目录 updates/ 下（App 私有目录，安装时由原生
  /// PackageInstaller 读取）。按镜像回退链逐个尝试；全部失败抛
  /// [NetworkException]。返回保存的文件路径。
  /// [onProgress] 回调（已下载字节, 总字节；总字节未知时为 0）。
  /// [isCancelled] 每次回调询问是否取消；true 时抛
  /// [UpdateDownloadCancelledException]（不重试镜像）。
  Future<String> downloadApk({
    required String url,
    void Function(int received, int total)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final updatesDir = Directory('${dir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    final targetPath = '${updatesDir.path}/${_apkFileName(url)}';

    String? lastError;
    for (final candidate in candidateUrls(url)) {
      try {
        await _downloadSingle(
          candidate,
          targetPath,
          onProgress,
          isCancelled,
        );
        return targetPath;
      } on UpdateDownloadCancelledException {
        rethrow; // 用户取消：不尝试镜像
      } on Object catch (e) {
        lastError = e.toString();
      }
    }
    // 全部失败：清理半成品
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    throw NetworkException(
      'APK 下载失败（直连与镜像均不可用）'
      '${lastError == null ? '' : '：$lastError'}',
    );
  }

  Future<void> _downloadSingle(
    String url,
    String targetPath,
    void Function(int received, int total)? onProgress,
    Future<bool> Function()? isCancelled,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final file = File(targetPath);
    final sink = file.openWrite();
    var received = 0;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'LnnLore-Updater');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final total = response.contentLength;
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        if (isCancelled != null && await isCancelled()) {
          throw const UpdateDownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } on Object {
      await sink.close();
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// 从 URL 提取文件名（如 pocketinn-1.4.0-special.80.apk）；
  /// 提取失败用时间戳命名。
  static String _apkFileName(String url) {
    final path = Uri.parse(url).pathSegments;
    if (path.isNotEmpty && path.last.endsWith('.apk')) {
      return path.last;
    }
    return 'lnnlore-update-${DateTime.now().millisecondsSinceEpoch}.apk';
  }
}
