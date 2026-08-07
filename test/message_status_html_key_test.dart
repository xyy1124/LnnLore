
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/services/chat_service.dart';

void main() {
  test('messageStatusHtmlKey 按消息 id 关联', () {
    expect(
      ChatService.messageStatusHtmlKey('msg-1'),
      '__msg_status_html__:msg-1',
    );
  });
}
