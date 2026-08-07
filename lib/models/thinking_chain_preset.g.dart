// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thinking_chain_preset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ThinkingChainPreset _$ThinkingChainPresetFromJson(Map<String, dynamic> json) =>
    _ThinkingChainPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      template: json['template'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$ThinkingChainPresetToJson(
  _ThinkingChainPreset instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'template': instance.template,
  'updatedAt': instance.updatedAt.toIso8601String(),
};
