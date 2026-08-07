
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/chat_service.dart';

void main() {
  test('messageStatusHtmlKey 按消息 id 关联（v3 结构化状态快照 key）', () {
    expect(
      ChatService.messageStatusHtmlKey('msg-1'),
      '__msg_tracker_state_v3__:msg-1',
    );
  });

  test('v3 快照 key 与旧 v2/v1 HTML 快照 key 不同（旧数据被忽略）', () {
    final v3 = ChatService.messageStatusHtmlKey('msg-1');
    const v2 = '__msg_status_html_v2__:msg-1';
    const v1 = '__msg_status_html__:msg-1';
    expect(v3, isNot(equals(v2)));
    expect(v3, isNot(equals(v1)));
    expect(v3, startsWith('__msg_tracker_state_v3__:'));
  });
}
