// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_chat_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_GroupChatSession _$GroupChatSessionFromJson(Map<String, dynamic> json) =>
    _GroupChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
      characterIds: (json['characterIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      turnIndex: (json['turnIndex'] as num?)?.toInt() ?? 0,
      replyMode: json['replyMode'] as String? ?? 'rotation',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$GroupChatSessionToJson(_GroupChatSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'characterIds': instance.characterIds,
      'turnIndex': instance.turnIndex,
      'replyMode': instance.replyMode,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
