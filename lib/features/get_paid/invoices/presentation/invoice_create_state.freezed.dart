// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'invoice_create_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InvoiceCreateState {

 int? get amountSat; int? get fiatAmountMinor; String? get fiatCurrency; String get publicDescription; String get recipientName; String get invoiceNumber; bool get acceptBtc; bool get acceptLn; bool get acceptLiquid; DateTime get expiresAt; String get linkToPageNym; String get privateMemo; bool get isSubmitting; CreateInvoiceResult? get result; String? get error;
/// Create a copy of InvoiceCreateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InvoiceCreateStateCopyWith<InvoiceCreateState> get copyWith => _$InvoiceCreateStateCopyWithImpl<InvoiceCreateState>(this as InvoiceCreateState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InvoiceCreateState&&(identical(other.amountSat, amountSat) || other.amountSat == amountSat)&&(identical(other.fiatAmountMinor, fiatAmountMinor) || other.fiatAmountMinor == fiatAmountMinor)&&(identical(other.fiatCurrency, fiatCurrency) || other.fiatCurrency == fiatCurrency)&&(identical(other.publicDescription, publicDescription) || other.publicDescription == publicDescription)&&(identical(other.recipientName, recipientName) || other.recipientName == recipientName)&&(identical(other.invoiceNumber, invoiceNumber) || other.invoiceNumber == invoiceNumber)&&(identical(other.acceptBtc, acceptBtc) || other.acceptBtc == acceptBtc)&&(identical(other.acceptLn, acceptLn) || other.acceptLn == acceptLn)&&(identical(other.acceptLiquid, acceptLiquid) || other.acceptLiquid == acceptLiquid)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.linkToPageNym, linkToPageNym) || other.linkToPageNym == linkToPageNym)&&(identical(other.privateMemo, privateMemo) || other.privateMemo == privateMemo)&&(identical(other.isSubmitting, isSubmitting) || other.isSubmitting == isSubmitting)&&(identical(other.result, result) || other.result == result)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,amountSat,fiatAmountMinor,fiatCurrency,publicDescription,recipientName,invoiceNumber,acceptBtc,acceptLn,acceptLiquid,expiresAt,linkToPageNym,privateMemo,isSubmitting,result,error);

@override
String toString() {
  return 'InvoiceCreateState(amountSat: $amountSat, fiatAmountMinor: $fiatAmountMinor, fiatCurrency: $fiatCurrency, publicDescription: $publicDescription, recipientName: $recipientName, invoiceNumber: $invoiceNumber, acceptBtc: $acceptBtc, acceptLn: $acceptLn, acceptLiquid: $acceptLiquid, expiresAt: $expiresAt, linkToPageNym: $linkToPageNym, privateMemo: $privateMemo, isSubmitting: $isSubmitting, result: $result, error: $error)';
}


}

