// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark
//
// NOTE: this file currently includes a hand-written addition for the new
// `nostrPublishWarning` field because the local build_runner setup was
// broken at edit time. Re-run
// `dart run build_runner build --delete-conflicting-outputs` (or the
// flutter equivalent) to regenerate cleanly before merge — the codegen
// output should be byte-equivalent or close to what's here.

part of 'lightning_address_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LightningAddressState {

 bool get loading; bool get registering; bool get walletExists; String? get lightningAddress; String? get previousNym; String? get error; NymQuota? get quota; bool get quotaStale; String? get nostrPublishWarning;
/// Create a copy of LightningAddressState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LightningAddressStateCopyWith<LightningAddressState> get copyWith => _$LightningAddressStateCopyWithImpl<LightningAddressState>(this as LightningAddressState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LightningAddressState&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.registering, registering) || other.registering == registering)&&(identical(other.walletExists, walletExists) || other.walletExists == walletExists)&&(identical(other.lightningAddress, lightningAddress) || other.lightningAddress == lightningAddress)&&(identical(other.previousNym, previousNym) || other.previousNym == previousNym)&&(identical(other.error, error) || other.error == error)&&(identical(other.quota, quota) || other.quota == quota)&&(identical(other.quotaStale, quotaStale) || other.quotaStale == quotaStale)&&(identical(other.nostrPublishWarning, nostrPublishWarning) || other.nostrPublishWarning == nostrPublishWarning));
}


@override
int get hashCode => Object.hash(runtimeType,loading,registering,walletExists,lightningAddress,previousNym,error,quota,quotaStale,nostrPublishWarning);

@override
String toString() {
  return 'LightningAddressState(loading: $loading, registering: $registering, walletExists: $walletExists, lightningAddress: $lightningAddress, previousNym: $previousNym, error: $error, quota: $quota, quotaStale: $quotaStale, nostrPublishWarning: $nostrPublishWarning)';
}


}

/// @nodoc
abstract mixin class $LightningAddressStateCopyWith<$Res>  {
  factory $LightningAddressStateCopyWith(LightningAddressState value, $Res Function(LightningAddressState) _then) = _$LightningAddressStateCopyWithImpl;
@useResult
$Res call({
 bool loading, bool registering, bool walletExists, String? lightningAddress, String? previousNym, String? error, NymQuota? quota, bool quotaStale, String? nostrPublishWarning
});




}
/// @nodoc
class _$LightningAddressStateCopyWithImpl<$Res>
    implements $LightningAddressStateCopyWith<$Res> {
  _$LightningAddressStateCopyWithImpl(this._self, this._then);

  final LightningAddressState _self;
  final $Res Function(LightningAddressState) _then;

/// Create a copy of LightningAddressState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? loading = null,Object? registering = null,Object? walletExists = null,Object? lightningAddress = freezed,Object? previousNym = freezed,Object? error = freezed,Object? quota = freezed,Object? quotaStale = null,Object? nostrPublishWarning = freezed,}) {
  return _then(_self.copyWith(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,registering: null == registering ? _self.registering : registering // ignore: cast_nullable_to_non_nullable
as bool,walletExists: null == walletExists ? _self.walletExists : walletExists // ignore: cast_nullable_to_non_nullable
as bool,lightningAddress: freezed == lightningAddress ? _self.lightningAddress : lightningAddress // ignore: cast_nullable_to_non_nullable
as String?,previousNym: freezed == previousNym ? _self.previousNym : previousNym // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,quota: freezed == quota ? _self.quota : quota // ignore: cast_nullable_to_non_nullable
as NymQuota?,quotaStale: null == quotaStale ? _self.quotaStale : quotaStale // ignore: cast_nullable_to_non_nullable
as bool,nostrPublishWarning: freezed == nostrPublishWarning ? _self.nostrPublishWarning : nostrPublishWarning // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [LightningAddressState].
extension LightningAddressStatePatterns on LightningAddressState {
@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LightningAddressState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LightningAddressState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LightningAddressState value)  $default,){
final _that = this;
switch (_that) {
case _LightningAddressState():
return $default(_that);}
}
@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LightningAddressState value)?  $default,){
final _that = this;
switch (_that) {
case _LightningAddressState() when $default != null:
return $default(_that);case _:
  return null;

}
}
@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool loading,  bool registering,  bool walletExists,  String? lightningAddress,  String? previousNym,  String? error,  NymQuota? quota,  bool quotaStale,  String? nostrPublishWarning)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LightningAddressState() when $default != null:
return $default(_that.loading,_that.registering,_that.walletExists,_that.lightningAddress,_that.previousNym,_that.error,_that.quota,_that.quotaStale,_that.nostrPublishWarning);case _:
  return orElse();

}
}
@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool loading,  bool registering,  bool walletExists,  String? lightningAddress,  String? previousNym,  String? error,  NymQuota? quota,  bool quotaStale,  String? nostrPublishWarning)  $default,) {final _that = this;
switch (_that) {
case _LightningAddressState():
return $default(_that.loading,_that.registering,_that.walletExists,_that.lightningAddress,_that.previousNym,_that.error,_that.quota,_that.quotaStale,_that.nostrPublishWarning);}
}
@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool loading,  bool registering,  bool walletExists,  String? lightningAddress,  String? previousNym,  String? error,  NymQuota? quota,  bool quotaStale,  String? nostrPublishWarning)?  $default,) {final _that = this;
switch (_that) {
case _LightningAddressState() when $default != null:
return $default(_that.loading,_that.registering,_that.walletExists,_that.lightningAddress,_that.previousNym,_that.error,_that.quota,_that.quotaStale,_that.nostrPublishWarning);case _:
  return null;

}
}

}

