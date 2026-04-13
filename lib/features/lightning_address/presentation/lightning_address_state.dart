import 'package:freezed_annotation/freezed_annotation.dart';

part 'lightning_address_state.freezed.dart';

@freezed
sealed class LightningAddressState with _$LightningAddressState {
  const factory LightningAddressState({
    @Default(true) bool loading,
    @Default(false) bool registering,
    @Default(false) bool walletExists,
    String? lightningAddress,
    String? previousNym,
    String? error,
  }) = _LightningAddressState;
}
