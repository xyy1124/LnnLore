import '../models/tracker_config.dart';
import 'chat_variable_service.dart';
import 'tracker_runtime.dart';

class ChatOpeningMessages {
  const ChatOpeningMessages({
    required this.messages,
    this.openingName,
  });

  final List<String> messages;

  /// v103：本会话抽中的开场原身份姓名（写入状态栏 Tab）。
  final String? openingName;
}

class ChatOpeningMessageBuilder {
  ChatOpeningMessageBuilder._();

  static List<String> build({
    required Map<String, dynamic> characterCardData,
    required String characterName,
    required String userName,
  }) {
    return buildWithOpeningName(
      characterCardData: characterCardData,
      characterName: characterName,
      userName: userName,
    ).messages;
  }

  /// v103：顺带抽出开场人名，供状态栏立刻建档。
  static ChatOpeningMessages buildWithOpeningName({
    required Map<String, dynamic> characterCardData,
    required String characterName,
    required String userName,
  }) {
    final data = characterCardData['data'];
    if (data is! Map) {
      return const ChatOpeningMessages(messages: []);
    }

    final config = TrackerConfig.fromCardJson(characterCardData);
    String? openingName;
    final firstRaw = (data['first_mes'] as String? ?? '');
    if (firstRaw.contains(TrackerRuntime.kOpeningNamePlaceholder)) {
      openingName = TrackerRuntime.pickOpeningName(config);
    }

    String fill(String text) {
      var replaced = ChatVariableService.replacePlaceholders(
        text,
        characterName: characterName,
        userName: userName,
      );
      if (openingName != null) {
        replaced = TrackerRuntime.applyOpeningName(replaced, openingName);
      }
      return replaced.trim();
    }

    final messages = <String>[];
    final seen = <String>{};

    final firstMessage = firstRaw.trim();
    if (firstMessage.isNotEmpty) {
      final replaced = fill(firstMessage);
      if (replaced.isNotEmpty && seen.add(replaced)) {
        messages.add(replaced);
      }
    }

    final alternates = data['alternate_greetings'];
    if (alternates is List) {
      for (final item in alternates) {
        final text = item.toString().trim();
        if (text.isEmpty) {
          continue;
        }
        final replaced = fill(text);
        if (replaced.isNotEmpty && seen.add(replaced)) {
          messages.add(replaced);
        }
      }
    }

    return ChatOpeningMessages(messages: messages, openingName: openingName);
  }
}
