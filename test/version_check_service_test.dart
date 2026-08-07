import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/version_check_service.dart';

void main() {
  group('VersionCheckService.compareVersions', () {
    test('相同版本返回 0', () {
      expect(
        VersionCheckService.compareVersions('1.4.0-special.1', 'v1.4.0-special.1'),
        0,
      );
    });

    test('远端 pre-release 数字更大返回 1', () {
      expect(
        VersionCheckService.compareVersions('1.4.0-special.1', 'v1.4.0-special.2'),
        1,
      );
    });

    test('远端主版本更大返回 1', () {
      expect(
        VersionCheckService.compareVersions('1.4.0-special.1', 'v1.5.0-special.1'),
        1,
      );
    });

    test('本地更新返回 -1', () {
      expect(
        VersionCheckService.compareVersions('1.4.0-special.2', 'v1.4.0-special.1'),
        -1,
      );
    });

    test('无 pre-release 的版本可比较', () {
      expect(
        VersionCheckService.compareVersions('1.3.2', 'v1.4.0'),
        1,
      );
      expect(
        VersionCheckService.compareVersions('1.4.0', 'v1.4.0'),
        0,
      );
    });

    test('带 +build 段不影响比较', () {
      expect(
        VersionCheckService.compareVersions('1.4.0-special.1+56', 'v1.4.0-special.1'),
        0,
      );
    });

    test('pre-release < 正式版（semver 交叉方向）', () {
      // 本地 special，远端正式版 → 提示更新
      expect(
        VersionCheckService.compareVersions('1.4.0-special.1', 'v1.4.0'),
        1,
      );
      // 本地正式版，远端 special → 本地更新
      expect(
        VersionCheckService.compareVersions('1.4.0', 'v1.4.0-special.2'),
        -1,
      );
    });

    test('无数字 pre 标识符按字典序比较', () {
      expect(
        VersionCheckService.compareVersions('1.4.0-alpha', 'v1.4.0-beta'),
        1,
      );
      expect(
        VersionCheckService.compareVersions('1.4.0-alpha', 'v1.4.0-alpha'),
        0,
      );
      // 数字 pre（special.N）优先于标识符 pre（alpha/beta）
      expect(
        VersionCheckService.compareVersions('1.4.0-special.1', 'v1.4.0-alpha'),
        -1,
      );
      expect(
        VersionCheckService.compareVersions('1.4.0-alpha', 'v1.4.0-special.1'),
        1,
      );
    });

    test('无法解析的版本按字符串兜底', () {
      expect(
        VersionCheckService.compareVersions('unknown', 'v1.4.0'),
        isNot(0),
      );
    });
  });

  group('VersionCheckService.isUpstreamUpdateAvailable（上游锚点）', () {
    test('锚点为 fork 时的上游版本 1.3.2', () {
      expect(VersionCheckService.baselineUpstreamVersion, '1.3.2');
    });

    test('上游发布高于 1.3.2 的版本即提示', () {
      expect(
        VersionCheckService.isUpstreamUpdateAvailable('v1.3.3'),
        isTrue,
      );
      expect(
        VersionCheckService.isUpstreamUpdateAvailable('v1.4.0'),
        isTrue,
      );
    });

    test('上游等于或低于锚点不提示', () {
      expect(
        VersionCheckService.isUpstreamUpdateAvailable('v1.3.2'),
        isFalse,
      );
      expect(
        VersionCheckService.isUpstreamUpdateAvailable('v1.3.1'),
        isFalse,
      );
    });

    test('本地特别版号与上游提示互不影响', () {
      // 本地 1.4.0-special.1 高于上游 1.3.3，但上游更新仍应提示
      expect(
        VersionCheckService.compareVersions(
          '1.4.0-special.1',
          'v1.3.3',
        ),
        -1,
      );
      expect(
        VersionCheckService.isUpstreamUpdateAvailable('v1.3.3'),
        isTrue,
      );
    });
  });
}
