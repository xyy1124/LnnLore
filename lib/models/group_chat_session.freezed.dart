// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'group_chat_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$GroupChatSession {

 String get id; String get title; List<String> get characterIds;/// 下一位回复的角色索引（轮转游标）
 int get turnIndex;/// 回复模式（特别版）：rotation 轮流制 / everyone 全员回复
 String get replyMode; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of GroupChatSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupChatSessionCopyWith<GroupChatSession> get copyWith => _$GroupChatSessionCopyWithImpl<GroupChatSession>(this as GroupChatSession, _$identity);

  /// Serializes this GroupChatSession to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupChatSession&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.characterIds, characterIds)&&(identical(other.turnIndex, turnIndex) || other.turnIndex == turnIndex)&&(identical(other.replyMode, replyMode) || other.replyMode == replyMode)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(characterIds),turnIndex,replyMode,createdAt,updatedAt);

@override
String toString() {
  return 'GroupChatSession(id: $id, title: $title, characterIds: $characterIds, turnIndex: $turnIndex, replyMode: $replyMode, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $GroupChatSessionCopyWith<$Res>  {
  factory $GroupChatSessionCopyWith(GroupChatSession value, $Res Function(GroupChatSession) _then) = _$GroupChatSessionCopyWithImpl;
@useResult
$Res call({
 String id, String title, List<String> characterIds, int turnIndex, String replyMode, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$GroupChatSessionCopyWithImpl<$Res>
    implements $GroupChatSessionCopyWith<$Res> {
  _$GroupChatSessionCopyWithImpl(this._self, this._then);

  final GroupChatSession _self;
  final $Res Function(GroupChatSession) _then;

/// Create a copy of GroupChatSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? characterIds = null,Object? turnIndex = null,Object? replyMode = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,characterIds: null == characterIds ? _self.characterIds : characterIds // ignore: cast_nullable_to_non_nullable
as List<String>,turnIndex: null == turnIndex ? _self.turnIndex : turnIndex // ignore: cast_nullable_to_non_nullable
as int,replyMode: null == replyMode ? _self.replyMode : replyMode // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [GroupChatSession].
extension GroupChatSessionPatterns on GroupChatSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GroupChatSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GroupChatSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GroupChatSession value)  $default,){
final _that = this;
switch (_that) {
case _GroupChatSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GroupChatSession value)?  $default,){
final _that = this;
switch (_that) {
case _GroupChatSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  List<String> characterIds,  int turnIndex,  String replyMode,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GroupChatSession() when $default != null:
return $default(_that.id,_that.title,_that.characterIds,_that.turnIndex,_that.replyMode,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  List<String> characterIds,  int turnIndex,  String replyMode,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _GroupChatSession():
return $default(_that.id,_that.title,_that.characterIds,_that.turnIndex,_that.replyMode,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  List<String> characterIds,  int turnIndex,  String replyMode,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _GroupChatSession() when $default != null:
return $default(_that.id,_that.title,_that.characterIds,_that.turnIndex,_that.replyMode,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GroupChatSession extends GroupChatSession {
  const _GroupChatSession({required this.id, required this.title, required final  List<String> characterIds, this.turnIndex = 0, this.replyMode = 'rotation', required this.createdAt, required this.updatedAt}): _characterIds = characterIds,super._();
  factory _GroupChatSession.fromJson(Map<String, dynamic> json) => _$GroupChatSessionFromJson(json);

@override final  String id;
@override final  String title;
 final  List<String> _characterIds;
@override List<String> get characterIds {
  if (_characterIds is EqualUnmodifiableListView) return _characterIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_characterIds);
}

/// 下一位回复的角色索引（轮转游标）
@override@JsonKey() final  int turnIndex;
/// 回复模式（特别版）：rotation 轮流制 / everyone 全员回复
@override@JsonKey() final  String replyMode;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of GroupChatSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GroupChatSessionCopyWith<_GroupChatSession> get copyWith => __$GroupChatSessionCopyWithImpl<_GroupChatSession>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GroupChatSessionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GroupChatSession&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._characterIds, _characterIds)&&(identical(other.turnIndex, turnIndex) || other.turnIndex == turnIndex)&&(identical(other.replyMode, replyMode) || other.replyMode == replyMode)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(_characterIds),turnIndex,replyMode,createdAt,updatedAt);

@override
String toString() {
  return 'GroupChatSession(id: $id, title: $title, characterIds: $characterIds, turnIndex: $turnIndex, replyMode: $replyMode, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$GroupChatSessionCopyWith<$Res> implements $GroupChatSessionCopyWith<$Res> {
  factory _$GroupChatSessionCopyWith(_GroupChatSession value, $Res Function(_GroupChatSession) _then) = __$GroupChatSessionCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, List<String> characterIds, int turnIndex, String replyMode, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$GroupChatSessionCopyWithImpl<$Res>
    implements _$GroupChatSessionCopyWith<$Res> {
  __$GroupChatSessionCopyWithImpl(this._self, this._then);

  final _GroupChatSession _self;
  final $Res Function(_GroupChatSession) _then;

/// Create a copy of GroupChatSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? characterIds = null,Object? turnIndex = null,Object? replyMode = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_GroupChatSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,characterIds: null == characterIds ? _self._characterIds : characterIds // ignore: cast_nullable_to_non_nullable
as List<String>,turnIndex: null == turnIndex ? _self.turnIndex : turnIndex // ignore: cast_nullable_to_non_nullable
as int,replyMode: null == replyMode ? _self.replyMode : replyMode // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
