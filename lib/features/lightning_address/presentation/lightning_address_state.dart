import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
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

    /// Lifetime nym quota for this wallet's npub. `null` until the cubit
    /// has hit the server at least once. Drives the deactivate-warning UX
    /// via `quota.state()` — the UI reads the enum, never the raw counts.
    NymQuota? quota,

    /// True when the most recent lookup attempt failed and the cubit is
    /// showing a `quota` carried over from a prior request. UI may render a
    /// "couldn't refresh" hint; copy decisions still flow through
    /// `quota.state()` against the cached value.
    @Default(false) bool quotaStale,
  }) = _LightningAddressState;
}
