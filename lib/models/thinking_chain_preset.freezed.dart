// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thinking_chain_preset.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ThinkingChainPreset {

 String get id; String get name; String get template; DateTime get updatedAt;
/// Create a copy of ThinkingChainPreset
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThinkingChainPresetCopyWith<ThinkingChainPreset> get copyWith => _$ThinkingChainPresetCopyWithImpl<ThinkingChainPreset>(this as ThinkingChainPreset, _$identity);

  /// Serializes this ThinkingChainPreset to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThinkingChainPreset&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.template, template) || other.template == template)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,template,updatedAt);

@override
String toString() {
  return 'ThinkingChainPreset(id: $id, name: $name, template: $template, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ThinkingChainPresetCopyWith<$Res>  {
  factory $ThinkingChainPresetCopyWith(ThinkingChainPreset value, $Res Function(ThinkingChainPreset) _then) = _$ThinkingChainPresetCopyWithImpl;
@useResult
$Res call({
 String id, String name, String template, DateTime updatedAt
});




}
/// @nodoc
class _$ThinkingChainPresetCopyWithImpl<$Res>
    implements $ThinkingChainPresetCopyWith<$Res> {
  _$ThinkingChainPresetCopyWithImpl(this._self, this._then);

  final ThinkingChainPreset _self;
  final $Res Function(ThinkingChainPreset) _then;

/// Create a copy of ThinkingChainPreset
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? template = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,template: null == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [ThinkingChainPreset].
extension ThinkingChainPresetPatterns on ThinkingChainPreset {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThinkingChainPreset value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThinkingChainPreset() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThinkingChainPreset value)  $default,){
final _that = this;
switch (_that) {
case _ThinkingChainPreset():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThinkingChainPreset value)?  $default,){
final _that = this;
switch (_that) {
case _ThinkingChainPreset() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String template,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThinkingChainPreset() when $default != null:
return $default(_that.id,_that.name,_that.template,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String template,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ThinkingChainPreset():
return $default(_that.id,_that.name,_that.template,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String template,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ThinkingChainPreset() when $default != null:
return $default(_that.id,_that.name,_that.template,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ThinkingChainPreset extends ThinkingChainPreset {
  const _ThinkingChainPreset({required this.id, required this.name, required this.template, required this.updatedAt}): super._();
  factory _ThinkingChainPreset.fromJson(Map<String, dynamic> json) => _$ThinkingChainPresetFromJson(json);

@override final  String id;
@override final  String name;
@override final  String template;
@override final  DateTime updatedAt;

/// Create a copy of ThinkingChainPreset
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThinkingChainPresetCopyWith<_ThinkingChainPreset> get copyWith => __$ThinkingChainPresetCopyWithImpl<_ThinkingChainPreset>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ThinkingChainPresetToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThinkingChainPreset&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.template, template) || other.template == template)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,template,updatedAt);

@override
String toString() {
  return 'ThinkingChainPreset(id: $id, name: $name, template: $template, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ThinkingChainPresetCopyWith<$Res> implements $ThinkingChainPresetCopyWith<$Res> {
  factory _$ThinkingChainPresetCopyWith(_ThinkingChainPreset value, $Res Function(_ThinkingChainPreset) _then) = __$ThinkingChainPresetCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String template, DateTime updatedAt
});




}
/// @nodoc
class __$ThinkingChainPresetCopyWithImpl<$Res>
    implements _$ThinkingChainPresetCopyWith<$Res> {
  __$ThinkingChainPresetCopyWithImpl(this._self, this._then);

  final _ThinkingChainPreset _self;
  final $Res Function(_ThinkingChainPreset) _then;

/// Create a copy of ThinkingChainPreset
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? template = null,Object? updatedAt = null,}) {
  return _then(_ThinkingChainPreset(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,template: null == template ? _self.template : template // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
