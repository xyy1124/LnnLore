import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pocket_inn/models/character_card.dart';
import 'package:pocket_inn/services/character_service.dart';

void main() {
  group('character thumbnail crop model', () {
    test('old local record defaults crop to centered 1x', () {
      final record = CharacterCardRecord.fromJson({
        'id': 'legacy',
        'cardJson': {
          'data': {'name': '旧角色'},
        },
        'originalImagePath': 'characters/images/legacy.png',
        'thumbnailPath': 'characters/thumbnails/legacy.png',
      });

      expect(record.thumbnailFocusX, 0.5);
      expect(record.thumbnailFocusY, 0.5);
      expect(record.thumbnailScale, 1.0);
    });

    test('crop metadata is local record data, never exported card JSON', () {
      const record = CharacterCardRecord(
        id: 'local-crop',
        cardJson: {
          'data': {'name': '测试角色'},
        },
        originalImagePath: 'characters/images/local-crop.png',
        thumbnailPath: 'characters/thumbnails/local-crop.png',
        thumbnailFocusX: 0.2,
        thumbnailFocusY: 0.8,
        thumbnailScale: 2.0,
      );

      final exported = jsonDecode(record.exportJsonString()) as Map<String, dynamic>;
      expect(exported.containsKey('thumbnailFocusX'), isFalse);
      expect(exported.containsKey('thumbnailFocusY'), isFalse);
      expect(exported.containsKey('thumbnailScale'), isFalse);
      expect((exported['data'] as Map)['name'], '测试角色');
    });
  });

  group('character thumbnail crop rendering', () {
    test('different focus positions produce different 4:3 thumbnails', () {
      // A 2:1 source leaves horizontal crop room for the 4:3 output.
      final source = img.Image(width: 1600, height: 800);
      img.fill(source, color: img.ColorRgb8(0, 0, 255));
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 799,
        y2: 799,
        color: img.ColorRgb8(255, 0, 0),
      );

      final left = CharacterService.buildThumbnailForCrop(
        source,
        focusX: 0,
        focusY: 0.5,
      );
      final right = CharacterService.buildThumbnailForCrop(
        source,
        focusX: 1,
        focusY: 0.5,
      );

      expect(left.width, 1024);
      expect(left.height, 768);
      expect(right.width, 1024);
      expect(right.height, 768);
      expect(left.getPixel(512, 384).r, greaterThan(left.getPixel(512, 384).b));
      expect(right.getPixel(512, 384).b, greaterThan(right.getPixel(512, 384).r));
    });

    test('out-of-range crop values are clamped to a valid output', () {
      final source = img.Image(width: 400, height: 300);
      img.fill(source, color: img.ColorRgb8(20, 40, 60));

      final thumbnail = CharacterService.buildThumbnailForCrop(
        source,
        focusX: -5,
        focusY: 9,
        scale: 99,
      );

      expect(thumbnail.width, 1024);
      expect(thumbnail.height, 768);
    });
  });
}
