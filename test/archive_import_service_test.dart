import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/archive_import_service.dart';

import 'package:image/image.dart' as img;

/// 1x1 透明 PNG（真实有效的 png 字节）。
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  group('ArchiveImportService', () {
    test('zip 解压返回内部文件列表', () async {
      // 构造 zip
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('角色A.json', utf8.encode('{}')))
        ..addFile(ArchiveFile.bytes('角色A.png', [1, 2, 3]))
        ..addFile(ArchiveFile.bytes('世界书.json', utf8.encode('{}')));
      final zipBytes = ZipEncoder().encode(archive);

      final entries = await ArchiveImportService.instance.expandArchives([
        (name: 'cards.zip', bytes: Uint8List.fromList(zipBytes!)),
      ]);

      expect(entries.length, 3);
      expect(entries.map((e) => e.name), containsAll(['角色A.json', '角色A.png', '世界书.json']));
    });

    test('普通文件原样保留', () async {
      final entries = await ArchiveImportService.instance.expandArchives([
        (name: '直接.json', bytes: Uint8List.fromList(utf8.encode('{}'))),
      ]);
      expect(entries.length, 1);
      expect(entries.first.name, '直接.json');
    });

    test('损坏的 zip 静默跳过', () async {
      final entries = await ArchiveImportService.instance.expandArchives([
        (name: 'bad.zip', bytes: Uint8List.fromList([1, 2, 3, 4])),
      ]);
      expect(entries, isEmpty);
    });

    test('zip 内路径穿越项被过滤', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('../evil.json', utf8.encode('{}')))
        ..addFile(ArchiveFile.bytes('正常.json', utf8.encode('{}')));
      final zipBytes = ZipEncoder().encode(archive);

      final entries = await ArchiveImportService.instance.expandArchives([
        (name: 'x.zip', bytes: Uint8List.fromList(zipBytes!)),
      ]);
      expect(entries.length, 1);
      expect(entries.first.name, '正常.json');
    });

    test('扩展名与 basename 提取', () {
      expect(ArchiveImportService.extensionOf('a/b/c.JSON'), 'json');
      expect(ArchiveImportService.extensionOf('noext'), '');
      expect(
        ArchiveImportService.basenameWithoutExtension('角色A.json'),
        '角色A',
      );
      expect(
        ArchiveImportService.basenameWithoutExtension('x/y/世界书.json'),
        '世界书',
      );
    });
  });

  group('ArchiveImportService.hasSafePngDimensions', () {
    test('支持放宽参数（编辑页立绘场景）', () {
      // 构造 IHDR 声明 9000x9000 的 png 头（超过默认 8192 预算）
      final bytes = Uint8List(24);
      bytes.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      bytes[12] = 0x49; // I
      bytes[13] = 0x48; // H
      bytes[14] = 0x44; // D
      bytes[15] = 0x52; // R
      bytes[16] = 0;
      bytes[17] = 0;
      bytes[18] = 0x23;
      bytes[19] = 0x28; // 9000
      bytes[20] = 0;
      bytes[21] = 0;
      bytes[22] = 0x23;
      bytes[23] = 0x28; // 9000
      expect(ArchiveImportService.hasSafePngDimensions(bytes), isFalse);
      expect(
        ArchiveImportService.hasSafePngDimensions(
          bytes,
          maxDimension: ArchiveImportService.maxPngDimensionPortrait,
          maxPixels: ArchiveImportService.maxPngPixelsPortrait,
        ),
        isTrue,
      );
    });

    test('超限大图可降采样为安全尺寸', () {
      // 9000x5000 = 4500 万像素 > 默认 3355 万预算
      final huge = img.Image(width: 9000, height: 5000);
      img.fill(huge, color: img.ColorRgb8(100, 100, 100));
      final hugeBytes = img.encodePng(huge);
      expect(ArchiveImportService.hasSafePngDimensions(hugeBytes), isFalse);
      expect(
        ArchiveImportService.hasSafePngDimensions(
          hugeBytes,
          maxDimension: ArchiveImportService.maxPngDimensionPortrait,
          maxPixels: ArchiveImportService.maxPngPixelsPortrait,
        ),
        isTrue,
      );
      // 降采样到 2048 宽后通过严格预算（与 _prepareImageAssets 逻辑一致）
      final decoded = img.decodeImage(hugeBytes)!;
      final resized = img.copyResize(decoded, width: 2048);
      final resizedBytes = img.encodePng(resized, level: 6);
      expect(
        ArchiveImportService.hasSafePngDimensions(resizedBytes),
        isTrue,
      );
    });

    test('正常 1x1 png 通过', () {
      final bytes = Uint8List.fromList(
        base64Decode(_tinyPngBase64),
      );
      expect(ArchiveImportService.hasSafePngDimensions(bytes), isTrue);
    });

    test('超宽 png 被拒绝', () {
      // 伪造 IHDR：宽 65535 高 65535
      final bytes = Uint8List(24);
      bytes[0] = 0x89;
      bytes[1] = 0x50; // PNG 签名
      bytes[2] = 0x4E;
      bytes[3] = 0x47;
      bytes[12] = 0x49; // I
      bytes[13] = 0x48; // H
      bytes[14] = 0x44; // D
      bytes[15] = 0x52; // R
      bytes[16] = 0x00;
      bytes[17] = 0xFF;
      bytes[18] = 0xFF;
      bytes[19] = 0xFF;
      bytes[20] = 0x00;
      bytes[21] = 0xFF;
      bytes[22] = 0xFF;
      bytes[23] = 0xFF;
      expect(ArchiveImportService.hasSafePngDimensions(bytes), isFalse);
    });

    test('非 png 字节被拒绝', () {
      expect(
        ArchiveImportService.hasSafePngDimensions(
          Uint8List.fromList([1, 2, 3]),
        ),
        isFalse,
      );
    });
  });
}
