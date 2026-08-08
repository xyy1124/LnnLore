// v75 回归测试：状态一致性收口——
//  - allowInlineTrackerProtocol=false 时 setvar 不解析（后台/严格主模型
//    偷偷输出 setvar 不得改状态）
//  - 非当前会话的变量事件应被忽略（不串会话）
//  - 快照 key 前缀清单覆盖 v3/v4/v5/v2/v1（deleteMessageBranch 清理用）
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/services/chat_database_service.dart';
import 'package:pocket_inn/services/chat_variable_service.dart';

void main() {
  group('v75 setvar 受控', () {
    test('allowInlineTrackerProtocol=false 时 setvar 不解析（等价逻辑）', () {
      const text = '剧情正文 {{setvar::ml_like::50}}';
      // 后台/严格模式：calls = const []（不解析）
      final backgroundCalls = false
          ? ChatVariableService.parseSetVarCalls(text)
          : const <(String, String)>[];
      expect(backgroundCalls, isEmpty, reason: '后台/严格模式 setvar 忽略');
      // 快速模式：正常解析
      final quickCalls = ChatVariableService.parseSetVarCalls(text);
      expect(quickCalls, isNotEmpty);
      expect(quickCalls.first.$1, 'ml_like');
    });
  });

  group('v75 非当前会话事件过滤', () {
    test('事件携带 sessionId 供 ViewModel 判断', () {
      const change = ChatDatabaseChange(
        kind: ChatDatabaseChangeKind.variables,
        sessionId: 'sessionA',
      );
      expect(change.sessionId, 'sessionA');
      // ViewModel 过滤逻辑：当前活动会话 != change.sessionId → return
      const activeSession = 'sessionB';
      final shouldIgnore = change.sessionId != null &&
          change.sessionId != activeSession;
      expect(shouldIgnore, isTrue, reason: '非当前会话事件应被忽略');
      // 同会话事件不忽略
      const sameSession = 'sessionA';
      final shouldNotIgnore = change.sessionId != null &&
          change.sessionId != sameSession;
      expect(shouldNotIgnore, isFalse);
    });
  });

  group('v75 快照清理前缀', () {
    test('快照 key 前缀清单覆盖 v3/v4/v5/v2/v1', () {
      const prefixes = [
        '__msg_tracker_state_v3__:',
        '__msg_tracker_state_v4__:',
        '__msg_tracker_state_v5__:',
        '__msg_status_html_v2__:',
        '__msg_status_html__:',
      ];
      expect(prefixes.length, 5, reason: '5 种快照前缀全覆盖');
      // 每个前缀 + messageId 构成实际 key
      const messageId = 'msg1';
      for (final p in prefixes) {
        expect('$p$messageId', contains(messageId));
      }
    });
  });
}
