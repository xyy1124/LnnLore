// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quick_command.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_QuickCommand _$QuickCommandFromJson(Map<String, dynamic> json) =>
    _QuickCommand(
      id: json['id'] as String,
      name: json['name'] as String,
      prompt: json['prompt'] as String,
      order: (json['order'] as num?)?.toInt() ?? 0,
      type:
          $enumDecodeNullable(_$QuickCommandTypeEnumMap, json['type']) ??
          QuickCommandType.direct,
    );

Map<String, dynamic> _$QuickCommandToJson(_QuickCommand instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'prompt': instance.prompt,
      'order': instance.order,
      'type': _$QuickCommandTypeEnumMap[instance.type]!,
    };

const _$QuickCommandTypeEnumMap = {
  QuickCommandType.direct: 'direct',
  QuickCommandType.prompt: 'prompt',
  QuickCommandType.insert: 'insert',
};
