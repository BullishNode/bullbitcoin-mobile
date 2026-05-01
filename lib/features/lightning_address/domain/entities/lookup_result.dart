import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';

/// ENTITY: result of looking up a Nostr public key on the pay-service.
///
/// Sealed so UI branches are exhaustive — there is no "active=true with
/// previousNym set" combination to mishandle. Both variants always carry
/// the per-npub `quota` so the deactivate-warning UX has the data it needs
/// without a follow-up round trip.
///
/// Field naming: both variants call the nym `nym`. The "previousNym"
/// terminology is presentation-flavored and stays in the cubit/UI; the
/// domain just knows whether the nym is active or inactive.
sealed class LookupResult {
  const LookupResult();
  NymQuota get quota;
}

/// The npub has an active Lightning Address. `nym` is the currently-served
/// label.
class ActiveLookupResult extends LookupResult {
  final String nym;
  @override
  final NymQuota quota;
  const ActiveLookupResult({required this.nym, required this.quota});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveLookupResult && other.nym == nym && other.quota == quota;

  @override
  int get hashCode => Object.hash(runtimeType, nym, quota);
}

/// The npub has a row, but it's deactivated. `nym` is the deactivated label
/// (still reserved to this npub — the user can reactivate it).
class InactiveLookupResult extends LookupResult {
  final String nym;
  @override
  final NymQuota quota;
  const InactiveLookupResult({required this.nym, required this.quota});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InactiveLookupResult && other.nym == nym && other.quota == quota;

  @override
  int get hashCode => Object.hash(runtimeType, nym, quota);
}
