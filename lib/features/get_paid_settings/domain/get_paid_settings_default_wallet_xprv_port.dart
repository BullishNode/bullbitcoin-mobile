/// Derives the default-wallet xprv used to sign/publish the encrypted Nostr
/// backup snapshot.
///
/// This MUST derive identically to the fetch side
/// (`RemoteKeychainRecoveryDefaultWalletXprvAdapter`): the published author key
/// has to equal the key recovery fetches under, or every backup is invisible
/// to recovery (KC-4 obligation 4). The parity is pinned by a test, not by
/// sharing code (the two adapters are deliberately not consolidated in PR23).
abstract interface class GetPaidSettingsDefaultWalletXprvPort {
  Future<GetPaidSettingsDefaultWalletXprv> deriveDefaultWalletXprv();
}

class GetPaidSettingsDefaultWalletXprv {
  final String xprvBase58;
  final String parentFingerprint;

  const GetPaidSettingsDefaultWalletXprv({
    required this.xprvBase58,
    required this.parentFingerprint,
  });
}
