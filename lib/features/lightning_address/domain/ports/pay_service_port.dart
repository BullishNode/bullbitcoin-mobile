import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';

/// Port interface for the pay service.
/// Domain use cases depend on this, not the concrete datasource.
abstract class PayServicePort {
  /// Register a new (or reactivated) Lightning Address. Returns the
  /// `nym@domain` string and the post-register `NymQuota` from the server's
  /// `RegisterResponse.quota` block — saves a follow-up `lookupByNpub`.
  Future<({String address, NymQuota quota})> register({
    required String nym,
    required String ctDescriptor,
    required NostrKeychainHandle authHandle,
    required String verificationNpubHex,
  });

  /// Deactivate the address. Returns the post-delete `NymQuota` (unchanged
  /// — deactivate doesn't free a slot, but the server emits it for symmetry).
  Future<NymQuota> deleteRegistration({
    required String nym,
    required NostrKeychainHandle handle,
  });

  /// Look up a npub. Returns a sealed `LookupResult` (Active / Inactive)
  /// or `null` when the npub has no row at all.
  Future<LookupResult?> lookupByNpub(String npubHex);

  Future<String?> getStoredAddress();

  Future<void> storeAddress(String address);
}

class PayServiceException implements Exception {
  final String message;
  PayServiceException(this.message);

  @override
  String toString() => message;
}
