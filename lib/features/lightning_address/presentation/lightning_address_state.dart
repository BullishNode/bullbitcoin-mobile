import 'package:bb_mobile/features/lightning_address/domain/primitives/nostr_publish_status.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/previous_nym.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'lightning_address_state.freezed.dart';

@freezed
sealed class LightningAddressState with _$LightningAddressState {
  const factory LightningAddressState({
    @Default(true) bool loading,
    @Default(false) bool registering,
    @Default(false) bool walletExists,
    String? lightningAddress,
    @Default([]) List<PreviousNym> previousNyms,
    String? error,
    NymQuota? quota,
    @Default(false) bool quotaStale,
    @Default(NostrPublishStatus.none) NostrPublishStatus nostrPublishStatus,
  }) = _LightningAddressState;
}