/// @nodoc


class _LightningAddressState implements LightningAddressState {
  const _LightningAddressState({this.loading = true, this.registering = false, this.walletExists = false, this.lightningAddress, this.previousNym, this.error, this.quota, this.quotaStale = false, this.nostrPublishWarning});


@override@JsonKey() final  bool loading;
@override@JsonKey() final  bool registering;
@override@JsonKey() final  bool walletExists;
@override final  String? lightningAddress;
@override final  String? previousNym;
@override final  String? error;
@override final  NymQuota? quota;
@override@JsonKey() final  bool quotaStale;
@override final  String? nostrPublishWarning;

/// Create a copy of LightningAddressState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LightningAddressStateCopyWith<_LightningAddressState> get copyWith => __$LightningAddressStateCopyWithImpl<_LightningAddressState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LightningAddressState&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.registering, registering) || other.registering == registering)&&(identical(other.walletExists, walletExists) || other.walletExists == walletExists)&&(identical(other.lightningAddress, lightningAddress) || other.lightningAddress == lightningAddress)&&(identical(other.previousNym, previousNym) || other.previousNym == previousNym)&&(identical(other.error, error) || other.error == error)&&(identical(other.quota, quota) || other.quota == quota)&&(identical(other.quotaStale, quotaStale) || other.quotaStale == quotaStale)&&(identical(other.nostrPublishWarning, nostrPublishWarning) || other.nostrPublishWarning == nostrPublishWarning));
}


@override
int get hashCode => Object.hash(runtimeType,loading,registering,walletExists,lightningAddress,previousNym,error,quota,quotaStale,nostrPublishWarning);

@override
String toString() {
  return 'LightningAddressState(loading: $loading, registering: $registering, walletExists: $walletExists, lightningAddress: $lightningAddress, previousNym: $previousNym, error: $error, quota: $quota, quotaStale: $quotaStale, nostrPublishWarning: $nostrPublishWarning)';
}


}

/// @nodoc
abstract mixin class _$LightningAddressStateCopyWith<$Res> implements $LightningAddressStateCopyWith<$Res> {
  factory _$LightningAddressStateCopyWith(_LightningAddressState value, $Res Function(_LightningAddressState) _then) = __$LightningAddressStateCopyWithImpl;
@override @useResult
$Res call({
 bool loading, bool registering, bool walletExists, String? lightningAddress, String? previousNym, String? error, NymQuota? quota, bool quotaStale, String? nostrPublishWarning
});




}
/// @nodoc
class __$LightningAddressStateCopyWithImpl<$Res>
    implements _$LightningAddressStateCopyWith<$Res> {
  __$LightningAddressStateCopyWithImpl(this._self, this._then);

  final _LightningAddressState _self;
  final $Res Function(_LightningAddressState) _then;

/// Create a copy of LightningAddressState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? loading = null,Object? registering = null,Object? walletExists = null,Object? lightningAddress = freezed,Object? previousNym = freezed,Object? error = freezed,Object? quota = freezed,Object? quotaStale = null,Object? nostrPublishWarning = freezed,}) {
  return _then(_LightningAddressState(
loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,registering: null == registering ? _self.registering : registering // ignore: cast_nullable_to_non_nullable
as bool,walletExists: null == walletExists ? _self.walletExists : walletExists // ignore: cast_nullable_to_non_nullable
as bool,lightningAddress: freezed == lightningAddress ? _self.lightningAddress : lightningAddress // ignore: cast_nullable_to_non_nullable
as String?,previousNym: freezed == previousNym ? _self.previousNym : previousNym // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,quota: freezed == quota ? _self.quota : quota // ignore: cast_nullable_to_non_nullable
as NymQuota?,quotaStale: null == quotaStale ? _self.quotaStale : quotaStale // ignore: cast_nullable_to_non_nullable
as bool,nostrPublishWarning: freezed == nostrPublishWarning ? _self.nostrPublishWarning : nostrPublishWarning // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
