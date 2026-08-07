// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quick_command.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$QuickCommand {

 String get id; String get name; String get prompt; int get order;/// 特别版：发送类型（直接发送 / 询问后发送），默认直接发送。
 QuickCommandType get type;
/// Create a copy of QuickCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuickCommandCopyWith<QuickCommand> get copyWith => _$QuickCommandCopyWithImpl<QuickCommand>(this as QuickCommand, _$identity);

  /// Serializes this QuickCommand to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuickCommand&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.order, order) || other.order == order)&&(identical(other.type, type) || other.type == type));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,prompt,order,type);

@override
String toString() {
  return 'QuickCommand(id: $id, name: $name, prompt: $prompt, order: $order, type: $type)';
}


}

/// @nodoc
abstract mixin class $QuickCommandCopyWith<$Res>  {
  factory $QuickCommandCopyWith(QuickCommand value, $Res Function(QuickCommand) _then) = _$QuickCommandCopyWithImpl;
@useResult
$Res call({
 String id, String name, String prompt, int order, QuickCommandType type
});




}
/// @nodoc
class _$QuickCommandCopyWithImpl<$Res>
    implements $QuickCommandCopyWith<$Res> {
  _$QuickCommandCopyWithImpl(this._self, this._then);

  final QuickCommand _self;
  final $Res Function(QuickCommand) _then;

/// Create a copy of QuickCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? order = null,Object? type = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuickCommandType,
  ));
}

}


/// Adds pattern-matching-related methods to [QuickCommand].
extension QuickCommandPatterns on QuickCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuickCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuickCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuickCommand value)  $default,){
final _that = this;
switch (_that) {
case _QuickCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuickCommand value)?  $default,){
final _that = this;
switch (_that) {
case _QuickCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  int order,  QuickCommandType type)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuickCommand() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.order,_that.type);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String prompt,  int order,  QuickCommandType type)  $default,) {final _that = this;
switch (_that) {
case _QuickCommand():
return $default(_that.id,_that.name,_that.prompt,_that.order,_that.type);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String prompt,  int order,  QuickCommandType type)?  $default,) {final _that = this;
switch (_that) {
case _QuickCommand() when $default != null:
return $default(_that.id,_that.name,_that.prompt,_that.order,_that.type);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuickCommand extends QuickCommand {
  const _QuickCommand({required this.id, required this.name, required this.prompt, this.order = 0, this.type = QuickCommandType.direct}): super._();
  factory _QuickCommand.fromJson(Map<String, dynamic> json) => _$QuickCommandFromJson(json);

@override final  String id;
@override final  String name;
@override final  String prompt;
@override@JsonKey() final  int order;
/// 特别版：发送类型（直接发送 / 询问后发送），默认直接发送。
@override@JsonKey() final  QuickCommandType type;

/// Create a copy of QuickCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuickCommandCopyWith<_QuickCommand> get copyWith => __$QuickCommandCopyWithImpl<_QuickCommand>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuickCommandToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuickCommand&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.order, order) || other.order == order)&&(identical(other.type, type) || other.type == type));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,prompt,order,type);

@override
String toString() {
  return 'QuickCommand(id: $id, name: $name, prompt: $prompt, order: $order, type: $type)';
}


}

/// @nodoc
abstract mixin class _$QuickCommandCopyWith<$Res> implements $QuickCommandCopyWith<$Res> {
  factory _$QuickCommandCopyWith(_QuickCommand value, $Res Function(_QuickCommand) _then) = __$QuickCommandCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String prompt, int order, QuickCommandType type
});




}
/// @nodoc
class __$QuickCommandCopyWithImpl<$Res>
    implements _$QuickCommandCopyWith<$Res> {
  __$QuickCommandCopyWithImpl(this._self, this._then);

  final _QuickCommand _self;
  final $Res Function(_QuickCommand) _then;

/// Create a copy of QuickCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? prompt = null,Object? order = null,Object? type = null,}) {
  return _then(_QuickCommand(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,order: null == order ? _self.order : order // ignore: cast_nullable_to_non_nullable
as int,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuickCommandType,
  ));
}


}

// dart format on
