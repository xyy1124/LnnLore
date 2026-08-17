import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/data/app_settings.dart';
import 'package:pocket_inn/theme/chat_reading_theme.dart';

void main() {
  group('ChatReadingTheme', () {
    for (final preset in AppThemePreset.values) {
      for (final brightness in Brightness.values) {
        test('${preset.name} ${brightness.name} builds distinct reading layers',
            () {
          final scheme = ColorScheme.fromSeed(
            seedColor: preset.seedColor,
            brightness: brightness,
          );
          final theme = ChatReadingTheme.fromColorScheme(scheme);

          expect(theme.canvas, isNot(theme.composerSurface));
          expect(theme.userBubble, isNot(theme.canvas));
          expect(theme.sidebarSurface, isNot(theme.sidebarSelectedSurface));
          expect(theme.assistantText.computeLuminance(), isNot(0));
          expect(theme.composerText.computeLuminance(), isNot(0));
        });
      }
    }

    test('dark reading theme has readable assistant text over canvas', () {
      final theme = ChatReadingTheme.fromColorScheme(
        ColorScheme.fromSeed(
          seedColor: AppThemePreset.ocean.seedColor,
          brightness: Brightness.dark,
        ),
      );
      final ratio = _contrastRatio(theme.assistantText, theme.canvas);

      expect(ratio, greaterThan(7));
    });

    test('light reading theme has readable assistant text over canvas', () {
      final theme = ChatReadingTheme.fromColorScheme(
        ColorScheme.fromSeed(
          seedColor: AppThemePreset.ocean.seedColor,
          brightness: Brightness.light,
        ),
      );
      final ratio = _contrastRatio(theme.assistantText, theme.canvas);

      expect(ratio, greaterThan(7));
    });
  });
}

double _contrastRatio(Color a, Color b) {
  final light = a.computeLuminance();
  final dark = b.computeLuminance();
  final high = light > dark ? light : dark;
  final low = light > dark ? dark : light;
  return (high + 0.05) / (low + 0.05);
}
