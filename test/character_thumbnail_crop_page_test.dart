import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pocket_inn/pages/character_thumbnail_crop_page.dart';

void main() {
  group('CharacterThumbnailCropPage gestures', () {
    late File image;
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('crop_test_');
      image = File('${tempDir.path}/portrait.png');
      final source = img.Image(width: 1600, height: 800);
      img.fill(source, color: img.ColorRgb8(30, 60, 90));
      await image.writeAsBytes(Uint8List.fromList(img.encodePng(source)));
    });

    tearDownAll(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('single-finger drag moves the focus (pan is not stuck)',
        (tester) async {
      ThumbnailCropValue? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    saved = await Navigator.of(context).push<ThumbnailCropValue>(
                      MaterialPageRoute(
                        builder: (_) => CharacterThumbnailCropPage(
                          imagePath: image.path,
                          initialFocusX: 0.5,
                          initialFocusY: 0.5,
                          initialScale: 1.0,
                          characterName: '测试',
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Drag left across the preview frame. ScaleGestureRecognizer reports
      // cumulative focal offset, which must move focusX away from 0.5.
      final preview = find.byType(GestureDetector).first;
      await tester.drag(preview, const Offset(-120, 0));
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saved, isNotNull);
      // Dragging the image left shows the right side of the source, so the
      // focal point moves right (focusX > 0.5); this confirms pan works.
      expect(saved!.focusX, greaterThan(0.5));
      expect(saved!.focusY, closeTo(0.5, 0.05));
    });
  });
}
