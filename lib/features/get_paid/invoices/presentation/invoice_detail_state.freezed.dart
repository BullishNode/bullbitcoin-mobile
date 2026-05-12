// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'invoice_detail_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InvoiceDetailState {

 InvoiceId? get invoiceId; String? get nymOwner; InvoiceStatusSnapshot? get snapshot; CancelInvoiceResult? get cancelResult; bool get isLoading; bool get isCancelling; String? get error;
/// Create a copy of InvoiceDetailState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InvoiceDetailStateCopyWith<InvoiceDetailState> get copyWith => _$InvoiceDetailStateCopyWithImpl<InvoiceDetailState>(this as InvoiceDetailState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InvoiceDetailState&&(identical(other.invoiceId, invoiceId) || other.invoiceId == invoiceId)&&(identical(other.nymOwner, nymOwner) || other.nymOwner == nymOwner)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot)&&(identical(other.cancelResult, cancelResult) || other.cancelResult == cancelResult)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isCancelling, isCancelling) || other.isCancelling == isCancelling)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,invoiceId,nymOwner,snapshot,cancelResult,isLoading,isCancelling,error);

@override
String toString() {
  return 'InvoiceDetailState(invoiceId: $invoiceId, nymOwner: $nymOwner, snapshot: $snapshot, cancelResult: $cancelResult, isLoading: $isLoading, isCancelling: $isCancelling, error: $error)';
}


}

