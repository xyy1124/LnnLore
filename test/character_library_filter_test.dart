import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/models/character_card.dart';
import 'package:pocket_inn/pages/char_list_page.dart';

void main() {
  final summaries = <CharacterSummary>[
    CharacterSummary(
      id: 'a',
      name: '夜无央',
      description: '魔尊与正道女修的剧情',
      thumbnailPath: '',
      updatedAt: DateTime(2026, 8, 16),
    ),
    CharacterSummary(
      id: 'b',
      name: '苏蕴泠',
      description: '青云宗掌门与弟子',
      thumbnailPath: '',
      updatedAt: DateTime(2026, 8, 17),
    ),
    CharacterSummary(
      id: 'c',
      name: '蜜欧拉',
      description: '女神与随机 NPC',
      thumbnailPath: '',
      updatedAt: DateTime(2026, 8, 15),
    ),
  ];

  group('character library filter and sorting', () {
    test('searches both name and summary locally', () {
      final byName = filterAndSortCharacterSummaries(
        summaries,
        query: '苏蕴',
        sort: CharacterLibrarySort.updatedAt,
      );
      final byDescription = filterAndSortCharacterSummaries(
        summaries,
        query: '随机',
        sort: CharacterLibrarySort.updatedAt,
      );

      expect(byName.map((item) => item.id), ['b']);
      expect(byDescription.map((item) => item.id), ['c']);
    });

    test('recent sorting keeps newest first', () {
      final result = filterAndSortCharacterSummaries(
        summaries,
        query: '',
        sort: CharacterLibrarySort.updatedAt,
      );

      expect(result.map((item) => item.id), ['b', 'a', 'c']);
    });

    test('name sorting is deterministic and does not mutate source list', () {
      final result = filterAndSortCharacterSummaries(
        summaries,
        query: '',
        sort: CharacterLibrarySort.name,
      );

      expect(result.map((item) => item.name), ['夜无央', '苏蕴泠', '蜜欧拉']);
      expect(summaries.map((item) => item.id), ['a', 'b', 'c']);
    });

    test('blank query returns all characters', () {
      final result = filterAndSortCharacterSummaries(
        summaries,
        query: '   ',
        sort: CharacterLibrarySort.updatedAt,
      );

      expect(result, hasLength(3));
    });
  });
}
