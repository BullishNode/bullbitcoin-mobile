// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';

final class RevealKeychainManifestNostrKeyUsecase {
  final KeychainManifestBackupWalletPort _wallet;

  const RevealKeychainManifestNostrKeyUsecase({
    required KeychainManifestBackupWalletPort wallet,
  }) : _wallet = wallet;

  Future<String> execute(KeychainManifestNostrKeyRecord record) async {
    final source = await _wallet.deriveDefaultWallet();
    if (source.parentFingerprint.toLowerCase() !=
        record.entry.parentFingerprint.toLowerCase()) {
      throw StateError('Nostr key belongs to a different wallet seed');
    }
    final handle = NostrKeychainHandle.deriveFromBip85Path(
      xprvBase58: source.xprvBase58,
      hardenedPath: record.entry.bip85DerivationPath,
    );
    if (handle.publicKeyHex != record.nostrKeyMaterialization.publicKeyHex) {
      throw StateError('Nostr key public-key verification failed');
    }
    return NostrKeychainSecretMaterializer.deriveNsec(
      xprvBase58: source.xprvBase58,
      hardenedPath: record.entry.bip85DerivationPath,
    );
  }
}
