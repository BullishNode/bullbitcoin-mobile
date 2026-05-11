import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';

/// PORT: publishing the user's Nostr kind:0 profile event under their npub.
///
/// Pulled out of the application layer so the LA usecases never reach
/// directly into core relay publishing. The adapter wraps `NostrFacade`;
/// tests inject a fake.
///
/// **Error contract**: both methods throw
/// `LightningAddressNostrPublishFailedException` when the broadcast reached
/// zero relays. Server-side state — if the caller mutated it before
/// publishing — is NOT unwound; the cubit surfaces the failure to the user.
abstract class NostrPublishPort {
  /// Publish a NIP-05 profile (kind:0) event tying the user's npub to their
  /// Lightning Address.
  Future<void> publishProfile({
    required NostrKeychainHandle handle,
    required String name,
    required String nip05,
    required String lud16,
  });

  /// Publish a kind:0 event whose `name` / `nip05` / `lud16` fields are
  /// explicit empty strings, clearing any prior NIP-05 advertisement for
  /// this npub. Empty strings (rather than field omission) defeat clients
  /// that merge kind:0 contents instead of replacing them.
  Future<void> clearProfile({required NostrKeychainHandle handle});
}
