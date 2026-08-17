import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/pages/chat/widgets/entity_status_panel.dart';

void main() {
  group('entity panel gradient foreground', () {
    test('dark gradient selects light foreground', () {
      expect(
        gradientForegroundForColors(
          '#0d0a14',
          '#1b1226',
          fallback: Colors.black,
        ),
        const Color(0xFFF0F4F2),
      );
    });

    test('light gradient selects dark foreground', () {
      expect(
        gradientForegroundForColors(
          '#f7f1e3',
          '#e7dbc1',
          fallback: Colors.white,
        ),
        const Color(0xFF1F2522),
      );
    });

    test('invalid declared gradient colors retain a readable fallback path', () {
      expect(
        gradientForegroundForColors(
          'not-a-color',
          '',
          fallback: Colors.black,
        ),
        const Color(0xFFF0F4F2),
      );
    });
  });
}
