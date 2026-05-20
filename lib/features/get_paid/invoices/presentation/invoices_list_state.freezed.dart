// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'invoices_list_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InvoicesListState {

 List<Invoice> get invoices; int get page; int get pageSize; bool get hasMore; InvoiceStatus? get statusFilter; bool get isLoading; String? get error;
/// Create a copy of InvoicesListState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InvoicesListStateCopyWith<InvoicesListState> get copyWith => _$InvoicesListStateCopyWithImpl<InvoicesListState>(this as InvoicesListState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InvoicesListState&&const DeepCollectionEquality().equals(other.invoices, invoices)&&(identical(other.page, page) || other.page == page)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.statusFilter, statusFilter) || other.statusFilter == statusFilter)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(invoices),page,pageSize,hasMore,statusFilter,isLoading,error);

@override
String toString() {
  return 'InvoicesListState(invoices: $invoices, page: $page, pageSize: $pageSize, hasMore: $hasMore, statusFilter: $statusFilter, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class $InvoicesListStateCopyWith<$Res>  {
  factory $InvoicesListStateCopyWith(InvoicesListState value, $Res Function(InvoicesListState) _then) = _$InvoicesListStateCopyWithImpl;
@useResult
$Res call({
 List<Invoice> invoices, int page, int pageSize, bool hasMore, InvoiceStatus? statusFilter, bool isLoading, String? error
});




}
/// @nodoc
class _$InvoicesListStateCopyWithImpl<$Res>
    implements $InvoicesListStateCopyWith<$Res> {
  _$InvoicesListStateCopyWithImpl(this._self, this._then);

  final InvoicesListState _self;
  final $Res Function(InvoicesListState) _then;

/// Create a copy of InvoicesListState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? invoices = null,Object? page = null,Object? pageSize = null,Object? hasMore = null,Object? statusFilter = freezed,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
invoices: null == invoices ? _self.invoices : invoices // ignore: cast_nullable_to_non_nullable
as List<Invoice>,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,statusFilter: freezed == statusFilter ? _self.statusFilter : statusFilter // ignore: cast_nullable_to_non_nullable
as InvoiceStatus?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InvoicesListState].
extension InvoicesListStatePatterns on InvoicesListState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InvoicesListState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InvoicesListState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InvoicesListState value)  $default,){
final _that = this;
switch (_that) {
case _InvoicesListState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InvoicesListState value)?  $default,){
final _that = this;
switch (_that) {
case _InvoicesListState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Invoice> invoices,  int page,  int pageSize,  bool hasMore,  InvoiceStatus? statusFilter,  bool isLoading,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InvoicesListState() when $default != null:
return $default(_that.invoices,_that.page,_that.pageSize,_that.hasMore,_that.statusFilter,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Invoice> invoices,  int page,  int pageSize,  bool hasMore,  InvoiceStatus? statusFilter,  bool isLoading,  String? error)  $default,) {final _that = this;
switch (_that) {
case _InvoicesListState():
return $default(_that.invoices,_that.page,_that.pageSize,_that.hasMore,_that.statusFilter,_that.isLoading,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Invoice> invoices,  int page,  int pageSize,  bool hasMore,  InvoiceStatus? statusFilter,  bool isLoading,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _InvoicesListState() when $default != null:
return $default(_that.invoices,_that.page,_that.pageSize,_that.hasMore,_that.statusFilter,_that.isLoading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _InvoicesListState extends InvoicesListState {
  const _InvoicesListState({final  List<Invoice> invoices = const [], this.page = 1, this.pageSize = 100, this.hasMore = false, this.statusFilter, this.isLoading = false, this.error}): _invoices = invoices,super._();


 final  List<Invoice> _invoices;
@override@JsonKey() List<Invoice> get invoices {
  if (_invoices is EqualUnmodifiableListView) return _invoices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_invoices);
}

@override final  InvoiceStatus? statusFilter;
@override@JsonKey() final  int page;
@override@JsonKey() final  int pageSize;
@override@JsonKey() final  bool hasMore;
@override@JsonKey() final  bool isLoading;
@override final  String? error;

/// Create a copy of InvoicesListState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InvoicesListStateCopyWith<_InvoicesListState> get copyWith => __$InvoicesListStateCopyWithImpl<_InvoicesListState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InvoicesListState&&const DeepCollectionEquality().equals(other._invoices, _invoices)&&(identical(other.page, page) || other.page == page)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore)&&(identical(other.statusFilter, statusFilter) || other.statusFilter == statusFilter)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_invoices),page,pageSize,hasMore,statusFilter,isLoading,error);

@override
String toString() {
  return 'InvoicesListState(invoices: $invoices, page: $page, pageSize: $pageSize, hasMore: $hasMore, statusFilter: $statusFilter, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class _$InvoicesListStateCopyWith<$Res> implements $InvoicesListStateCopyWith<$Res> {
  factory _$InvoicesListStateCopyWith(_InvoicesListState value, $Res Function(_InvoicesListState) _then) = __$InvoicesListStateCopyWithImpl;
@override @useResult
$Res call({
 List<Invoice> invoices, int page, int pageSize, bool hasMore, InvoiceStatus? statusFilter, bool isLoading, String? error
});




}
/// @nodoc
class __$InvoicesListStateCopyWithImpl<$Res>
    implements _$InvoicesListStateCopyWith<$Res> {
  __$InvoicesListStateCopyWithImpl(this._self, this._then);

  final _InvoicesListState _self;
  final $Res Function(_InvoicesListState) _then;

/// Create a copy of InvoicesListState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? invoices = null,Object? page = null,Object? pageSize = null,Object? hasMore = null,Object? statusFilter = freezed,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_InvoicesListState(
invoices: null == invoices ? _self._invoices : invoices // ignore: cast_nullable_to_non_nullable
as List<Invoice>,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,statusFilter: freezed == statusFilter ? _self.statusFilter : statusFilter // ignore: cast_nullable_to_non_nullable
as InvoiceStatus?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
