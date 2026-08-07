
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/chat_service.dart';

void main() {
  test('messageStatusHtmlKey 按消息 id 关联（v2 规范快照 key）', () {
    expect(
      ChatService.messageStatusHtmlKey('msg-1'),
      '__msg_status_html_v2__:msg-1',
    );
  });

  test('v2 快照 key 与旧 v1 模型 HTML key 不同（v1 数据被忽略）', () {
    final v2 = ChatService.messageStatusHtmlKey('msg-1');
    const v1 = '__msg_status_html__:msg-1';
    expect(v2, isNot(equals(v1)));
    // v2 使用带版本标记的命名空间
    expect(v2, startsWith('__msg_status_html_v2__:'));
  });
}