/// @nodoc
abstract mixin class $InvoiceCreateStateCopyWith<$Res>  {
  factory $InvoiceCreateStateCopyWith(InvoiceCreateState value, $Res Function(InvoiceCreateState) _then) = _$InvoiceCreateStateCopyWithImpl;
@useResult
$Res call({
 int? amountSat, int? fiatAmountMinor, String? fiatCurrency, String publicDescription, String recipientName, String invoiceNumber, bool acceptBtc, bool acceptLn, bool acceptLiquid, DateTime expiresAt, String linkToPageNym, String privateMemo, bool isSubmitting, CreateInvoiceResult? result, String? error
});




}
/// @nodoc
class _$InvoiceCreateStateCopyWithImpl<$Res>
    implements $InvoiceCreateStateCopyWith<$Res> {
  _$InvoiceCreateStateCopyWithImpl(this._self, this._then);

  final InvoiceCreateState _self;
  final $Res Function(InvoiceCreateState) _then;

/// Create a copy of InvoiceCreateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? amountSat = freezed,Object? fiatAmountMinor = freezed,Object? fiatCurrency = freezed,Object? publicDescription = null,Object? recipientName = null,Object? invoiceNumber = null,Object? acceptBtc = null,Object? acceptLn = null,Object? acceptLiquid = null,Object? expiresAt = null,Object? linkToPageNym = null,Object? privateMemo = null,Object? isSubmitting = null,Object? result = freezed,Object? error = freezed,}) {
  return _then(_self.copyWith(
amountSat: freezed == amountSat ? _self.amountSat : amountSat // ignore: cast_nullable_to_non_nullable
as int?,fiatAmountMinor: freezed == fiatAmountMinor ? _self.fiatAmountMinor : fiatAmountMinor // ignore: cast_nullable_to_non_nullable
as int?,fiatCurrency: freezed == fiatCurrency ? _self.fiatCurrency : fiatCurrency // ignore: cast_nullable_to_non_nullable
as String?,publicDescription: null == publicDescription ? _self.publicDescription : publicDescription // ignore: cast_nullable_to_non_nullable
as String,recipientName: null == recipientName ? _self.recipientName : recipientName // ignore: cast_nullable_to_non_nullable
as String,invoiceNumber: null == invoiceNumber ? _self.invoiceNumber : invoiceNumber // ignore: cast_nullable_to_non_nullable
as String,acceptBtc: null == acceptBtc ? _self.acceptBtc : acceptBtc // ignore: cast_nullable_to_non_nullable
as bool,acceptLn: null == acceptLn ? _self.acceptLn : acceptLn // ignore: cast_nullable_to_non_nullable
as bool,acceptLiquid: null == acceptLiquid ? _self.acceptLiquid : acceptLiquid // ignore: cast_nullable_to_non_nullable
as bool,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime,linkToPageNym: null == linkToPageNym ? _self.linkToPageNym : linkToPageNym // ignore: cast_nullable_to_non_nullable
as String,privateMemo: null == privateMemo ? _self.privateMemo : privateMemo // ignore: cast_nullable_to_non_nullable
as String,isSubmitting: null == isSubmitting ? _self.isSubmitting : isSubmitting // ignore: cast_nullable_to_non_nullable
as bool,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CreateInvoiceResult?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InvoiceCreateState].
extension InvoiceCreateStatePatterns on InvoiceCreateState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InvoiceCreateState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InvoiceCreateState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InvoiceCreateState value)  $default,){
final _that = this;
switch (_that) {
case _InvoiceCreateState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InvoiceCreateState value)?  $default,){
final _that = this;
switch (_that) {
case _InvoiceCreateState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? amountSat,  int? fiatAmountMinor,  String? fiatCurrency,  String publicDescription,  String recipientName,  String invoiceNumber,  bool acceptBtc,  bool acceptLn,  bool acceptLiquid,  DateTime expiresAt,  String linkToPageNym,  String privateMemo,  bool isSubmitting,  CreateInvoiceResult? result,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InvoiceCreateState() when $default != null:
return $default(_that.amountSat,_that.fiatAmountMinor,_that.fiatCurrency,_that.publicDescription,_that.recipientName,_that.invoiceNumber,_that.acceptBtc,_that.acceptLn,_that.acceptLiquid,_that.expiresAt,_that.linkToPageNym,_that.privateMemo,_that.isSubmitting,_that.result,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? amountSat,  int? fiatAmountMinor,  String? fiatCurrency,  String publicDescription,  String recipientName,  String invoiceNumber,  bool acceptBtc,  bool acceptLn,  bool acceptLiquid,  DateTime expiresAt,  String linkToPageNym,  String privateMemo,  bool isSubmitting,  CreateInvoiceResult? result,  String? error)  $default,) {final _that = this;
switch (_that) {
case _InvoiceCreateState():
return $default(_that.amountSat,_that.fiatAmountMinor,_that.fiatCurrency,_that.publicDescription,_that.recipientName,_that.invoiceNumber,_that.acceptBtc,_that.acceptLn,_that.acceptLiquid,_that.expiresAt,_that.linkToPageNym,_that.privateMemo,_that.isSubmitting,_that.result,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? amountSat,  int? fiatAmountMinor,  String? fiatCurrency,  String publicDescription,  String recipientName,  String invoiceNumber,  bool acceptBtc,  bool acceptLn,  bool acceptLiquid,  DateTime expiresAt,  String linkToPageNym,  String privateMemo,  bool isSubmitting,  CreateInvoiceResult? result,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _InvoiceCreateState() when $default != null:
return $default(_that.amountSat,_that.fiatAmountMinor,_that.fiatCurrency,_that.publicDescription,_that.recipientName,_that.invoiceNumber,_that.acceptBtc,_that.acceptLn,_that.acceptLiquid,_that.expiresAt,_that.linkToPageNym,_that.privateMemo,_that.isSubmitting,_that.result,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _InvoiceCreateState extends InvoiceCreateState {
  const _InvoiceCreateState({this.amountSat, this.fiatAmountMinor, this.fiatCurrency, this.publicDescription = '', this.recipientName = '', this.invoiceNumber = '', this.acceptBtc = true, this.acceptLn = true, this.acceptLiquid = true, required this.expiresAt, this.linkToPageNym = '', this.privateMemo = '', this.isSubmitting = false, this.result, this.error}): super._();


@override final  int? amountSat;
@override final  int? fiatAmountMinor;
@override final  String? fiatCurrency;
@override@JsonKey() final  String publicDescription;
@override@JsonKey() final  String recipientName;
@override@JsonKey() final  String invoiceNumber;
@override@JsonKey() final  bool acceptBtc;
@override@JsonKey() final  bool acceptLn;
@override@JsonKey() final  bool acceptLiquid;
@override final  DateTime expiresAt;
@override@JsonKey() final  String linkToPageNym;
@override@JsonKey() final  String privateMemo;
@override@JsonKey() final  bool isSubmitting;
@override final  CreateInvoiceResult? result;
@override final  String? error;

/// Create a copy of InvoiceCreateState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InvoiceCreateStateCopyWith<_InvoiceCreateState> get copyWith => __$InvoiceCreateStateCopyWithImpl<_InvoiceCreateState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InvoiceCreateState&&(identical(other.amountSat, amountSat) || other.amountSat == amountSat)&&(identical(other.fiatAmountMinor, fiatAmountMinor) || other.fiatAmountMinor == fiatAmountMinor)&&(identical(other.fiatCurrency, fiatCurrency) || other.fiatCurrency == fiatCurrency)&&(identical(other.publicDescription, publicDescription) || other.publicDescription == publicDescription)&&(identical(other.recipientName, recipientName) || other.recipientName == recipientName)&&(identical(other.invoiceNumber, invoiceNumber) || other.invoiceNumber == invoiceNumber)&&(identical(other.acceptBtc, acceptBtc) || other.acceptBtc == acceptBtc)&&(identical(other.acceptLn, acceptLn) || other.acceptLn == acceptLn)&&(identical(other.acceptLiquid, acceptLiquid) || other.acceptLiquid == acceptLiquid)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.linkToPageNym, linkToPageNym) || other.linkToPageNym == linkToPageNym)&&(identical(other.privateMemo, privateMemo) || other.privateMemo == privateMemo)&&(identical(other.isSubmitting, isSubmitting) || other.isSubmitting == isSubmitting)&&(identical(other.result, result) || other.result == result)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,amountSat,fiatAmountMinor,fiatCurrency,publicDescription,recipientName,invoiceNumber,acceptBtc,acceptLn,acceptLiquid,expiresAt,linkToPageNym,privateMemo,isSubmitting,result,error);

@override
String toString() {
  return 'InvoiceCreateState(amountSat: $amountSat, fiatAmountMinor: $fiatAmountMinor, fiatCurrency: $fiatCurrency, publicDescription: $publicDescription, recipientName: $recipientName, invoiceNumber: $invoiceNumber, acceptBtc: $acceptBtc, acceptLn: $acceptLn, acceptLiquid: $acceptLiquid, expiresAt: $expiresAt, linkToPageNym: $linkToPageNym, privateMemo: $privateMemo, isSubmitting: $isSubmitting, result: $result, error: $error)';
}


}

/// @nodoc
abstract mixin class _$InvoiceCreateStateCopyWith<$Res> implements $InvoiceCreateStateCopyWith<$Res> {
  factory _$InvoiceCreateStateCopyWith(_InvoiceCreateState value, $Res Function(_InvoiceCreateState) _then) = __$InvoiceCreateStateCopyWithImpl;
@override @useResult
$Res call({
 int? amountSat, int? fiatAmountMinor, String? fiatCurrency, String publicDescription, String recipientName, String invoiceNumber, bool acceptBtc, bool acceptLn, bool acceptLiquid, DateTime expiresAt, String linkToPageNym, String privateMemo, bool isSubmitting, CreateInvoiceResult? result, String? error
});




}
/// @nodoc
class __$InvoiceCreateStateCopyWithImpl<$Res>
    implements _$InvoiceCreateStateCopyWith<$Res> {
  __$InvoiceCreateStateCopyWithImpl(this._self, this._then);

  final _InvoiceCreateState _self;
  final $Res Function(_InvoiceCreateState) _then;

/// Create a copy of InvoiceCreateState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? amountSat = freezed,Object? fiatAmountMinor = freezed,Object? fiatCurrency = freezed,Object? publicDescription = null,Object? recipientName = null,Object? invoiceNumber = null,Object? acceptBtc = null,Object? acceptLn = null,Object? acceptLiquid = null,Object? expiresAt = null,Object? linkToPageNym = null,Object? privateMemo = null,Object? isSubmitting = null,Object? result = freezed,Object? error = freezed,}) {
  return _then(_InvoiceCreateState(
amountSat: freezed == amountSat ? _self.amountSat : amountSat // ignore: cast_nullable_to_non_nullable
as int?,fiatAmountMinor: freezed == fiatAmountMinor ? _self.fiatAmountMinor : fiatAmountMinor // ignore: cast_nullable_to_non_nullable
as int?,fiatCurrency: freezed == fiatCurrency ? _self.fiatCurrency : fiatCurrency // ignore: cast_nullable_to_non_nullable
as String?,publicDescription: null == publicDescription ? _self.publicDescription : publicDescription // ignore: cast_nullable_to_non_nullable
as String,recipientName: null == recipientName ? _self.recipientName : recipientName // ignore: cast_nullable_to_non_nullable
as String,invoiceNumber: null == invoiceNumber ? _self.invoiceNumber : invoiceNumber // ignore: cast_nullable_to_non_nullable
as String,acceptBtc: null == acceptBtc ? _self.acceptBtc : acceptBtc // ignore: cast_nullable_to_non_nullable
as bool,acceptLn: null == acceptLn ? _self.acceptLn : acceptLn // ignore: cast_nullable_to_non_nullable
as bool,acceptLiquid: null == acceptLiquid ? _self.acceptLiquid : acceptLiquid // ignore: cast_nullable_to_non_nullable
as bool,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime,linkToPageNym: null == linkToPageNym ? _self.linkToPageNym : linkToPageNym // ignore: cast_nullable_to_non_nullable
as String,privateMemo: null == privateMemo ? _self.privateMemo : privateMemo // ignore: cast_nullable_to_non_nullable
as String,isSubmitting: null == isSubmitting ? _self.isSubmitting : isSubmitting // ignore: cast_nullable_to_non_nullable
as bool,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as CreateInvoiceResult?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
