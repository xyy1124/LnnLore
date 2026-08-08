// v68 回归测试：三档模式失效与跳底回归修复——
//  - 协议示例是合法 JSON（模型照抄也能解析）
//  - TrackerUpdateMode 持久化（AppSettingsService 读写）
//  - 数据库通知分类（variables/choices 不再触发消息树重载）
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/data/app_settings.dart';
import 'package:pocket_inn/services/chat_database_service.dart';
import 'package:pocket_inn/services/tracker_runtime.dart';

void main() {
  group('v68 协议合法 JSON', () {
    test('kTrackerProtocolSuffix 中的示例可被 jsonDecode 解析', () {
      final suffix = TrackerRuntime.kTrackerProtocolSuffix;
      // 提取 ```json ... ``` 块
      final match = RegExp(r'```json\n([\s\S]*?)\n```').firstMatch(suffix);
      expect(match, isNotNull, reason: '协议应包含 JSON 示例块');
      final jsonText = match!.group(1)!;
      // 示例必须能解析——模型照抄也不会因中文占位值失败
      final decoded = jsonDecode(jsonText);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['reply'], '剧情正文');
      expect(decoded['patch'], isA<Map<String, dynamic>>());
      expect(decoded['narrative'], isA<Map<String, dynamic>>());
      expect(decoded['consequence'], isA<Map<String, dynamic>>());
    });

    test('协议不再含非法占位值（字段key/数值变化作为 JSON 值）', () {
      final suffix = TrackerRuntime.kTrackerProtocolSuffix;
      // "数值变化" 只允许出现在说明文字（"增加 2"），不允许在 JSON 示例内
      final jsonBlock = RegExp(r'```json\n([\s\S]*?)\n```')
          .firstMatch(suffix)!
          .group(1)!;
      expect(jsonBlock.contains('数值变化'), isFalse);
      expect(jsonBlock.contains('字段key":'), isFalse);
    });

    test('协议说明文字保留 key 映射指导', () {
      final suffix = TrackerRuntime.kTrackerProtocolSuffix;
      expect(suffix, contains('number 字段增减写入 add'));
      expect(suffix, contains('string 字段变化写入 set'));
    });
  });

  group('v68 TrackerUpdateMode 持久化', () {
    test('AppSettings 默认 quick 且枚举三档', () {
      expect(appSettingsNotifier.value.trackerUpdateMode,
          TrackerUpdateMode.quick);
      expect(TrackerUpdateMode.values.length, 3);
    });

    test('copyWith 可切换且可恢复', () {
      final switched = appSettingsNotifier.value.copyWith(
        trackerUpdateMode: TrackerUpdateMode.strict,
      );
      expect(switched.trackerUpdateMode, TrackerUpdateMode.strict);
      final restored = switched.copyWith(
        trackerUpdateMode: TrackerUpdateMode.background,
      );
      expect(restored.trackerUpdateMode, TrackerUpdateMode.background);
    });
  });

  group('v68 数据库通知分类', () {
    test('ChatDatabaseChange 携带 kind/sessionId/messageId', () {
      const change = ChatDatabaseChange(
        kind: ChatDatabaseChangeKind.variables,
        sessionId: 's1',
      );
      expect(change.kind, ChatDatabaseChangeKind.variables);
      expect(change.sessionId, 's1');
      expect(change.messageId, isNull);

      const choicesChange = ChatDatabaseChange(
        kind: ChatDatabaseChangeKind.choices,
        messageId: 'm1',
      );
      expect(choicesChange.kind, ChatDatabaseChangeKind.choices);
      expect(choicesChange.messageId, 'm1');
    });

    test('notifyDataChanged 发出带类型事件', () {
      final service = ChatDatabaseService.instance;
      ChatDatabaseChange? received;
      void listener() {
        received = service.changeNotifier.value;
      }

      service.changeNotifier.addListener(listener);
      service.notifyDataChanged(
        kind: ChatDatabaseChangeKind.variables,
        sessionId: 's1',
      );
      service.changeNotifier.removeListener(listener);

      expect(received, isNotNull);
      expect(received!.kind, ChatDatabaseChangeKind.variables);
      expect(received!.sessionId, 's1');
    });

    test('默认 kind 为 messages（消息树变化）', () {
      final service = ChatDatabaseService.instance;
      ChatDatabaseChange? received;
      void listener() {
        received = service.changeNotifier.value;
      }

      service.changeNotifier.addListener(listener);
      service.notifyDataChanged();
      service.changeNotifier.removeListener(listener);

      expect(received!.kind, ChatDatabaseChangeKind.messages);
    });
  });
}
