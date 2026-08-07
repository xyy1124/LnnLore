import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/character_intro_service.dart';

void main() {
  group('CharacterIntroService.truncateText', () {
    test('短文本原样返回', () {
      expect(CharacterIntroService.truncateText('短文本'), '短文本');
    });

    test('超长文本截断并标注', () {
      final long = 'x' * 5000;
      final result = CharacterIntroService.truncateText(long);
      expect(result, contains('内容过长已截断'));
      expect(result.length, lessThan(long.length));
    });

    test('自定义 limit 生效', () {
      final result = CharacterIntroService.truncateText('abcdefghij', limit: 5);
      expect(result, startsWith('abcde'));
      expect(result, contains('截断'));
    });
  });

  group('CharacterIntroService.maxPromptBudget', () {
    test('预算为 60000 字符', () {
      expect(CharacterIntroService.maxPromptBudget, 60000);
    });
  });
}