/// @nodoc
abstract mixin class $InvoiceDetailStateCopyWith<$Res>  {
  factory $InvoiceDetailStateCopyWith(InvoiceDetailState value, $Res Function(InvoiceDetailState) _then) = _$InvoiceDetailStateCopyWithImpl;
@useResult
$Res call({
 InvoiceId? invoiceId, String? nymOwner, InvoiceStatusSnapshot? snapshot, CancelInvoiceResult? cancelResult, bool isLoading, bool isCancelling, String? error
});




}
/// @nodoc
class _$InvoiceDetailStateCopyWithImpl<$Res>
    implements $InvoiceDetailStateCopyWith<$Res> {
  _$InvoiceDetailStateCopyWithImpl(this._self, this._then);

  final InvoiceDetailState _self;
  final $Res Function(InvoiceDetailState) _then;

/// Create a copy of InvoiceDetailState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? invoiceId = freezed,Object? nymOwner = freezed,Object? snapshot = freezed,Object? cancelResult = freezed,Object? isLoading = null,Object? isCancelling = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
invoiceId: freezed == invoiceId ? _self.invoiceId : invoiceId // ignore: cast_nullable_to_non_nullable
as InvoiceId?,nymOwner: freezed == nymOwner ? _self.nymOwner : nymOwner // ignore: cast_nullable_to_non_nullable
as String?,snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as InvoiceStatusSnapshot?,cancelResult: freezed == cancelResult ? _self.cancelResult : cancelResult // ignore: cast_nullable_to_non_nullable
as CancelInvoiceResult?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isCancelling: null == isCancelling ? _self.isCancelling : isCancelling // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InvoiceDetailState].
extension InvoiceDetailStatePatterns on InvoiceDetailState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InvoiceDetailState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InvoiceDetailState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InvoiceDetailState value)  $default,){
final _that = this;
switch (_that) {
case _InvoiceDetailState():
return $default(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InvoiceDetailState value)?  $default,){
final _that = this;
switch (_that) {
case _InvoiceDetailState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InvoiceId? invoiceId,  String? nymOwner,  InvoiceStatusSnapshot? snapshot,  CancelInvoiceResult? cancelResult,  bool isLoading,  bool isCancelling,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InvoiceDetailState() when $default != null:
return $default(_that.invoiceId,_that.nymOwner,_that.snapshot,_that.cancelResult,_that.isLoading,_that.isCancelling,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InvoiceId? invoiceId,  String? nymOwner,  InvoiceStatusSnapshot? snapshot,  CancelInvoiceResult? cancelResult,  bool isLoading,  bool isCancelling,  String? error)  $default,) {final _that = this;
switch (_that) {
case _InvoiceDetailState():
return $default(_that.invoiceId,_that.nymOwner,_that.snapshot,_that.cancelResult,_that.isLoading,_that.isCancelling,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InvoiceId? invoiceId,  String? nymOwner,  InvoiceStatusSnapshot? snapshot,  CancelInvoiceResult? cancelResult,  bool isLoading,  bool isCancelling,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _InvoiceDetailState() when $default != null:
return $default(_that.invoiceId,_that.nymOwner,_that.snapshot,_that.cancelResult,_that.isLoading,_that.isCancelling,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _InvoiceDetailState extends InvoiceDetailState {
  const _InvoiceDetailState({this.invoiceId, this.nymOwner, this.snapshot, this.cancelResult, this.isLoading = false, this.isCancelling = false, this.error}): super._();
  

@override final  InvoiceId? invoiceId;
@override final  String? nymOwner;
@override final  InvoiceStatusSnapshot? snapshot;
@override final  CancelInvoiceResult? cancelResult;
@override@JsonKey() final  bool isLoading;
@override@JsonKey() final  bool isCancelling;
@override final  String? error;

/// Create a copy of InvoiceDetailState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InvoiceDetailStateCopyWith<_InvoiceDetailState> get copyWith => __$InvoiceDetailStateCopyWithImpl<_InvoiceDetailState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InvoiceDetailState&&(identical(other.invoiceId, invoiceId) || other.invoiceId == invoiceId)&&(identical(other.nymOwner, nymOwner) || other.nymOwner == nymOwner)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot)&&(identical(other.cancelResult, cancelResult) || other.cancelResult == cancelResult)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isCancelling, isCancelling) || other.isCancelling == isCancelling)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,invoiceId,nymOwner,snapshot,cancelResult,isLoading,isCancelling,error);

@override
String toString() {
  return 'InvoiceDetailState(invoiceId: $invoiceId, nymOwner: $nymOwner, snapshot: $snapshot, cancelResult: $cancelResult, isLoading: $isLoading, isCancelling: $isCancelling, error: $error)';
}


}

/// @nodoc
abstract mixin class _$InvoiceDetailStateCopyWith<$Res> implements $InvoiceDetailStateCopyWith<$Res> {
  factory _$InvoiceDetailStateCopyWith(_InvoiceDetailState value, $Res Function(_InvoiceDetailState) _then) = __$InvoiceDetailStateCopyWithImpl;
@override @useResult
$Res call({
 InvoiceId? invoiceId, String? nymOwner, InvoiceStatusSnapshot? snapshot, CancelInvoiceResult? cancelResult, bool isLoading, bool isCancelling, String? error
});




}
/// @nodoc
class __$InvoiceDetailStateCopyWithImpl<$Res>
    implements _$InvoiceDetailStateCopyWith<$Res> {
  __$InvoiceDetailStateCopyWithImpl(this._self, this._then);

  final _InvoiceDetailState _self;
  final $Res Function(_InvoiceDetailState) _then;

/// Create a copy of InvoiceDetailState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? invoiceId = freezed,Object? nymOwner = freezed,Object? snapshot = freezed,Object? cancelResult = freezed,Object? isLoading = null,Object? isCancelling = null,Object? error = freezed,}) {
  return _then(_InvoiceDetailState(
invoiceId: freezed == invoiceId ? _self.invoiceId : invoiceId // ignore: cast_nullable_to_non_nullable
as InvoiceId?,nymOwner: freezed == nymOwner ? _self.nymOwner : nymOwner // ignore: cast_nullable_to_non_nullable
as String?,snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as InvoiceStatusSnapshot?,cancelResult: freezed == cancelResult ? _self.cancelResult : cancelResult // ignore: cast_nullable_to_non_nullable
as CancelInvoiceResult?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isCancelling: null == isCancelling ? _self.isCancelling : isCancelling // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
