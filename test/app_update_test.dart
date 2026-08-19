// v81 回归测试：应用内自更新——
//  - AppUpdateInfo.fromLatestReleaseJson（GitHub releases/latest 响应解析）
//  - UpdateDownloadService.candidateUrls（镜像回退链构造）
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/app_update_info.dart';
import 'package:pocket_inn/services/update_download_service.dart';

void main() {
  group('AppUpdateInfo.fromLatestReleaseJson', () {
    test('含 .apk asset 的响应正确提取全部字段', () {
      final info = AppUpdateInfo.fromLatestReleaseJson({
        'tag_name': 'v1.4.0-special.80',
        'body': '## 更新内容\n- 修复若干问题',
        'published_at': '2026-08-10T12:00:00Z',
        'assets': [
          {
            'name': 'pocketinn-1.4.0-special.80.apk',
            'browser_download_url':
                'https://github.com/xyy1124/LnnLore/releases/download/v1.4.0-special.80/pocketinn-1.4.0-special.80.apk',
            'size': 75971541,
          },
          {
            'name': 'source.zip',
            'browser_download_url': 'https://example.com/source.zip',
            'size': 100,
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.tagName, 'v1.4.0-special.80');
      expect(info.downloadUrl, contains('pocketinn-1.4.0-special.80.apk'));
      expect(info.sizeBytes, 75971541);
      expect(info.body, contains('修复若干问题'));
      expect(info.publishedAt, isNotNull);
      expect(info.sizeText, '72.5 MB');
    });

    test('无 tag 返回 null', () {
      final info = AppUpdateInfo.fromLatestReleaseJson({
        'assets': [
          {'name': 'a.apk', 'browser_download_url': 'https://x/a.apk'},
        ],
      });
      expect(info, isNull);
    });

    test('有 tag 但无 .apk asset 返回 null', () {
      final info = AppUpdateInfo.fromLatestReleaseJson({
        'tag_name': 'v1.4.0-special.80',
        'assets': [
          {'name': 'source.zip', 'browser_download_url': 'https://x/s.zip'},
        ],
      });
      expect(info, isNull);
    });

    test('无 assets 字段（旧版 release）返回 null', () {
      final info = AppUpdateInfo.fromLatestReleaseJson({
        'tag_name': 'v1.4.0-special.80',
      });
      expect(info, isNull);
    });
  });

  group('UpdateDownloadService download integrity', () {
    test('GitHub asset size is available for integrity verification', () {
      const update = AppUpdateInfo(
        tagName: 'v1.4.0-special.100',
        downloadUrl: 'https://example.com/app.apk',
        sizeBytes: 1024,
      );
      expect(update.sizeBytes, 1024);
      expect(update.sizeText, '1 KB');
    });
  });

  group('UpdateDownloadService.candidateUrls', () {
    test('直连在前，三个镜像依次在后', () {
      const url =
          'https://github.com/xyy1124/LnnLore/releases/download/v1.4.0-special.80/pocketinn-1.4.0-special.80.apk';
      final candidates = UpdateDownloadService.candidateUrls(url);
      expect(candidates, hasLength(4));
      expect(candidates[0], url);
      expect(candidates[1], 'https://ghfast.top/$url');
      expect(candidates[2], 'https://ghproxy.net/$url');
      expect(candidates[3], 'https://gh-proxy.com/$url');
    });
  });
}
